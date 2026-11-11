import 'dart:convert';
import 'dart:io';

import 'support/capture.dart';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../../scripts/src/process.dart';
import 'support/cleanup.dart';
import 'support/inspection.dart';

/// 为 remote_settings_test.dart 提供独立 Android 观察，不注入产品 session.start、session.display 或 devices.wake 调用。
///
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
    final result = await runProcess(adb, [
      '-s',
      serial,
      'shell',
      command,
    ], timeout: const Duration(seconds: 20));
    if (result.exitCode != 0) {
      throw StateError('$serial $command: ${result.stderr}');
    }
    return result.stdout as String;
  }

  final captures = <Map<String, Object?>>[];
  Future<void> capture(String name, {String? serial}) async {
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) {
      throw StateError('Invalid acceptance screenshot name.');
    }
    final started = DateTime.now().toUtc();
    final source = serial ?? controller;
    final screenshot = await runProcess(
      adb,
      ['-s', source, 'exec-out', 'screencap', '-p'],
      stdoutEncoding: null,
      timeout: const Duration(seconds: 20),
    );
    final bytes = screenshot.stdout as List<int>;
    if (screenshot.exitCode != 0 ||
        bytes.length < 8 ||
        bytes.take(8).join(',') != '137,80,78,71,13,10,26,10') {
      throw StateError('Cannot capture actual Android display $source.');
    }
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    captures.add({
      'name': name,
      'serial': source,
      'startedAt': started.toIso8601String(),
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    });
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
  Future<Map<String, Object?>> verifyApplicationServices(
    String checkpointId,
  ) async {
    final safe = checkpointId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    String connections = '';
    await until(
      () async {
        connections = await shell(
          controller,
          'dumpsys activity services dev.scrcpyconnect.scrcpy_connect/.ConnectionService',
        );
        await File('${directory.path}/$safe-connection-service.txt')
            .writeAsString(connections);
        final type = RegExp(r'(?:foregroundServiceType|types)=0x([0-9a-fA-F]+)')
            .firstMatch(connections);
        if (type == null) return false;
        final bits = int.parse(type[1]!, radix: 16);
        return connections.contains('isForeground=true') &&
            (bits & 16) != 0 &&
            (bits & 2) == 0;
      },
      'Closing the final window stopped the native connectedDevice foreground service.',
    );
    final audio = await shell(
      controller,
      'dumpsys activity services dev.scrcpyconnect.scrcpy_connect/.AudioPlaybackService',
    );
    await File('${directory.path}/$safe-audio-service.txt')
        .writeAsString(audio);
    if (audio.contains('isForeground=true')) {
      throw StateError(
        'An idle controller retained a native audio foreground service after closing its final window.',
      );
    }
    return {
      'source': 'independent Android dumpsys activity services',
      'connectionForeground': true,
      'connectedDeviceType': true,
      'audioForeground': false,
    };
  }

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

    await withDriverCleanup(
      () async {},
      () => {
        'controller rotation': () => setting('user_rotation', values[1]),
        'controller rotation mode': () =>
            setting('accelerometer_rotation', values[0]),
      },
    );
  }

  Future<void> restoreHost() async {
    if (hostRestored || !baselineTaken) return;
    await withDriverCleanup(
      () async {},
      () => {
        'controller settings': restoreController,
        'original target power state': () async {
          final wasAwake = targetBefore!['power']!.contains(
            'mWakefulness=Awake',
          );
          await shell(target, 'input keyevent ${wasAwake ? 224 : 223}');
          await until(
            () async => await awake() == wasAwake,
            'Original target power state did not return.',
          );
        },
      },
    );
    hostRestored = true;
  }

  Future<Map<String, dynamic>> inspect(Map<String, dynamic> checkpoint) async {
    final name = checkpoint['name'] as String;
    Map<String, Object?>? services;
    bool? shadeExpanded;
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
    } else if (name == 'top-shade-open' || name == 'top-shade-closed') {
      final expected = name == 'top-shade-open';
      final safe = checkpoint['id'].toString().replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      String observed = '';
      await until(
        () async {
          observed = await shell(
            target,
            'dumpsys activity service com.android.systemui/.SystemUIService',
          );
          await File('${directory.path}/$safe-systemui.txt')
              .writeAsString(observed);
          final fractions =
              RegExp(
                    r'\bm?ExpandedFraction\s*=\s*([0-9.]+)',
                    caseSensitive: false,
                  )
                  .allMatches(observed)
                  .map((match) => double.parse(match[1]!))
                  .toList();
          final visible = RegExp(r'\bmExpandedVisible\s*=\s*(true|false)')
              .firstMatch(observed);
          if (fractions.isEmpty && visible == null) {
            throw StateError(
              'SystemUI dump exposes no current shade expansion state; cannot verify the top gesture.',
            );
          }
          shadeExpanded = fractions.isNotEmpty
              ? fractions.any((fraction) => fraction > .1)
              : visible![1] == 'true';
          return shadeExpanded == expected;
        },
        'The actual target notification shade did not ${expected ? 'open after the video top gesture' : 'collapse after remote Back'}.',
      );
      if (expected) {
        await Future.wait([
          capture('target-top-shade-open', serial: target),
          capture('controller-top-shade-open'),
        ]);
      }
    } else if (name == 'sleep-target') {
      await sleepTarget();
    } else if (name == 'wake-fixture') {
      await shell(target, 'input keyevent 224');
      await until(
        awake,
        'Target fixture did not wake for the application branch.',
      );
    } else if (name == 'still-asleep' ||
        name == 'connected-asleep' ||
        name == 'exit-asleep' ||
        name == 'application-exit-asleep') {
      if (name == 'exit-asleep' || name == 'application-exit-asleep') {
        await until(
          () async => !await awake(),
          'Actual phone did not sleep on the final page exit.',
        );
        await Future<void>.delayed(const Duration(milliseconds: 4500));
      }
      if (await awake()) {
        throw StateError('$name unexpectedly woke the target.');
      }
      if (name == 'exit-asleep' || name == 'application-exit-asleep') {
        services = await verifyApplicationServices(checkpoint['id'] as String);
      }
    } else if (name == 'new-screen-awake' || name == 'application-new-awake') {
      await until(
        awake,
        'A new screen started but the actual target did not wake.',
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
    } else if (name == 'keep-active-released') {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final before = userActivity(await shell(target, 'dumpsys power'));
      await Future<void>.delayed(const Duration(milliseconds: 4500));
      final after = userActivity(await shell(target, 'dumpsys power'));
      if (after != before) {
        throw StateError(
          'Closing the final window left its keep-active activity lease running.',
        );
      }
    } else if (name == 'pause-controller') {
      await shell(controller, 'input keyevent 3');
    } else if (name == 'resume-controller') {
      await shell(
        controller,
        'am start -n dev.scrcpyconnect.scrcpy_connect/.MainActivity',
      );
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
      // finally 恢复失败运行前，先记录实际被控状态。
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
      final closed = checkpoint['closedSessionId'] as String?;
      if (closed != null) {
        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(closed)) {
          throw StateError('Invalid owned session identity.');
        }
        await until(() async {
          final processes = await shell(target, 'ps -A -o ARGS');
          return !processes.contains('interop-scrcpy-$closed.jar');
        }, 'Closing the exact window left its target process alive.');
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
      if (const [
        'original',
        'auto-no-navigation',
        'auto-landscape',
      ].contains(name)) {
        await Future.wait([
          capture('target-$name', serial: target),
          capture(name),
        ]);
      } else {
        await capture(name);
      }
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
      'nativeServices': ?services,
      'targetShadeExpanded': ?shadeExpanded,
    };
    checks.add(record);
    await File(
      '${directory.path}/${checkpoint['id'].toString().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.json',
    ).writeAsString(jsonEncode(record));
    return {'wm': current['wm']};
  }

  final driver = await FlutterDriver.connect();
  Map<String, dynamic>? responseResult;
  final inspection = DriverInspection(
    request: ([args]) async =>
        (await driver.serviceClient.callServiceExtension(
          'ext.connect.remoteSettings',
          isolateId: driver.appIsolate.id,
          args: args,
        )).json ??
        {},
    timeout: const Duration(minutes: 15),
    inspect: inspect,
  );
  Object? driverFailure;
  await withDriverCleanup(
    () async {
      try {
        await integrationDriver(
          driver: driver,
          writeResponseOnFailure: true,
          onScreenshot: (name, bytes, [args]) =>
              saveScreenshot(directory, name, bytes),
          responseDataCallback: (data) async {
            await inspection.stop();
            // SDK 会在回调返回后退出；设备恢复不能仅依赖外层收尾。
            await restoreHost();
            final result = {...?data}..remove('screenshots');
            result['independentTargetChecks'] = checks;
            result['displayCaptures'] = captures;
            responseResult = result;
            await File('${directory.path}/result.json')
                .writeAsString(jsonEncode(result));
            if (inspection.error != null ||
                result['remoteSettingsComplete'] != true ||
                result['topSurfaceGestureAndRemoteBackVerified'] != true ||
                result['backgroundKeepAliveRestored'] != true ||
                (result['cleanupErrors'] as List?)?.isEmpty != true) {
              throw StateError(
                'Real Flutter remote settings acceptance incomplete: ${inspection.error}',
              );
            }
          },
        );
      } catch (error) {
        driverFailure = error;
        rethrow;
      }
    },
    () => {
      'remote-settings inspection': inspection.stop,
      'original controller and target state': restoreHost,
      'driver connection': () => driverRpc(driver.close()),
      'failure report': () async {
        if (driverFailure == null) return;
        await File('${directory.path}/result.json').writeAsString(
          jsonEncode({
            ...?responseResult,
            'remoteSettingsComplete': false,
            'driverFailure': '$driverFailure',
            'independentTargetChecks': checks,
          }),
        );
      },
    },
  );
}
