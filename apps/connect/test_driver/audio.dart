import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> driveAudioLifecycle(FlutterDriver driver) async {
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
    final result = await Process.run(adb, [
      '-s',
      serial,
      ...args,
    ]).timeout(const Duration(seconds: 20));
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
  final finished = <String>{};
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  try {
    while (DateTime.now().isBefore(deadline)) {
      Map<String, dynamic> current;
      try {
        current = await state();
      } catch (error) {
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
        await run(['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
        backgrounded = true;
        await Future<void>.delayed(const Duration(seconds: 2));
        final first = await state({'action': 'status'});
        if (!['paused', 'hidden'].contains(first['lifecycle'])) {
          throw StateError(
            'Actual HOME did not background the controller: ${first['lifecycle']}',
          );
        }
        final native = Map<String, dynamic>.from(first['state'] as Map);
        final shouldPause = stage == 'background-paused';
        if (native['playState'] != (shouldPause ? 'paused' : 'playing') ||
            native['backgroundPaused'] != shouldPause ||
            native['backend'] != 'fvp') {
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
          if ((second['positionMs'] as int) <= (native['positionMs'] as int)) {
            throw StateError(
              'Actual background playback clock stopped advancing.',
            );
          }
          final service = await run([
            'shell',
            'dumpsys',
            'activity',
            'services',
            'dev.scrcpyconnect.scrcpy_connect/.ConnectionService',
          ]);
          final flags = RegExp(
            r'(?:foregroundServiceType|types)=0x([0-9a-fA-F]+)',
          ).firstMatch(service);
          if (flags == null || (int.parse(flags[1]!, radix: 16) & 2) == 0) {
            throw StateError(
              'Actual service did not declare active mediaPlayback type: $service',
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
        await state({'returned': stage});
        stdout.writeln('Actual shared playback HOME policy verified: $stage.');
        if (finished.length == 2) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('Actual audio lifecycle handshake timed out.');
  } finally {
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
  }
}
