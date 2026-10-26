import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../../scripts/src/process.dart';

const fixturePackage = 'dev.scrcpyconnect.notificationfixture';
const controllerPackage = 'dev.scrcpyconnect.scrcpy_connect';
String quote(String text) => "'${text.replaceAll("'", "'\\''")}'";

Future<void> main() async {
  final adb = Platform.environment['CONNECT_E2E_ADB']!;
  final target = Platform.environment['CONNECT_E2E_TARGET']!;
  final controller = Platform.environment['CONNECT_E2E_DEVICE']!;
  final manualSystemUi =
      Platform.environment['CONNECT_E2E_MANUAL_SYSTEM_UI'] == '1';
  if (!target.startsWith('emulator-') ||
      !controller.startsWith('emulator-') ||
      target == controller) {
    throw StateError(
      'Distinct explicit controller and target AVDs are required.',
    );
  }
  final output = Directory(
    Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
        '/tmp/connect-e2e/notification-requirements',
  );
  if (!output.path.startsWith('/tmp/') ||
      output.path.split('/').contains('..')) {
    throw StateError('Use scoped temporary output.');
  }
  await output.create(recursive: true);
  final runId = List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  final receipt = <String, dynamic>{'runId': runId};
  final snapshotRunId = '$runId-snapshot';
  final errors = <String>[];
  var otherControllerNotices = <String>{};
  var installed = false;
  var snapshotPosted = false;
  var temporaryPin = false;
  var cleaned = false;
  var finished = false;
  var reportWritten = false;
  Future<void>? coordination;
  Future<String> shell(String serial, List<String> args) async {
    final result = await runProcess(adb, [
      '-s',
      serial,
      'shell',
      args.map(quote).join(' '),
    ]);
    if (result.exitCode != 0) {
      if (args.length == 3 &&
          args[0] == 'pm' &&
          args[1] == 'path' &&
          result.exitCode == 1 &&
          (result.stdout as String).trim().isEmpty) {
        return '';
      }
      throw StateError('Android ${args.first} failed (${result.exitCode}).');
    }
    return result.stdout as String;
  }

  Future<void> capture(String serial, String name) async {
    final result = await runProcess(adb, [
      '-s',
      serial,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null);
    if (result.exitCode != 0) throw StateError('Screenshot failed.');
    await File('${output.path}/$name.png')
        .writeAsBytes(result.stdout as List<int>, flush: true);
  }

  Future<String> hierarchy(String serial) async {
    final path = '/data/local/tmp/connect-notification-$runId.xml';
    try {
      await shell(serial, ['uiautomator', 'dump', path]);
      return await shell(serial, ['cat', path]);
    } finally {
      await shell(serial, ['rm', '-f', path]);
    }
  }

  Future<void> activity(String action, {String? fixtureRunId}) async {
    await shell(target, [
      'am',
      'start',
      '-W',
      '-n',
      '$fixturePackage/.NotificationFixtureActivity',
      '-a',
      '$fixturePackage.$action',
      '--es',
      'runId',
      fixtureRunId ?? runId,
    ]);
  }

  Future<List<String>> keys(String serial) async => const LineSplitter()
      .convert(await shell(serial, ['cmd', 'notification', 'list']))
      .where((key) => key.contains('|'))
      .toList();
  Future<List<int>> sourceIds() async =>
      (await keys(target))
          .where(
            (key) => key.split('|')[1] == fixturePackage && key.contains(runId),
          )
          .map((key) => int.parse(key.split('|')[2]))
          .toList()
        ..sort();
  Future<Map<String, String>> snapshotSources() async {
    final result = <String, String>{};
    for (final key in await keys(target)) {
      final parts = key.split('|');
      if (parts.length > 3 &&
          parts[1] == fixturePackage &&
          parts[3] == 'notification-fixture-$snapshotRunId') {
        result[key] = await shell(target, ['cmd', 'notification', 'get', key]);
      }
    }
    return result;
  }

  Future<Map<String, String>> mirrors() async {
    final result = <String, String>{};
    for (final key in await keys(controller)) {
      final parts = key.split('|');
      final id = int.tryParse(parts[2]) ?? 0;
      if (parts[1] == controllerPackage && id >= 100000 && id <= 199999) {
        result[key] = await shell(controller, [
          'cmd',
          'notification',
          'get',
          key,
        ]);
      }
    }
    return result;
  }

  Future<void> wait(Future<bool> Function() ready, String reason) async {
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    while (DateTime.now().isBefore(deadline)) {
      if (await ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(reason);
  }

  Future<void> cleanup() async {
    if (!installed || cleaned) return;
    final failures = <String>[];
    if (temporaryPin) {
      try {
        await shell(target, ['locksettings', 'clear', '--old', '483921']);
        temporaryPin = false;
        await shell(target, ['input', 'keyevent', 'KEYCODE_WAKEUP']);
        await shell(target, ['wm', 'dismiss-keyguard']);
      } catch (_) {
        failures.add('Temporary target PIN cleanup failed.');
      }
    }
    try {
      await activity('CLEANUP');
      if (snapshotPosted) {
        await activity('CLEANUP', fixtureRunId: snapshotRunId);
      }
    } catch (_) {
      failures.add('Fixture cleanup action failed.');
    }
    // 前序清理失败仍尝试卸载；安装前已确立所有权，不触碰已有包。
    //
    try {
      final result = await runProcess(adb, [
        '-s',
        target,
        'uninstall',
        fixturePackage,
      ]);
      if (result.exitCode != 0 ||
          (await shell(target, [
            'pm',
            'path',
            fixturePackage,
          ])).trim().isNotEmpty) {
        throw StateError('Owned fixture uninstall failed.');
      }
    } catch (_) {
      failures.add('Owned fixture uninstall failed.');
    }
    try {
      await wait(
        () async => (await sourceIds()).isEmpty && (await mirrors()).isEmpty,
        'Owned source and mirror cleanup failed.',
      );
    } catch (_) {
      failures.add('Owned source or mirror cleanup failed.');
    }
    cleaned = failures.isEmpty;
    receipt['fixtureCleanupConfirmed'] = cleaned;
    if (!cleaned) throw StateError(failures.join(' '));
  }

  try {
    if ((await shell(target, [
      'pm',
      'path',
      fixturePackage,
    ])).trim().isNotEmpty) {
      throw StateError('Refuse replacing pre-existing fixture.');
    }
    final install = await runProcess(adb, [
      '-s',
      target,
      'install',
      '/tmp/connect-notification-fixture/notification-fixture.apk',
    ]);
    if (install.exitCode != 0) throw StateError('Fixture install failed.');
    installed = true;
    await shell(target, [
      'pm',
      'grant',
      fixturePackage,
      'android.permission.POST_NOTIFICATIONS',
    ]);
    await activity('CREATE_REQUIREMENTS');
    await wait(
      () async => jsonEncode(await sourceIds()) == '[0,1,4]',
      'Actual fixture source records missing.',
    );
    final driver = await FlutterDriver.connect();
    Future<Map<String, dynamic>> extension([Map<String, String>? args]) async =>
        (await driver.serviceClient.callServiceExtension(
          'ext.connect.notificationRequirements',
          isolateId: driver.appIsolate.id,
          args: args,
        )).json ??
        {};
    coordination =
        () async {
          final done = <String>{};
          String? previousStage;
          final deadline = DateTime.now().add(const Duration(minutes: 8));
          while (!finished && DateTime.now().isBefore(deadline)) {
            Map<String, dynamic> state;
            try {
              state = await extension();
            } catch (error) {
              if (!error.toString().contains('Method not found') &&
                  !error.toString().contains('-32601')) {
                rethrow;
              }
              await Future<void>.delayed(const Duration(milliseconds: 200));
              continue;
            }
            final stage = state['stage'];
            if (stage != previousStage && stage is String) {
              stdout.writeln('Notification requirements stage: $stage');
              previousStage = stage;
            }
            if (stage == 'complete') return;
            if (stage == 'requesting-permission' && !manualSystemUi) {
              final xml = await hierarchy(controller);
              final match = RegExp(
                r'resource-id="[^"]+:id/permission_allow_button"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
              ).firstMatch(xml);
              if (match != null) {
                final values = [
                  for (var i = 1; i <= 4; i++) int.parse(match.group(i)!),
                ];
                await shell(controller, [
                  'input',
                  'tap',
                  '${(values[0] + values[2]) ~/ 2}',
                  '${(values[1] + values[3]) ~/ 2}',
                ]);
              }
            }
            if (stage == 'connecting' && !manualSystemUi) {
              // 仅确认被控设备正常的 ADB 授权对话框。
              final xml = await hierarchy(target);
              if (xml.contains('Allow USB debugging?') ||
                  xml.contains('Allow debugging?')) {
                final match = RegExp(
                  r'text="Allow"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
                ).firstMatch(xml);
                if (match != null) {
                  final numbers = [
                    for (var i = 1; i <= 4; i++) int.parse(match.group(i)!),
                  ];
                  await shell(target, [
                    'input',
                    'tap',
                    '${(numbers[0] + numbers[2]) ~/ 2}',
                    '${(numbers[1] + numbers[3]) ~/ 2}',
                  ]);
                }
              }
            }
            if (stage is String &&
                !done.contains(stage) &&
                stage != 'connecting') {
              try {
                String? ack;
                switch (stage) {
                  case 'waiting-fixture':
                    ack = 'fixture';
                  case 'baseline':
                    if ((await mirrors()).isNotEmpty) {
                      throw StateError(
                        'Initial snapshot created OS reminders.',
                      );
                    }
                    otherControllerNotices = (await keys(controller))
                        .where((key) {
                          final parts = key.split('|');
                          final id = int.tryParse(parts[2]) ?? 0;
                          return parts[1] == controllerPackage &&
                              (id < 100000 || id > 199999);
                        })
                        .toSet();
                    receipt['quietBaseline'] = true;
                    ack = 'baseline';
                  case 'opened':
                    await wait(() async {
                      final result = await runProcess(adb, [
                        '-s',
                        target,
                        'shell',
                        'run-as',
                        fixturePackage,
                        'cat',
                        'files/opens/$runId.json',
                      ]);
                      if (result.exitCode != 0) return false;
                      final opened = jsonDecode(
                        result.stdout as String,
                      ) as Map<String, dynamic>;
                      return opened['runId'] == runId &&
                          opened['notificationId'] == 0 &&
                          opened['count'] == 1;
                    }, 'Original PendingIntent did not deliver exactly once.');
                    final activities = await shell(target, [
                      'dumpsys',
                      'activity',
                      'activities',
                    ]);
                    if (!RegExp(
                      '(?:mResumedActivity|topResumedActivity)[^\n]*$fixturePackage',
                    ).hasMatch(activities)) {
                      throw StateError('Original app is not foreground.');
                    }
                    await capture(target, 'target-original-open');
                    receipt['originalOpenReceipt'] = {
                      'notificationId': 0,
                      'count': 1,
                    };
                    ack = 'opened';
                  case 'lock-target':
                    final pin = await shell(target, [
                      'locksettings',
                      'set-pin',
                      '483921',
                    ]);
                    if (!pin.toLowerCase().contains('pin set')) {
                      throw StateError('Cannot prepare isolated target lock.');
                    }
                    temporaryPin = true;
                    await shell(target, ['input', 'keyevent', 'KEYCODE_SLEEP']);
                    await shell(target, [
                      'input',
                      'keyevent',
                      'KEYCODE_WAKEUP',
                    ]);
                    await wait(
                      () async => (await shell(target, [
                        'dumpsys',
                        'window',
                        'policy',
                      ])).contains('showing=true'),
                      'Target keyguard not showing.',
                    );
                    ack = 'target-locked';
                  case 'locked-opened':
                    final opened = jsonDecode(
                      await shell(target, [
                        'run-as',
                        fixturePackage,
                        'cat',
                        'files/opens/$runId.json',
                      ]),
                    ) as Map<String, dynamic>;
                    if (opened['count'] != 1 ||
                        !(await shell(target, [
                          'dumpsys',
                          'window',
                          'policy',
                        ])).contains('showing=true')) {
                      throw StateError(
                        'Locked card replayed original action or bypassed keyguard.',
                      );
                    }
                    await capture(target, 'target-keyguard');
                    await capture(controller, 'controller-keyguard-fallback');
                    receipt['lockedOpenDoesNotReplayOrUnlock'] = true;
                    ack = 'locked-opened';
                  case 'unlock-target':
                    await shell(target, [
                      'locksettings',
                      'clear',
                      '--old',
                      '483921',
                    ]);
                    temporaryPin = false;
                    await shell(target, [
                      'input',
                      'keyevent',
                      'KEYCODE_WAKEUP',
                    ]);
                    await shell(target, ['wm', 'dismiss-keyguard']);
                    ack = 'target-unlocked';
                  case 'single-cleared':
                    await wait(
                      () async => jsonEncode(await sourceIds()) == '[1,4]',
                      'Single UI clear changed wrong source IDs.',
                    );
                    receipt['singleClearExact'] = true;
                    ack = 'single-cleared';
                  case 'all-cleared':
                    await wait(
                      () async => jsonEncode(await sourceIds()) == '[4]',
                      'All UI clear did not preserve ongoing source.',
                    );
                    receipt['allClearPreservesOngoing'] = true;
                    ack = 'all-cleared';
                  case 'post-foreground':
                    await activity('POST_REQUIREMENT');
                    ack = 'posted-foreground';
                  case 'foreground-mirrored':
                    await wait(
                      () async => (await mirrors()).length == 1,
                      'Foreground source did not reach host OS.',
                    );
                    final records = await mirrors();
                    final record = records.values.single;
                    if (!record.contains('设备有新通知') ||
                        !record.contains('请打开邻接查看') ||
                        record.contains(runId) ||
                        record.contains('Synthetic requirements') ||
                        !record.contains('remote_notifications')) {
                      throw StateError('OS mirror privacy/channel mismatch.');
                    }
                    final current = await shell(controller, [
                      'dumpsys',
                      'activity',
                      'activities',
                    ]);
                    if (!RegExp(
                      '(?:mResumedActivity|topResumedActivity)[^\n]*$controllerPackage',
                    ).hasMatch(current)) {
                      throw StateError(
                        'Controller was not actually foreground.',
                      );
                    }
                    await capture(controller, 'controller-foreground-mirror');
                    receipt['foregroundOsKey'] = records.keys.single;
                    receipt['foregroundGenericPrivacy'] = true;
                    ack = 'foreground-mirrored';
                  case 'withdraw-target':
                    await activity('WITHDRAW_REQUIREMENT');
                    ack = 'target-withdrawn';
                  case 'withdrawn':
                    await wait(
                      () async =>
                          (await mirrors()).isEmpty &&
                          jsonEncode(await sourceIds()) == '[4]',
                      'Target withdrawal did not retract exact host mirror.',
                    );
                    if (!(await keys(controller))
                        .toSet()
                        .containsAll(otherControllerNotices)) {
                      throw StateError(
                        'Withdrawing a mirror changed another controller notice.',
                      );
                    }
                    receipt['otherControllerNoticesRetained'] = true;
                    receipt['targetWithdrawalRetractsMirror'] = true;
                    ack = 'withdrawn';
                  case 'snapshot-create':
                    snapshotPosted = true;
                    await activity(
                      'CREATE_SNAPSHOT',
                      fixtureRunId: snapshotRunId,
                    );
                    var records = <String, String>{};
                    await wait(() async {
                      records = await snapshotSources();
                      if (records.length != 3) return false;
                      final big = records.entries
                          .singleWhere(
                            (entry) => entry.key.split('|')[2] == '0',
                          )
                          .value;
                      final inbox = records.entries
                          .singleWhere(
                            (entry) => entry.key.split('|')[2] == '1',
                          )
                          .value;
                      final messages = records.entries
                          .singleWhere(
                            (entry) => entry.key.split('|')[2] == '2',
                          )
                          .value;
                      return big.contains('Expanded title') &&
                          big.contains('Real expanded body') &&
                          inbox.contains('Alice: first message') &&
                          inbox.contains('Bob: latest message') &&
                          messages.contains('Team chat') &&
                          messages.contains('Latest');
                    }, 'Owned Android expanded notification records missing.');
                    await File('${output.path}/target-snapshot-create.json')
                        .writeAsString(jsonEncode(records), flush: true);
                    receipt['snapshotCreateAndroidVerified'] = true;
                    ack = 'snapshot-created';
                  case 'snapshot-update':
                    await activity(
                      'UPDATE_SNAPSHOT',
                      fixtureRunId: snapshotRunId,
                    );
                    var records = <String, String>{};
                    await wait(() async {
                      records = await snapshotSources();
                      if (records.length != 3) return false;
                      final big = records.entries
                          .singleWhere(
                            (entry) => entry.key.split('|')[2] == '0',
                          )
                          .value;
                      return big.contains('Updated expanded title') &&
                          big.contains('Updated real expanded body');
                    }, 'Owned Android snapshot revision did not update.');
                    await File('${output.path}/target-snapshot-update.json')
                        .writeAsString(jsonEncode(records), flush: true);
                    receipt['snapshotUpdateAndroidVerified'] = true;
                    ack = 'snapshot-updated';
                  case 'snapshot-withdraw':
                    await activity('CLEANUP', fixtureRunId: snapshotRunId);
                    await wait(
                      () async => (await snapshotSources()).isEmpty,
                      'Android snapshot notifications remain after withdrawal.',
                    );
                    await File('${output.path}/target-snapshot-withdraw.json')
                        .writeAsString(
                          jsonEncode(await snapshotSources()),
                          flush: true,
                        );
                    receipt['snapshotWithdrawAndroidVerified'] = true;
                    receipt['expandedSnapshotAndroidVerified'] = true;
                    ack = 'snapshot-withdrawn';
                  case 'cleanup':
                    await cleanup();
                    ack = 'cleanup';
                }
                if (ack != null) {
                  await extension({'action': ack, 'runId': runId});
                  done.add(stage);
                }
              } catch (error) {
                errors.add('$stage: $error');
                done.add(stage);
                await extension({'error': '$stage failed', 'runId': runId});
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }().catchError((Object error) {
          errors.add('Host coordination: $error');
        });
    await integrationDriver(
      driver: driver,
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        finished = true;
        await coordination;
        try {
          await cleanup();
        } catch (error) {
          errors.add('Final cleanup: $error');
        }
        final report = {...?data}..remove('screenshots');
        report.addAll({
          'androidOsReceipt': receipt,
          'hostErrors': errors,
          'controllerAvd': controller,
          'targetAvd': target,
          'manualSystemUi': manualSystemUi,
        });
        await File('${output.path}/result.json')
            .writeAsString(jsonEncode(report), flush: true);
        reportWritten = true;
        if (errors.isNotEmpty ||
            report['notificationRequirementsComplete'] != true ||
            report['snapshotCreateEventUiVerified'] != true ||
            report['snapshotUpdateEventUiVerified'] != true ||
            report['snapshotWithdrawEventUiVerified'] != true ||
            receipt['snapshotCreateAndroidVerified'] != true ||
            receipt['snapshotUpdateAndroidVerified'] != true ||
            receipt['snapshotWithdrawAndroidVerified'] != true ||
            !cleaned) {
          throw StateError(
            'Notification requirements failed; see scoped result.json.',
          );
        }
      },
    );
  } catch (error) {
    errors.add('Acceptance failed: $error');
    rethrow;
  } finally {
    finished = true;
    await coordination;
    try {
      await cleanup();
    } catch (error) {
      errors.add('Cleanup: $error');
    }
    if (!reportWritten) {
      await File('${output.path}/result.json').writeAsString(
        jsonEncode({
          'notificationRequirementsComplete': false,
          'androidOsReceipt': receipt,
          'hostErrors': errors,
          'controllerAvd': controller,
          'targetAvd': target,
          'manualSystemUi': manualSystemUi,
        }),
        flush: true,
      );
    }
  }
}
