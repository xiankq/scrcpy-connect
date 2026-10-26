import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';
import 'package:path/path.dart' as p;

import 'support/cleanup.dart';
import '../../scripts/src/process.dart';

Future<void> main() async {
  const package = 'dev.scrcpyconnect.videofixture';
  final environment = Platform.environment;
  final adb = environment['CONNECT_E2E_ADB'];
  final target = environment['CONNECT_E2E_TARGET'];
  final controller = environment['CONNECT_E2E_DEVICE'];
  final apk = environment['CONNECT_E2E_VIDEO_FIXTURE'];
  final fixtureMotion = environment['CONNECT_E2E_VIDEO_MOTION'] == 'true';
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
        p.join(Directory.systemTemp.path, 'connect-e2e', 'video-performance'),
  );
  final temporaryRoots = [
    Directory.systemTemp.absolute.path,
    if (!Platform.isWindows) '/tmp',
    if (Platform.isMacOS) '/private/tmp',
  ];
  if (!temporaryRoots.any((root) => p.isWithin(root, output.absolute.path))) {
    throw StateError('Keep evidence in the system temporary directory.');
  }
  await output.create(recursive: true);
  Future<String> command(List<String> args) async {
    final result = await runProcess(adb, [
      '-s',
      target,
      ...args,
    ], timeout: const Duration(seconds: 30));
    if (result.exitCode != 0) {
      throw StateError('Target ${args.first} failed: ${result.stderr}');
    }
    return result.stdout as String;
  }

  Future<bool> fixtureExists() async {
    final result = await runProcess(adb, [
      '-s',
      target,
      'shell',
      'pm',
      'path',
      package,
    ], timeout: const Duration(seconds: 10));
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
  FlutterDriver? ownedDriver;
  Future<void> capture(String serial, String name) async {
    final result = await runProcess(
      adb,
      ['-s', serial, 'exec-out', 'screencap', '-p'],
      stdoutEncoding: null,
      timeout: const Duration(seconds: 15),
    );
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
      await withDriverCleanup(
        () async {},
        () => {
          'fixture uninstall': () async {
            if (await fixtureExists()) {
              cleanup['uninstalled'] = (await command(['uninstall', package]))
                  .contains('Success');
            } else {
              cleanup['uninstalled'] = true;
            }
            cleanup['absent'] = !await fixtureExists();
            if (cleanup['uninstalled'] != true || cleanup['absent'] != true) {
              throw StateError('Independent fixture cleanup not confirmed.');
            }
          },
          'target foreground': () async {
            await command([
              'shell',
              'am',
              'start',
              '-a',
              'android.settings.SETTINGS',
            ]);
          },
          'cleanup report': () =>
              File('${output.path}/cleanup.json')
                  .writeAsString(jsonEncode(cleanup)),
        },
      );
    }
    installed = false;
  }

  await withDriverCleanup(
    () async {
      installed = true;
      final install = await command(['install', apk]);
      if (!install.contains('Success')) {
        throw StateError('Fixture installation not confirmed.');
      }
      await command([
        'shell',
        'am',
        'start',
        '-W',
        '-n',
        '$package/.VideoPatternActivity',
        '--ez',
        'motion',
        '$fixtureMotion',
      ]);
      await capture(target, 'target-initial');
      final driver = ownedDriver = await FlutterDriver.connect();
      final response = await driverRpc(
        driver.serviceClient.callServiceExtension(
          'ext.connect.videoPerformance',
          isolateId: driver.appIsolate.id,
          args: {'ready': 'true'},
        ),
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
          // integrationDriver 会退出 VM，不能只依靠 finally 清理。
          await cleanupFixture();
          final report = {...?data}..remove('screenshots');
          report['fixtureCleanupConfirmed'] = true;
          report['fixtureMotionEnabled'] = fixtureMotion;
          await File('${output.path}/result.json')
              .writeAsString(jsonEncode(report));
          if (report['videoPerformanceComplete'] != true) {
            throw StateError('Video performance loop incomplete.');
          }
        },
      );
    },
    () => {
      'video fixture': cleanupFixture,
      'driver connection': () async {
        if (ownedDriver != null) await driverRpc(ownedDriver!.close());
      },
    },
  );
}
