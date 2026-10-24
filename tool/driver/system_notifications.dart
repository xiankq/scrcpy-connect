import 'dart:convert';
import 'dart:io';

import 'dart:math';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../src/process.dart';

const _controllerPackage = 'dev.scrcpyconnect.scrcpy_connect';
const _channel = 'remote_notifications';
const _genericTitle = '设备有新通知';
const _genericBody = '请打开邻接查看';

/// 宿主核验真实 Android 记录、SystemUI 点击及清理；协调器单测覆盖未尝试远端命令，本真实应用运行核验来源/会话及被控前台结果。
///
///
void validateSystemNotificationsReport(
  Map<String, dynamic> report, {
  required String runId,
  required Map<String, dynamic>? osReceipt,
  required bool cleanupConfirmed,
}) {
  final ids = report['sourceNotificationIds'];
  if (report.containsKey('productAcceptanceComplete') ||
      report['systemNotificationsComplete'] != true ||
      report['fixtureRunId'] != runId ||
      ids is! List ||
      ids.length != 2 ||
      ids.any((id) => id is! String || id.isEmpty) ||
      ids.toSet().length != 2 ||
      [
        'permissionGranted',
        'automaticObservationLive',
        'realNotificationEventObserved',
        'exactSourceWithdrawalVerified',
        'notificationsPageOpened',
        'clickedSourceStillLive',
        'remoteSessionUnchanged',
        'fixtureCleanupAcknowledged',
      ].any((key) => report[key] != true)) {
    throw StateError(
      'The app did not complete scoped system notification acceptance.',
    );
  }
  final localIds = osReceipt?['localNotificationIds'];
  if (osReceipt == null ||
      osReceipt['runId'] != runId ||
      osReceipt['channel'] != _channel ||
      osReceipt['genericRecordCount'] != 2 ||
      osReceipt['sourceRecordCount'] != 2 ||
      localIds is! List ||
      localIds.length != 2 ||
      localIds.any((id) => id is! int || id < 100000 || id > 199999) ||
      localIds.toSet().length != 2 ||
      [
        'actualHome',
        'baselineEmpty',
        'genericContentOnly',
        'exactWithdrawal',
        'otherMirrorRetained',
        'foregroundServiceRetained',
        'actualSystemUiTap',
        'targetForegroundUnchanged',
        'ownedSourcesAbsent',
        'ownedMirrorsAbsent',
      ].any((key) => osReceipt[key] != true)) {
    throw StateError(
      'Independent Android system notification evidence is missing or inconsistent.',
    );
  }
  if (!cleanupConfirmed) {
    throw StateError(
      'Exact source and mirrored notification cleanup was not confirmed.',
    );
  }
}

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

class _AndroidNotifications {
  _AndroidNotifications(this.adb, this.controller, this.target, this.output)
    : runId = List.generate(
        16,
        (_) => Random.secure().nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  final String adb;
  final String controller;
  final String target;
  final Directory output;
  final String runId;
  final keys = <String>[];
  final receipt = <String, dynamic>{};
  var cleanupConfirmed = false;
  var posted = false;
  String? targetForeground;
  Set<String> baseline = {};
  String title(String suffix) => 'connect-system-$runId-$suffix';
  String body(String suffix) => 'private-system-body-$runId-$suffix';

  Future<ProcessResult> _run(
    String serial,
    List<String> args, {
    bool binary = false,
  }) => runProcess(
    adb,
    ['-s', serial, ...args],
    stdoutEncoding: binary ? null : utf8,
    timeout: const Duration(seconds: 30),
  );

  Future<String> _shell(String serial, List<String> tokens) async {
    // adb 会拼接 shell 参数；每个 token 都按远端 shell 规则转义，包括带管道符的通知键和夹具正文。
    //
    final result = await _run(serial, ['shell', tokens.map(_quote).join(' ')]);
    if (result.exitCode != 0) {
      // 系统输出可能包含无关通知正文，禁止记录。
      throw StateError(
        'Android command ${tokens.first} failed (${result.exitCode}).',
      );
    }
    return result.stdout as String;
  }

  Future<Set<String>> _keys(String serial) async => const LineSplitter()
      .convert(await _shell(serial, ['cmd', 'notification', 'list']))
      .map((line) => line.trim())
      .where((line) => line.contains('|'))
      .toSet();

  bool _controllerKey(String key) {
    final parts = key.split('|');
    return parts.length >= 5 && parts[1] == _controllerPackage;
  }

  int _id(String key) => int.parse(key.split('|')[2]);

  Future<Set<String>> _sources() async => (await _keys(target)).where((key) {
    final parts = key.split('|');
    return parts.length >= 5 &&
        parts[1] == 'com.android.shell' &&
        key.contains(runId);
  }).toSet();

  Future<Map<String, String>> _mirrors() async {
    final mirrors = <String, String>{};
    for (final key in (await _keys(controller)).where(_controllerKey)) {
      final id = _id(key);
      if (id < 100000 || id > 199999) continue;
      final record = await _shell(controller, [
        'cmd',
        'notification',
        'get',
        key,
      ]);
      if (!record.contains('channel=$_channel ') &&
          !record.contains("mId='$_channel'")) {
        throw StateError(
          'An owned OS notification uses an unexpected channel.',
        );
      }
      mirrors[key] = record;
    }
    return mirrors;
  }

  void _generic(String record) {
    final titleMatch = RegExp(r'android.title=String \(([^\n]*)\)')
        .firstMatch(record);
    final bodyMatch = RegExp(r'android.text=String \(([^\n]*)\)')
        .firstMatch(record);
    if (titleMatch?.group(1) != _genericTitle ||
        bodyMatch?.group(1) != _genericBody ||
        record.contains(runId) ||
        record.contains('com.android.shell')) {
      throw StateError(
        'The owned Android notice did not preserve generic content privacy.',
      );
    }
  }

  Future<void> _wait(Future<bool> Function() ready, String reason) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (await ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(reason);
  }

  Future<String?> _foreground(String serial) async {
    final state = await _shell(serial, ['dumpsys', 'activity', 'activities']);
    final match = RegExp(
      r'(?:mResumedActivity|topResumedActivity)[^\n]*?\bu\d+\s+([^\s}]+)',
    ).firstMatch(state);
    // 真实 Activity 切换可能暂时没有 resumed 记录；缺失不代表前台，也不作为终态检查错误。
    //
    return match?.group(1);
  }

  Future<void> _capture(String name) async {
    final result = await _run(controller, [
      'exec-out',
      'screencap',
      '-p',
    ], binary: true);
    if (result.exitCode != 0 || (result.stdout as List<int>).isEmpty) {
      throw StateError('Controller OS screenshot capture failed.');
    }
    await File('${output.path}/$name.png')
        .writeAsBytes(result.stdout as List<int>, flush: true);
  }

  Future<String> _uiXml() async {
    final path = '/data/local/tmp/connect-system-$runId.xml';
    try {
      await _shell(controller, ['uiautomator', 'dump', '--compressed', path]);
      return await _shell(controller, ['cat', path]);
    } finally {
      await _shell(controller, ['rm', '-f', path]);
    }
  }

  Future<bool> _tapNode(bool Function(Map<String, String>) matches) async {
    final xml = await _uiXml();
    final nodes = <Map<String, String>>[];
    for (final node in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
      final attributes = {
        for (final attr in RegExp(
          r'([\w-]+)="([^"]*)"',
        ).allMatches(node.group(0)!))
          attr.group(1)!: attr.group(2)!,
      };
      if (matches(attributes)) nodes.add(attributes);
    }
    if (nodes.isEmpty) return false;
    if (nodes.length != 1) {
      throw StateError('The Android tap target is ambiguous.');
    }
    final bounds = RegExp(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
        .firstMatch(nodes.single['bounds'] ?? '');
    if (bounds == null) {
      throw StateError('The Android tap target has no exact bounds.');
    }
    final x = (int.parse(bounds.group(1)!) + int.parse(bounds.group(3)!)) ~/ 2;
    final y = (int.parse(bounds.group(2)!) + int.parse(bounds.group(4)!)) ~/ 2;
    await _shell(controller, ['input', 'tap', '$x', '$y']);
    return true;
  }

  Future<bool> allowPermission() => _tapNode(
    (node) =>
        (node['package'] ?? '').endsWith('permissioncontroller') &&
        (node['resource-id'] ?? '').endsWith(':id/permission_allow_button'),
  );

  Future<void> returnAfterFailure() async {
    if (receipt['actualHome'] == true) {
      await _shell(controller, [
        'am',
        'start',
        '-W',
        '-n',
        '$_controllerPackage/.MainActivity',
      ]);
    }
  }

  Future<void> postAfterHome() async {
    baseline = (await _keys(controller)).where(_controllerKey).toSet();
    if ((await _mirrors()).isNotEmpty) {
      throw StateError(
        'The controller must start without stale owned remote notices.',
      );
    }
    if (!baseline.any((key) => _id(key) == 2101)) {
      throw StateError(
        'The real connection foreground-service notice must be present.',
      );
    }
    await _wait(() async {
      targetForeground = await _foreground(target);
      return targetForeground != null;
    }, 'Cannot verify the initial target foreground activity.');
    await _shell(controller, ['input', 'keyevent', 'KEYCODE_HOME']);
    await _wait(() async {
      final current = await _foreground(controller);
      return current != null && !current.startsWith('$_controllerPackage/');
    }, 'Actual HOME did not background the controller.');
    // 先让真实 Activity 生命周期到达 Flutter，再发布新来源。
    await Future<void>.delayed(const Duration(seconds: 1));
    receipt.addAll({
      'runId': runId,
      'channel': _channel,
      'actualHome': true,
      'baselineEmpty': true,
    });
    for (final suffix in ['withdraw', 'click']) {
      posted = true;
      await _shell(target, [
        'cmd',
        'notification',
        'post',
        '-t',
        title(suffix),
        title(suffix),
        body(suffix),
      ]);
      await _wait(() async {
        final mirrors = await _mirrors();
        final added = mirrors.keys.where((key) => !keys.contains(key)).toList();
        if (added.isEmpty) return false;
        if (added.length != 1 || mirrors.length != keys.length + 1) {
          throw StateError(
            'Each source must create exactly one distinct owned OS notice.',
          );
        }
        _generic(mirrors[added.single]!);
        keys.add(added.single);
        return true;
      }, 'A real background source did not create its Android OS notice.');
    }
    final sources = await _sources();
    if (sources.length != 2 ||
        !sources.any((key) => key.contains(title('withdraw'))) ||
        !sources.any((key) => key.contains(title('click')))) {
      throw StateError('Two exact owned source OS records must be present.');
    }
    receipt.addAll({
      'genericRecordCount': keys.length,
      'sourceRecordCount': sources.length,
      'localNotificationIds': keys.map(_id).toList(),
      'genericContentOnly': true,
    });
    await _capture('system-notifications-background');
  }

  Future<void> verifyWithdrawal() async {
    await _wait(
      () async => !(await _keys(controller)).contains(keys[0]),
      'The exact withdrawn source OS key remained active.',
    );
    final active = await _keys(controller);
    if (!active.contains(keys[1]) || !active.containsAll(baseline)) {
      throw StateError(
        'Withdrawing one source changed another OS notice or foreground service.',
      );
    }
    final sources = await _sources();
    if (sources.length != 1 || !sources.single.contains(title('click'))) {
      throw StateError(
        'Only the exact withdrawn target source must disappear.',
      );
    }
    receipt.addAll({
      'exactWithdrawal': true,
      'otherMirrorRetained': true,
      'foregroundServiceRetained': true,
    });
    await _capture('system-notifications-exact-withdrawal');
  }

  Future<void> clickSystemUi() async {
    final mirrors = await _mirrors();
    if (mirrors.length != 1 || !mirrors.containsKey(keys[1])) {
      throw StateError(
        'The exact surviving OS notice must be the sole tap candidate.',
      );
    }
    _generic(mirrors.values.single);
    await _shell(controller, ['cmd', 'statusbar', 'expand-notifications']);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _capture('system-notifications-system-ui');
    await _wait(
      () => _tapNode(
        (node) =>
            node['package'] == 'com.android.systemui' &&
            node['text'] == _genericTitle,
      ),
      'The actual SystemUI notice was not tappable.',
    );
    await _wait(
      () async =>
          (await _foreground(controller))?.startsWith('$_controllerPackage/') ==
          true,
      'The actual OS notice tap did not foreground the controller.',
    );
    String? targetAfterClick;
    await _wait(() async {
      targetAfterClick = await _foreground(target);
      return targetAfterClick != null;
    }, 'Cannot verify the target foreground after the OS click.');
    if (targetAfterClick != targetForeground) {
      throw StateError(
        'The OS notice tap changed the target foreground activity.',
      );
    }
    receipt.addAll({
      'actualSystemUiTap': true,
      'targetForegroundUnchanged': true,
    });
  }

  Future<void> captureOpenedPage() => _capture('system-notifications-opened');

  Future<void> verifyCleanup() async {
    await _wait(() async {
      final targetKeys = await _keys(target);
      final controllerKeys = await _keys(controller);
      return !targetKeys.any((key) => key.contains(runId)) &&
          keys.every((key) => !controllerKeys.contains(key));
    }, 'This run’s exact source or mirrored notices did not clear.');
    final remaining = await _keys(controller);
    if (posted && !remaining.containsAll(baseline)) {
      throw StateError(
        'Owned fixture cleanup changed pre-existing controller notices.',
      );
    }
    receipt.addAll({'ownedSourcesAbsent': true, 'ownedMirrorsAbsent': true});
    cleanupConfirmed = posted && keys.length == 2;
  }
}

Future<void> main() async {
  final adb = Platform.environment['CONNECT_E2E_ADB'];
  final controller = Platform.environment['CONNECT_E2E_DEVICE'];
  final target = Platform.environment['CONNECT_E2E_TARGET'];
  if (adb == null ||
      adb.isEmpty ||
      controller == null ||
      target == null ||
      !controller.startsWith('emulator-') ||
      !target.startsWith('emulator-') ||
      controller == target) {
    throw StateError(
      'Select explicit, distinct controller and target AVDs with CONNECT_E2E_ADB, CONNECT_E2E_DEVICE and CONNECT_E2E_TARGET.',
    );
  }
  final path =
      Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
      '/tmp/connect-e2e/system-notifications';
  if (!path.startsWith('/tmp/') || path.split('/').contains('..')) {
    throw StateError('System notification artifacts must remain under /tmp/.');
  }
  final output = await Directory(path).create(recursive: true);
  final fixture = _AndroidNotifications(adb, controller, target, output);
  final errors = <String>[];
  var finished = false;
  Future<void>? coordination;
  Future<void> finishHost() async {
    finished = true;
    await coordination;
  }

  try {
    final driver = await FlutterDriver.connect();
    Future<Map<String, dynamic>> extension([Map<String, String>? args]) async =>
        (await driver.serviceClient
                .callServiceExtension(
                  'ext.connect.systemNotifications',
                  isolateId: driver.appIsolate.id,
                  args: args,
                )
                .timeout(const Duration(seconds: 15)))
            .json ??
        {};
    coordination =
        () async {
          final acknowledged = <String>{};
          final failed = <String>{};
          final deadline = DateTime.now().add(const Duration(minutes: 8));
          while (!finished && DateTime.now().isBefore(deadline)) {
            Map<String, dynamic> state;
            try {
              state = await extension();
            } catch (error) {
              if (finished) return;
              if (!error.toString().contains('Method not found') &&
                  !error.toString().contains('-32601')) {
                rethrow;
              }
              await Future<void>.delayed(const Duration(milliseconds: 200));
              continue;
            }
            final stage = state['stage'];
            if (stage == 'complete') return;
            if (stage is String &&
                !acknowledged.contains(stage) &&
                !failed.contains(stage)) {
              try {
                String? action;
                switch (stage) {
                  case 'waiting-fixture':
                    action = 'fixture';
                  case 'requesting-permission':
                    if (await fixture.allowPermission()) {
                      acknowledged.add(stage);
                    }
                  case 'ready-background':
                    await fixture.postAfterHome();
                    action = 'posted';
                  case 'awaiting-withdrawal':
                    await fixture.verifyWithdrawal();
                    action = 'withdrawal';
                  case 'awaiting-system-click':
                    await fixture.clickSystemUi();
                    action = 'clicked';
                  case 'awaiting-page-capture':
                    await fixture.captureOpenedPage();
                    action = 'page-captured';
                  case 'awaiting-cleanup':
                    await fixture.verifyCleanup();
                    action = 'cleanup';
                }
                if (action != null) {
                  await extension({'action': action, 'runId': fixture.runId});
                  acknowledged.add(stage);
                  if (action == 'cleanup') return;
                }
              } catch (error) {
                // 失败后继续协调，使应用 finally 能精确移除其来源并等待清理回执。
                //
                errors.add('Android stage $stage failed: $error');
                failed.add(stage);
                await fixture.returnAfterFailure();
                await extension({
                  'runId': fixture.runId,
                  'error': 'Android evidence failed',
                });
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          if (!finished) {
            throw StateError('System notification host handshake timed out.');
          }
        }().catchError((Object error) {
          errors.add('Host coordination failed: $error');
        });

    await integrationDriver(
      driver: driver,
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        // integrationDriver 在回调后退出，无论成功失败都须在返回前完成清理回执与宿主工作。
        //
        await finishHost();
        final report = {...?data}..remove('screenshots');
        report.addAll({
          'androidOsReceipt': fixture.receipt,
          'fixtureCleanupConfirmed': fixture.cleanupConfirmed,
          'controllerAvd': controller,
          'targetAvd': target,
          'hostErrors': errors,
          'evidenceScope':
              'real-Android-remote-notifications-SystemUI-navigation',
          'commandAbsenceEvidence':
              'coordinator-unit-tests; E2E checks observable remote state',
        });
        await File('${output.path}/result.json')
            .writeAsString(jsonEncode(report), flush: true);
        if (errors.isNotEmpty) {
          throw StateError(
            'Independent Android checks failed; see scoped /tmp report.',
          );
        }
        validateSystemNotificationsReport(
          report,
          runId: fixture.runId,
          osReceipt: fixture.receipt,
          cleanupConfirmed: fixture.cleanupConfirmed,
        );
      },
    );
  } finally {
    await finishHost();
  }
}
