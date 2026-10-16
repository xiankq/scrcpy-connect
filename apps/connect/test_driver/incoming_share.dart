import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final serial = Platform.environment['CONNECT_E2E_DEVICE'];
  if (serial == null) {
    throw StateError('Set CONNECT_E2E_DEVICE to the controller.');
  }
  final adb = Platform.environment['CONNECT_E2E_ADB'] ?? 'adb';
  final driver = await FlutterDriver.connect();
  var hostFinished = false;
  final controller = driveShares(driver, adb, serial, () => hostFinished);
  controller.catchError((Object error, StackTrace stack) {
    stderr.writeln('External sharing fixture failed: $error');
    exit(1);
  });
  await integrationDriver(
    driver: driver,
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      hostFinished = true;
      await controller;
      final metadata = {...?data}..remove('screenshots');
      final output = Directory('/tmp/connect-e2e/incoming-share');
      await output.create(recursive: true);
      await File('${output.path}/result.json')
          .writeAsString(jsonEncode(metadata));
      if (metadata['shareAcceptanceComplete'] != true) {
        throw StateError('The app did not complete external share acceptance.');
      }
    },
    onScreenshot: (name, bytes, [args]) async {
      final output = Directory('/tmp/connect-e2e/incoming-share');
      await output.create(recursive: true);
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await File('${output.path}/$safeName.png')
          .writeAsBytes(bytes, flush: true);
      return true;
    },
  );
}

Future<void> driveShares(
  FlutterDriver driver,
  String adb,
  String serial,
  bool Function() shouldStop,
) async {
  final sent = <String>{};
  var launcherReturned = false;
  Future<ProcessResult> runAdb(List<String> args) async {
    final result = await Process.run(adb, [
      '-s',
      serial,
      ...args,
    ]).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0) {
      throw StateError('External sharing host failed: ${result.stderr}');
    }
    return result;
  }

  final deadline = DateTime.now().add(const Duration(minutes: 8));
  while (!shouldStop() && DateTime.now().isBefore(deadline)) {
    try {
      final state =
          (await driver.serviceClient.callServiceExtension(
            'ext.connect.incomingShare',
            isolateId: driver.appIsolate.id,
          )).json ??
          {};
      if (state['stage'] == 'complete') return;
      if (state['stage'] == 'launcher-return' && !launcherReturned) {
        launcherReturned = true;
        await runAdb(['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
        await runAdb([
          'shell',
          'am',
          'start',
          '-W',
          '-a',
          'android.intent.action.MAIN',
          '-c',
          'android.intent.category.LAUNCHER',
          '-n',
          'dev.scrcpyconnect.scrcpy_connect/.MainActivity',
        ]);
        final activities = await runAdb([
          'shell',
          'dumpsys',
          'activity',
          'activities',
        ]);
        final hosts = RegExp(
          r'^\s*\* Hist\s+#\d+: ActivityRecord\{[^\n]* dev\.scrcpyconnect\.scrcpy_connect/\.MainActivity ',
          multiLine: true,
        ).allMatches('${activities.stdout}').length;
        if (hosts != 1) {
          throw StateError(
            'One Flutter engine has $hosts Android UI hosts after launcher return.',
          );
        }
        await driver.serviceClient.callServiceExtension(
          'ext.connect.incomingShare',
          isolateId: driver.appIsolate.id,
          args: {'action': 'launcherReturned'},
        );
        stdout.writeln('Actual HOME and launcher return: one Android UI host.');
      }
      final mode = state['mode'];
      if (state['stage'] == 'send' && mode is String && sent.add(mode)) {
        final result = await Process.run(adb, [
          '-s',
          serial,
          'shell',
          'am',
          'start',
          // Bring the sender itself to the top and deliver this mode even when
          // its task still has the previously opened receiver above it.
          '-f',
          '0x24000000',
          '-n',
          'dev.scrcpyconnect.sharefixture/.ShareFixtureActivity',
          '--es',
          'mode',
          mode,
        ]).timeout(const Duration(seconds: 20));
        if (result.exitCode != 0) {
          throw StateError('External fixture failed: ${result.stderr}');
        }
        stdout.writeln('External share launch $mode: ${result.stdout}');
      }
    } catch (error) {
      if (shouldStop()) return;
      if (!error.toString().contains('ext.connect.incomingShare') &&
          !error.toString().contains('Method not found')) {
        rethrow;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  if (!shouldStop()) {
    throw StateError('External share integration deadline exceeded.');
  }
}
