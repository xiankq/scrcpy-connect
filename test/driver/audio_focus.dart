import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../../scripts/src/process.dart';
import '../../scripts/src/android_sdk.dart';
import 'support/cleanup.dart';

const fixturePackage = 'dev.scrcpyconnect.focusfixture';

Future<void> main() async {
  final directory = Directory(
    Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ?? '/tmp/connect-e2e',
  );
  await directory.create(recursive: true);
  final driver = await FlutterDriver.connect();
  var hostFinished = false;
  Object? fixtureError;
  StackTrace? fixtureStack;
  final operation =
      driveFocus(driver, directory, shouldStop: () => hostFinished).catchError((
        Object error,
        StackTrace stack,
      ) async {
        fixtureError = error;
        fixtureStack = stack;
        hostFinished = true;
        try {
          await driverRpc(driver.close());
        } catch (closeError) {
          stderr.writeln('AudioFocus driver shutdown failed: $closeError');
        }
      });
  Future<void> finishFixture() async {
    hostFinished = true;
    await operation;
    if (fixtureError != null) {
      Error.throwWithStackTrace(fixtureError!, fixtureStack!);
    }
  }

  await withDriverCleanup(
    () async {
      await integrationDriver(
        driver: driver,
        writeResponseOnFailure: true,
        responseDataCallback: (data) async {
          await finishFixture();
          final metadata = {...?data}..remove('screenshots');
          await File('${directory.path}/audio-focus-result.json')
              .writeAsString(jsonEncode(metadata));
          if (metadata['audioFocusAcceptanceComplete'] != true) {
            throw StateError(
              'The app did not complete external audio focus acceptance.',
            );
          }
        },
      );
    },
    () => {
      'audio-focus fixture': finishFixture,
      'driver connection': () => driverRpc(driver.close()),
    },
  );
}

Future<void> driveFocus(
  FlutterDriver driver,
  Directory evidence, {
  required bool Function() shouldStop,
}) async {
  final serial = Platform.environment['CONNECT_E2E_DEVICE'];
  if (serial == null || !RegExp(r'^emulator-\d+$').hasMatch(serial)) {
    throw StateError(
      'Set CONNECT_E2E_DEVICE to a dedicated controller emulator.',
    );
  }
  final sdk = androidSdkPath();
  final adb =
      Platform.environment['CONNECT_E2E_ADB'] ?? '$sdk/platform-tools/adb';
  final apk = Platform.environment['CONNECT_E2E_FOCUS_APK'];
  if (apk == null || !await File(apk).exists()) {
    throw StateError(
      'Run scripts/build_fixture.dart audio-focus and set CONNECT_E2E_FOCUS_APK.',
    );
  }
  final buildTools = latestAndroidVersion('$sdk/build-tools');
  final badging = await runProcess(androidSdkTool(buildTools.path, 'aapt2'), [
    'dump',
    'badging',
    apk,
  ]);
  final package = RegExp(
    r"^package: name='([^']+)'",
    multiLine: true,
  ).firstMatch('${badging.stdout}')?.group(1);
  if (badging.exitCode != 0 || package != fixturePackage) {
    throw StateError(
      'Refusing an APK outside the dedicated audio focus fixture.',
    );
  }
  Future<String> run(List<String> args) async {
    final result = await runProcess(adb, [
      '-s',
      serial,
      ...args,
    ], timeout: const Duration(seconds: 25));
    if (result.exitCode != 0) {
      throw StateError('Official Android tool failed: ${result.stderr}');
    }
    return '${result.stdout}';
  }

  Future<Map<String, dynamic>> state([
    Map<String, String> args = const {},
  ]) async =>
      (await driver.serviceClient
              .callServiceExtension(
                'ext.connect.audioFocus',
                isolateId: driver.appIsolate.id,
                args: args,
              )
              .timeout(const Duration(seconds: 10)))
          .json ??
      {};
  Future<Map<String, dynamic>> until(
    bool Function(Map<String, dynamic>) accept,
    String reason,
  ) async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    Map<String, dynamic> last = {};
    while (DateTime.now().isBefore(end)) {
      last = await state({'action': 'status'});
      if (accept(last)) return last;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('$reason: ${jsonEncode(last)}');
  }

  Map<String, dynamic> native(Map<String, dynamic> snapshot, String key) =>
      Map<String, dynamic>.from(
        (snapshot['native'] as Map?)?[key] as Map? ?? {},
      );
  bool inactive(Map<String, dynamic> snapshot) {
    final ids = (snapshot['owned'] as Map).values.toSet();
    return !((snapshot['audio'] as Map?)?['sources'] as List? ?? [])
        .whereType<Map<Object?, Object?>>()
        .any(
          (s) =>
              ids.contains(s['sourceId']) &&
              ['playing', 'paused', 'starting'].contains(s['status']),
        );
  }

  var installed = false;
  var fixtureActive = false;
  var foregroundRestoreNeeded = false;
  String? xmlPath;
  Future<void> release() async {
    await withDriverCleanup(
      () async {},
      () => {
        'fixture audio focus': () async {
          if (!fixtureActive) return;
          await run([
            'shell',
            'am',
            'start',
            '-W',
            '-n',
            '$fixturePackage/.FocusActivity',
            '--es',
            'mode',
            'release',
          ]);
          fixtureActive = false;
        },
        'controller foreground': () async {
          await run([
            'shell',
            'am',
            'start',
            '-W',
            '-n',
            'dev.scrcpyconnect.scrcpy_connect/.MainActivity',
          ]);
          foregroundRestoreNeeded = false;
        },
      },
    );
  }

  Future<void> acquire(String mode, String runId) async {
    // 命令回执丢失时，设备也可能已经获得焦点，仍须释放。
    fixtureActive = true;
    foregroundRestoreNeeded = true;
    await run([
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$fixturePackage/.FocusActivity',
      '--es',
      'mode',
      mode,
      '--es',
      'run_id',
      runId,
    ]);
    xmlPath = '/sdcard/Download/$runId.xml';
    await run(['shell', 'uiautomator', 'dump', '--compressed', xmlPath!]);
    final xml = await run(['shell', 'cat', xmlPath!]);
    await File('${evidence.path}/audio-focus-$mode.xml').writeAsString(xml);
    if (!xml.contains('RUN=$runId MODE=$mode RESULT=1')) {
      throw StateError(
        'The real external app did not receive AUDIOFOCUS_REQUEST_GRANTED.',
      );
    }
  }

  final seen = <String>{};
  final deadline = DateTime.now().add(const Duration(minutes: 6));
  await withDriverCleanup(
    () async {
      while (DateTime.now().isBefore(deadline)) {
        if (shouldStop()) return;
        Map<String, dynamic> current;
        try {
          current = await state();
        } catch (error) {
          if (shouldStop()) return;
          if (!error.toString().contains('ext.connect.audioFocus') &&
              !error.toString().contains('Method not found')) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final stage = '${current['stage']}';
        final runId = '${current['runId']}';
        if (!RegExp(r'^focus-[0-9]+$').hasMatch(runId)) {
          throw StateError('Invalid fixture identity.');
        }
        if (seen.add(stage)) {
          switch (stage) {
            case 'prepare':
              final existing = await run([
                'shell',
                'pm',
                'list',
                'packages',
                fixturePackage,
              ]);
              if (existing.split('\n').contains('package:$fixturePackage')) {
                await run(['uninstall', fixturePackage]);
              }
              installed = true;
              await run(['install', apk]);
              await state({'ack': stage});
            case 'transient':
              await acquire('transient', runId);
              final first = await until(
                (s) => ['1', '2'].every((k) {
                  final n = native(s, k);
                  return n['focusPaused'] == true &&
                      n['backgroundPaused'] == false &&
                      n['playState'] == 'paused';
                }),
                'Both actual shared players must pause for external transient loss',
              );
              if (native(first, '1')['manualPaused'] != true ||
                  native(first, '2')['manualPaused'] != false) {
                throw StateError(
                  'Manual and focus pause flags were conflated.',
                );
              }
              await Future<void>.delayed(const Duration(milliseconds: 400));
              final stable = await state({'action': 'status'});
              await Future<void>.delayed(const Duration(milliseconds: 700));
              final after = await state({'action': 'status'});
              for (final k in ['1', '2']) {
                if (native(after, k)['backend'] != 'media_codec' ||
                    ((native(after, k)['positionMs'] as int) -
                                (native(stable, k)['positionMs'] as int))
                            .abs() >
                        40) {
                  throw StateError(
                    'Shared playback clock advanced after actual focus pause.',
                  );
                }
              }
              await File('${evidence.path}/audio-focus-transient.json')
                  .writeAsString(jsonEncode(after));
              await release();
              await until(
                (s) =>
                    native(s, '1')['focusPaused'] == false &&
                    native(s, '1')['playState'] == 'paused' &&
                    native(s, '2')['playState'] == 'playing',
                'Focus gain must preserve the manual pause and resume the other source',
              );
              await state({'ack': stage});
            case 'permanent':
              await acquire('permanent', runId);
              final lost = await until(
                inactive,
                'Permanent focus loss must close both old source identities',
              );
              await File('${evidence.path}/audio-focus-permanent.json')
                  .writeAsString(jsonEncode(lost));
              await release();
              await Future<void>.delayed(const Duration(seconds: 1));
              if (!inactive(await state({'action': 'status'}))) {
                throw StateError(
                  'Old sources revived after abandoning permanent focus.',
                );
              }
              await state({'ack': stage});
              stdout.writeln(
                'Two real device shared audio outputs: transient loss/manual pause/gain/permanent loss verified with independent AudioManager app.',
              );
              return;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      throw StateError('External focus test exceeded its deadline.');
    },
    () => {
      'external audio focus': () async {
        if (fixtureActive || foregroundRestoreNeeded) await release();
      },
      'focus fixture UI dump': () async {
        if (xmlPath != null) await run(['shell', 'rm', '-f', xmlPath!]);
      },
      'focus fixture install': () async {
        if (installed) await run(['uninstall', fixturePackage]);
      },
    },
  );
}
