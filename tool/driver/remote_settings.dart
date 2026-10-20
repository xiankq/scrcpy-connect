import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

/// Independent Android observations for remote_settings_test.dart. The driver
/// never injects a product session.start, session.display or devices.wake call.
Future<void> main() async {
  final environment = Platform.environment;
  final adb = environment['CONNECT_E2E_ADB'];
  final controller = environment['CONNECT_E2E_DEVICE'];
  final target = environment['CONNECT_E2E_TARGET'];
  if (adb == null ||
      controller == null ||
      target == null ||
      controller == target) {
    throw StateError(
      'Set explicit CONNECT_E2E_ADB and distinct Android CONNECT_E2E_DEVICE/TARGET.',
    );
  }
  final path =
      environment['CONNECT_E2E_CAPTURE_DIR'] ??
      '/tmp/connect-e2e/remote-settings';
  if (!path.startsWith('/tmp/') || path.split('/').contains('..')) {
    throw StateError('Acceptance evidence must stay under /tmp.');
  }
  final directory = await Directory(path).create(recursive: true);
  Future<String> shell(String serial, String command) async {
    final result = await Process.run(adb, [
      '-s',
      serial,
      'shell',
      command,
    ]).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0) {
      throw StateError('$serial $command: ${result.stderr}');
    }
    return result.stdout as String;
  }

  Future<void> capture(String name) async {
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) {
      throw StateError('Invalid acceptance screenshot name.');
    }
    final screenshot = await Process.run(adb, [
      '-s',
      controller,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null).timeout(const Duration(seconds: 20));
    if (screenshot.exitCode != 0) {
      throw StateError('Cannot capture actual Android controller.');
    }
    await File('${directory.path}/$name.png')
        .writeAsBytes(screenshot.stdout as List<int>);
  }

  Future<Map<String, String>> state(String serial) async => {
    'wm': await shell(serial, 'wm size'),
    'rotation': await shell(
      serial,
      'settings get system accelerometer_rotation; settings get system user_rotation',
    ),
    'timeouts': await shell(
      serial,
      'settings get system screen_off_timeout; settings get global stay_on_while_plugged_in',
    ),
    'power': await shell(serial, 'dumpsys power'),
  };
  int orientation(String input) {
    final viewport = input
        .split('\n')
        .where(
          (line) => line.contains('Viewport ') && line.contains('displayId=0,'),
        )
        .firstOrNull;
    final found = viewport == null
        ? RegExp(r'SurfaceOrientation: (\d)').firstMatch(input)
        : RegExp(r'orientation=(\d)').firstMatch(viewport);
    if (found == null) {
      throw StateError('Cannot independently read target display orientation.');
    }
    return int.parse(found.group(1)!);
  }

  double ratio(String report, int rotation) {
    final matches = RegExp(r'(?:Physical|Override) size: (\d+)x(\d+)')
        .allMatches(report)
        .toList();
    if (matches.isEmpty) throw StateError('Invalid real wm size: $report');
    final match = matches.last;
    final width = int.parse(match.group(1)!);
    final height = int.parse(match.group(2)!);
    return rotation.isOdd ? height / width : width / height;
  }

  Future<void> until(Future<bool> Function() ready, String reason) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      if (await ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError(reason);
  }

  Future<bool> awake() async =>
      (await shell(target, 'dumpsys power')).contains('mWakefulness=Awake');
  Future<void> sleepTarget() async {
    await shell(target, 'input keyevent 223');
    await until(() async => !await awake(), 'Fixture target did not sleep.');
  }

  int userActivity(String power) {
    final match = RegExp(
      r'^\s*(?:mLastUserActivityTime|lastUserActivityTime)=(\d+)',
      multiLine: true,
    ).firstMatch(power);
    if (match == null) {
      throw StateError('No independent PowerManager activity timestamp.');
    }
    return int.parse(match.group(1)!);
  }

  Map<String, String>? targetBefore, controllerBefore;
  String? targetBuild, controllerBuild;
  String? lastGeometry;
  var baselineTaken = false, hostRestored = false;
  final checks = <Map<String, Object?>>[];
  Future<void> restoreController() async {
    final saved = controllerBefore;
    if (saved == null) return;
    final values = saved['rotation']!.trim().split('\n');
    Future<void> setting(String key, String value) async {
      await shell(
        controller,
        value == 'null'
            ? 'settings delete system $key'
            : 'settings put system $key $value',
      );
    }

    await setting('user_rotation', values[1]);
    await setting('accelerometer_rotation', values[0]);
  }

  Future<void> restoreHost() async {
    if (hostRestored || !baselineTaken) return;
    await restoreController();
    final wasAwake = targetBefore!['power']!.contains('mWakefulness=Awake');
    await shell(target, 'input keyevent ${wasAwake ? 224 : 223}');
    await until(
      () async => await awake() == wasAwake,
      'Original target power state did not return.',
    );
    hostRestored = true;
  }

  Future<Map<String, dynamic>> inspect(Map<String, dynamic> checkpoint) async {
    final name = checkpoint['name'] as String;
    if (name == 'baseline') {
      targetBuild = await shell(
        target,
        'getprop ro.build.version.sdk; getprop ro.product.cpu.abi',
      );
      controllerBuild = await shell(
        controller,
        'getprop ro.build.version.sdk; getprop ro.product.cpu.abi',
      );
      targetBefore = await state(target);
      controllerBefore = await state(controller);
      baselineTaken = true;
      final lease = await shell(
        target,
        'if [ -d /data/local/tmp/interop-display-0 ]; then echo occupied; fi',
      );
      if (lease.trim().isNotEmpty) {
        throw StateError('An existing display lease must never be disturbed.');
      }
      if (!await awake()) {
        await shell(target, 'input keyevent 224');
        await until(
          awake,
          'The isolated target must be awake for display acceptance.',
        );
      }
    } else if (name == 'sleep-target') {
      await sleepTarget();
    } else if (name == 'wake-fixture') {
      await shell(target, 'input keyevent 224');
      await until(
        awake,
        'Target fixture did not wake for the application branch.',
      );
    } else if (name == 'application-exit-awake' ||
        name == 'restored-application-exit-awake') {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!await awake()) {
        throw StateError(
          'Exiting an independent application locked the physical screen.',
        );
      }
    } else if (name == 'still-asleep' || name == 'exit-asleep') {
      if (name == 'exit-asleep') {
        await until(
          () async => !await awake(),
          'Actual phone did not sleep on the final page exit.',
        );
        await Future<void>.delayed(const Duration(milliseconds: 4500));
      }
      if (await awake()) {
        throw StateError('$name unexpectedly woke the target.');
      }
    } else if (name == 'connected-awake') {
      await until(
        awake,
        'Connection succeeded but actual target did not wake.',
      );
    } else if (name == 'keep-active' || name == 'keep-active-paused') {
      final before = userActivity(await shell(target, 'dumpsys power'));
      await Future<void>.delayed(const Duration(milliseconds: 4500));
      final after = userActivity(await shell(target, 'dumpsys power'));
      if (after <= before) {
        throw StateError(
          'UI-enabled keep_active did not reach Android PowerManager.',
        );
      }
    } else if (name == 'ime-unchanged') {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await capture('actual-controller-ime');
      final current = await shell(target, 'wm size');
      if (current != lastGeometry) {
        throw StateError(
          'Controller IME target wm: $current; preceding full viewport wm: $lastGeometry',
        );
      }
    } else if (name == 'dismiss-ime') {
      await shell(controller, 'input keyevent 4');
    } else if (name == 'rotate-controller') {
      await shell(
        controller,
        'settings put system accelerometer_rotation 0; settings put system user_rotation 1',
      );
    } else if (name == 'restore-controller') {
      await restoreController();
    } else if (name == 'failure') {
      // Record actual target state before finally restores this failed run.
      await capture('remote-settings-failed');
      await File('${directory.path}/target-display-failed.txt')
          .writeAsString(await shell(target, 'dumpsys display'));
    } else if (name == 'cleanup' || name == 'restored') {
      if (targetBefore == null) {
        throw StateError('No independent target baseline.');
      }
      await until(
        () async => await shell(target, 'wm size') == targetBefore!['wm'],
        'Owned wm override did not restore.',
      );
      final lease = await shell(
        target,
        'if [ -d /data/local/tmp/interop-display-0 ]; then echo occupied; fi',
      );
      if (lease.trim().isNotEmpty) {
        throw StateError('Owned display lease remains after session stop.');
      }
      final after = await state(target);
      if (after['rotation'] != targetBefore!['rotation'] ||
          after['timeouts'] != targetBefore!['timeouts']) {
        throw StateError(
          'Display/keep_active changed permanent rotation or timeout settings.',
        );
      }
      if (name == 'cleanup') await restoreHost();
    } else {
      final expected = (checkpoint['ratio'] as num?)?.toDouble();
      if (expected == null || checkpoint['virtual'] == true) {
        if (await shell(target, 'wm size') != targetBefore!['wm']) {
          throw StateError(
            'Original ratio unexpectedly changed the physical display override.',
          );
        }
      } else {
        await until(() async {
          final wm = await shell(target, 'wm size');
          final rotation = orientation(await shell(target, 'dumpsys input'));
          return (ratio(wm, rotation) - expected).abs() < .008;
        }, '$name Flutter setting never produced its actual target ratio.');
      }
      lastGeometry = await shell(target, 'wm size');
      if (checkpoint['virtual'] == true) {
        await File('${directory.path}/virtual-display.txt')
            .writeAsString(await shell(target, 'dumpsys display'));
      }
      await capture(name);
    }
    final current = await state(target);
    final record = <String, Object?>{
      'checkpoint': name,
      'targetSerial': target,
      'controllerSerial': controller,
      'targetBuild': targetBuild,
      'controllerBuild': controllerBuild,
      ...checkpoint,
      ...current,
    };
    checks.add(record);
    await File(
      '${directory.path}/${checkpoint['id'].toString().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.json',
    ).writeAsString(jsonEncode(record));
    return {'wm': current['wm']};
  }

  final driver = await FlutterDriver.connect();
  var finished = false;
  Object? inspectionError;
  Map<String, dynamic>? responseResult;
  final inspection =
      () async {
        String? previous;
        final deadline = DateTime.now().add(const Duration(minutes: 15));
        while (!finished && DateTime.now().isBefore(deadline)) {
          try {
            final response = await driver.serviceClient.callServiceExtension(
              'ext.connect.remoteSettings',
              isolateId: driver.appIsolate.id,
            );
            final checkpoint = response.json?['checkpoint'];
            if (checkpoint is Map && checkpoint['id'] != previous) {
              final data = Map<String, dynamic>.from(checkpoint);
              previous = data['id'] as String;
              String? error;
              Map<String, dynamic>? result;
              try {
                result = await inspect(data);
              } catch (failure) {
                error = failure.toString();
                inspectionError = failure;
              }
              await driver.serviceClient.callServiceExtension(
                'ext.connect.remoteSettings',
                isolateId: driver.appIsolate.id,
                args: {
                  'ack': previous,
                  'error': ?error,
                  if (result != null) 'result': jsonEncode(result),
                },
              );
            }
          } catch (error) {
            if (!error.toString().contains('ext.connect.remoteSettings') &&
                !error.toString().contains('Method not found')) {
              rethrow;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!finished) {
          throw StateError('Timed out inspecting real remote settings.');
        }
      }().catchError((Object error) {
        inspectionError = error;
      });
  try {
    await integrationDriver(
      driver: driver,
      writeResponseOnFailure: true,
      onScreenshot: (name, bytes, [args]) async {
        await File('${directory.path}/$name.png').writeAsBytes(bytes);
        return true;
      },
      responseDataCallback: (data) async {
        finished = true;
        await inspection;
        final result = {...?data}..remove('screenshots');
        result['independentTargetChecks'] = checks;
        responseResult = result;
        await File('${directory.path}/result.json')
            .writeAsString(jsonEncode(result));
        if (inspectionError != null ||
            result['remoteSettingsComplete'] != true) {
          throw StateError(
            'Real Flutter remote settings acceptance incomplete: $inspectionError',
          );
        }
      },
    );
  } catch (error) {
    await File('${directory.path}/result.json').writeAsString(
      jsonEncode({
        ...?responseResult,
        'remoteSettingsComplete': false,
        'driverFailure': '$error',
        'independentTargetChecks': checks,
      }),
    );
    rethrow;
  } finally {
    finished = true;
    await restoreHost();
  }
}
