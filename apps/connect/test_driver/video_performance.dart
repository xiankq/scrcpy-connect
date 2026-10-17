import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const package = 'dev.scrcpyconnect.videofixture';
  final environment = Platform.environment;
  final adb = environment['CONNECT_E2E_ADB'];
  final target = environment['CONNECT_E2E_TARGET'];
  final controller = environment['CONNECT_E2E_DEVICE'];
  final apk = environment['CONNECT_E2E_VIDEO_FIXTURE'];
  if (adb == null ||
      target == null ||
      controller == null ||
      target == controller ||
      apk == null) {
    throw StateError(
      'Set CONNECT_E2E_ADB, distinct DEVICE/TARGET, and CONNECT_E2E_VIDEO_FIXTURE.',
    );
  }
  final output = Directory(
    environment['CONNECT_E2E_CAPTURE_DIR'] ??
        '/tmp/connect-e2e/video-performance',
  );
  if (!output.absolute.path.startsWith('/tmp/')) {
    throw StateError('Keep evidence under /tmp.');
  }
  await output.create(recursive: true);
  Future<String> command(List<String> args) async {
    final result = await Process.run(adb, [
      '-s',
      target,
      ...args,
    ]).timeout(const Duration(seconds: 30));
    if (result.exitCode != 0) {
      throw StateError('Target ${args.first} failed: ${result.stderr}');
    }
    return result.stdout as String;
  }

  Future<bool> fixtureExists() async {
    final result = await Process.run(adb, [
      '-s',
      target,
      'shell',
      'pm',
      'path',
      package,
    ]).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0 &&
        (result.exitCode != 1 || '${result.stderr}'.trim().isNotEmpty)) {
      throw StateError('Cannot inspect fixture ownership: ${result.stderr}');
    }
    return '${result.stdout}'.trim().isNotEmpty;
  }

  if (await fixtureExists()) {
    throw StateError(
      'Refusing to replace an existing independent fixture installation.',
    );
  }
  var installed = false;
  Future<void> capture(String serial, String name) async {
    final result = await Process.run(adb, [
      '-s',
      serial,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null).timeout(const Duration(seconds: 15));
    if (result.exitCode != 0) throw StateError('Cannot capture $name.');
    await File('${output.path}/$name.png')
        .writeAsBytes(result.stdout as List<int>);
  }

  Future<void> cleanupFixture() async {
    if (!installed) return;
    final cleanup = <String, Object?>{};
    if (installed) {
      try {
        await capture(target, 'target-final');
      } catch (error) {
        cleanup['captureError'] = '$error';
      }
      cleanup['uninstalled'] = (await command(['uninstall', package]))
          .contains('Success');
      cleanup['absent'] = !await fixtureExists();
      await command([
        'shell',
        'am',
        'start',
        '-a',
        'android.settings.SETTINGS',
      ]);
    }
    await File('${output.path}/cleanup.json')
        .writeAsString(jsonEncode(cleanup));
    if (cleanup['uninstalled'] != true || cleanup['absent'] != true) {
      throw StateError('Independent fixture cleanup not confirmed.');
    }
    installed = false;
  }

  try {
    final install = await command(['install', apk]);
    if (!install.contains('Success')) {
      throw StateError('Fixture installation not confirmed.');
    }
    installed = true;
    await command([
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$package/.VideoPatternActivity',
    ]);
    await capture(target, 'target-initial');
    final driver = await FlutterDriver.connect();
    final response = await driver.serviceClient.callServiceExtension(
      'ext.connect.videoPerformance',
      isolateId: driver.appIsolate.id,
      args: {'ready': 'true'},
    );
    if (response.json?['ready'] != true) {
      throw StateError('App did not acknowledge fixture readiness.');
    }
    await integrationDriver(
      driver: driver,
      writeResponseOnFailure: true,
      onScreenshot: (name, bytes, [args]) async {
        final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        await File('${output.path}/$safe.png').writeAsBytes(bytes);
        return true;
      },
      responseDataCallback: (data) async {
        // integrationDriver exits the VM, so finally alone cannot clean up.
        await cleanupFixture();
        final report = {...?data}..remove('screenshots');
        report['fixtureCleanupConfirmed'] = true;
        await File('${output.path}/result.json')
            .writeAsString(jsonEncode(report));
        if (report['videoPerformanceComplete'] != true) {
          throw StateError('Video performance loop incomplete.');
        }
      },
    );
  } finally {
    await cleanupFixture();
  }
}
