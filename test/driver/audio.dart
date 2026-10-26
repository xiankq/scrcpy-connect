import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import '../../scripts/src/process.dart';
import 'support/cleanup.dart';

Future<void> driveAudioLifecycle(
  FlutterDriver driver, {
  bool Function()? shouldStop,
}) async {
  final serial = Platform.environment['CONNECT_E2E_DEVICE'];
  final sdk = Platform.environment['ANDROID_HOME'];
  final adb =
      Platform.environment['CONNECT_E2E_ADB'] ?? '$sdk/platform-tools/adb';
  if (serial == null || serial.isEmpty) {
    throw StateError(
      'CONNECT_E2E_DEVICE must identify the actual Android controller.',
    );
  }
  Future<String> run(List<String> args) async {
    final result = await runProcess(adb, [
      '-s',
      serial,
      ...args,
    ], timeout: const Duration(seconds: 20));
    if (result.exitCode != 0) {
      throw StateError('Actual Android command failed: ${result.stderr}');
    }
    return result.stdout as String;
  }

  Future<Map<String, dynamic>> state([
    Map<String, String> args = const {},
  ]) async =>
      (await driver.serviceClient
              .callServiceExtension(
                'ext.connect.audio',
                isolateId: driver.appIsolate.id,
                args: args,
              )
              .timeout(const Duration(seconds: 5)))
          .json ??
      {};
  var backgrounded = false;
  final recreate = Platform.environment['CONNECT_E2E_RECREATE_ACTIVITY'] == '1';
  String? originalFinish;
  String? lifecycleFixture;
  Future<void> setAlwaysFinish(bool enabled) async {
    final result = await run([
      'shell',
      'env',
      'CLASSPATH=$lifecycleFixture',
      'app_process',
      '/system/bin',
      'dev.scrcpyconnect.inputfixture.ActivityLifecycle',
      enabled ? '1' : '0',
    ]);
    if (!result.contains('setAlwaysFinish=${enabled ? 1 : 0}')) {
      throw StateError(
        'ActivityManager did not acknowledge the lifecycle fixture.',
      );
    }
  }

  Future<String> activityIdentity() async {
    final dump = await run(['shell', 'dumpsys', 'activity', 'top']);
    final identity = RegExp(
      r'ACTIVITY dev\.scrcpyconnect\.scrcpy_connect/[^\n]+\n\s+Local Activity ([a-fA-F0-9]+) State:',
    ).firstMatch(dump)?.group(1);
    if (identity == null) {
      throw StateError('The actual product Activity must be present.');
    }
    return identity;
  }

  final finished = <String>{};
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  await withDriverCleanup(
    () async {
      if (recreate) {
        final fixture = Platform.environment['CONNECT_E2E_ACTIVITY_FIXTURE'];
        if (fixture == null || !await File(fixture).exists()) {
          throw StateError(
            'Build input_fixture and set CONNECT_E2E_ACTIVITY_FIXTURE.',
          );
        }
        lifecycleFixture =
            '/data/local/tmp/connect-activity-${DateTime.now().microsecondsSinceEpoch}.apk';
        await run(['push', fixture, lifecycleFixture!]);
        originalFinish = (await run([
          'shell',
          'settings',
          'get',
          'global',
          'always_finish_activities',
        ])).trim();
        await setAlwaysFinish(true);
      }
      while (DateTime.now().isBefore(deadline)) {
        if (shouldStop?.call() == true) return;
        Map<String, dynamic> current;
        try {
          current = await state();
        } catch (error) {
          if (shouldStop?.call() == true) return;
          if (!error.toString().contains('ext.connect.audio') &&
              !error.toString().contains('Method not found')) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final stage = current['stage'];
        if (stage == 'complete') return;
        if ((stage == 'background-paused' || stage == 'background-playing') &&
            finished.add(stage as String)) {
          final previousActivity = recreate ? await activityIdentity() : null;
          final previousProcess = recreate
              ? (await run([
                  'shell',
                  'pidof',
                  'dev.scrcpyconnect.scrcpy_connect',
                ])).trim()
              : null;
          backgrounded = true;
          await run(['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
          await Future<void>.delayed(const Duration(seconds: 2));
          final first = await state({'action': 'status'});
          if (!['paused', 'hidden', 'detached'].contains(first['lifecycle'])) {
            throw StateError(
              'Actual HOME did not background the controller: ${first['lifecycle']}',
            );
          }
          final native = Map<String, dynamic>.from(first['state'] as Map);
          final shouldPause = stage == 'background-paused';
          if (native['playState'] != (shouldPause ? 'paused' : 'playing') ||
              native['backgroundPaused'] != shouldPause ||
              native['backend'] != 'media_codec') {
            throw StateError(
              'Shared playback did not apply actual background policy: $native',
            );
          }
          await Future<void>.delayed(const Duration(seconds: 1));
          final second = Map<String, dynamic>.from(
            (await state({'action': 'status'}))['state'] as Map,
          );
          if (shouldPause) {
            if (((second['positionMs'] as int) - (native['positionMs'] as int))
                    .abs() >
                40) {
              throw StateError(
                'Actual paused shared playback clock continued advancing.',
              );
            }
          } else {
            if ((second['positionMs'] as int) <=
                (native['positionMs'] as int)) {
              throw StateError(
                'Actual background playback clock stopped advancing.',
              );
            }
            final service = await run([
              'shell',
              'dumpsys',
              'activity',
              'services',
              'dev.scrcpyconnect.scrcpy_connect/.AudioPlaybackService',
            ]);
            final flags = RegExp(
              r'(?:foregroundServiceType|types)=0x([0-9a-fA-F]+)',
            ).firstMatch(service);
            if (flags == null || int.parse(flags[1]!, radix: 16) != 2) {
              throw StateError(
                'Actual service did not declare active mediaPlayback type: $service',
              );
            }
            final connections = await run([
              'shell',
              'dumpsys',
              'activity',
              'services',
              'dev.scrcpyconnect.scrcpy_connect/.ConnectionService',
            ]);
            final connectionFlags = RegExp(
              r'(?:foregroundServiceType|types)=0x([0-9a-fA-F]+)',
            ).firstMatch(connections);
            if (connectionFlags == null ||
                int.parse(connectionFlags[1]!, radix: 16) != 16) {
              throw StateError(
                'Application service lost its independent connectedDevice type: $connections',
              );
            }
          }
          await run([
            'shell',
            'am',
            'start',
            '-W',
            '-n',
            'dev.scrcpyconnect.scrcpy_connect/.MainActivity',
          ]);
          backgrounded = false;
          if (recreate) {
            final replacementActivity = await activityIdentity();
            final replacementProcess = (await run([
              'shell',
              'pidof',
              'dev.scrcpyconnect.scrcpy_connect',
            ])).trim();
            if (replacementActivity == previousActivity ||
                replacementProcess != previousProcess) {
              throw StateError(
                'Expected a new Activity in the same process; recreation was not proven ($previousActivity/$previousProcess -> $replacementActivity/$replacementProcess).',
              );
            }
            stdout.writeln(
              'Actual Activity recreation in the same process verified: $stage.',
            );
          }
          await state({'returned': stage});
          stdout.writeln(
            'Actual shared playback HOME policy verified: $stage.',
          );
          if (finished.length == 2) return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      throw StateError('Actual audio lifecycle handshake timed out.');
    },
    () => {
      'ActivityManager setting': () async {
        if (originalFinish != null) {
          await setAlwaysFinish(originalFinish == '1');
        }
      },
      'stored Activity lifecycle setting': () async {
        if (originalFinish == null) return;
        await run([
          'shell',
          'settings',
          originalFinish == 'null' ? 'delete' : 'put',
          'global',
          'always_finish_activities',
          if (originalFinish != 'null') originalFinish!,
        ]);
      },
      'Activity fixture APK': () async {
        if (lifecycleFixture != null) {
          await run(['shell', 'rm', '-f', lifecycleFixture!]);
        }
      },
      'controller foreground': () async {
        if (backgrounded) {
          await run([
            'shell',
            'am',
            'start',
            '-W',
            '-n',
            'dev.scrcpyconnect.scrcpy_connect/.MainActivity',
          ]);
        }
      },
    },
  );
}
