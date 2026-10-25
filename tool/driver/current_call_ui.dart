import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../src/process.dart';
import '../src/driver_cleanup.dart';

// 仅宿主使用的夹具，由 Android 虚拟调制解调器产生一通隔离来电；只有产品 CallsPage 可以请求真实通话界面。
//
Future<void> main() async {
  final adb = Platform.environment['CONNECT_E2E_ADB'];
  final target = Platform.environment['CONNECT_E2E_TARGET'];
  final controller = Platform.environment['CONNECT_E2E_DEVICE'];
  if (adb == null ||
      controller == null ||
      target == null ||
      target != 'emulator-5556' ||
      controller == target) {
    throw StateError(
      'Set CONNECT_E2E_ADB, CONNECT_E2E_DEVICE and the isolated CONNECT_E2E_TARGET=emulator-5556.',
    );
  }
  final path =
      Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
      '/tmp/connect-e2e/current-call-ui';
  if (!path.startsWith('/tmp/') || path.split('/').contains('..')) {
    throw StateError('Current call UI evidence must stay under /tmp.');
  }
  final directory = await Directory(path).create(recursive: true);
  // 专用号码不会传给 calls.action 或全局挂断命令；清理仅定位本次创建的虚拟来电。
  //
  const number = '5550101246';
  var callOwned = false;
  var targetRestored = false;
  String? ownedTelecomId;
  final checks = <Map<String, Object?>>[];
  final screenshots = <String>[];
  Object? inspectionError;
  Future<String> adbTarget(List<String> command) async {
    final result = await runProcess(adb, [
      '-s',
      target,
      ...command,
    ], timeout: const Duration(seconds: 15));
    final output = result.stdout as String;
    if (result.exitCode != 0 || output.contains('KO:')) {
      throw StateError(
        'Independent Android command ${command.join(' ')} failed: $output ${result.stderr}',
      );
    }
    return output;
  }

  Future<String> shell(List<String> command) =>
      adbTarget(['shell', ...command]);
  Future<String> foreground() async {
    final dump = await shell(['dumpsys', 'activity', 'activities']);
    return dump
        .split('\n')
        .where((line) => line.contains('ResumedActivity'))
        .join('\n');
  }

  Future<Map<String, Object?>> modem(
    String stage, {
    required bool ringing,
  }) async {
    final list = await adbTarget(['emu', 'gsm', 'list']);
    final telephony = await shell(['dumpsys', 'telephony.registry']);
    final telecom = await shell(['dumpsys', 'telecom']);
    await File('${directory.path}/$stage-modem.txt').writeAsString(list);
    await File('${directory.path}/$stage-telephony.txt')
        .writeAsString(telephony);
    await File('${directory.path}/$stage-telecom.txt').writeAsString(telecom);
    final callLines = list
        .split('\n')
        .where((line) => line.trim().isNotEmpty && line.trim() != 'OK')
        .toList();
    final states = RegExp(
      r'^\s*mCallState=(\d+)\s*$',
      multiLine: true,
    ).allMatches(telephony).map((m) => int.parse(m[1]!)).toList();
    final activeTelecom = RegExp(
      r'^  mCalls:[ \t]*\n([\s\S]*?)^  mCallAudioManager:',
      multiLine: true,
    ).firstMatch(telecom)?.group(1);
    final actualCalls = activeTelecom == null
        ? <RegExpMatch>[]
        : RegExp(r'\[Call id=([^,]+), state=([^,]+),')
              .allMatches(activeTelecom)
              .toList();
    final incomingNumbers =
        RegExp(r'^\s*mCallIncomingNumber=(.*)$', multiLine: true)
            .allMatches(telephony)
            .map((m) => m[1]!.trim())
            .where((n) => n.isNotEmpty)
            .toList();
    if (ringing) {
      // Emulator 37.2.12 即使通话中也可能只对 gsm list 返回 OK；核验实时 Telecom 通话和精确来电号码，不把空控制台响应当成空闲证据。
      //
      //
      if (actualCalls.length != 1 ||
          actualCalls.single[2] != 'RINGING' ||
          incomingNumbers.length != 1 ||
          incomingNumbers.single != number ||
          (ownedTelecomId != null && actualCalls.single[1] != ownedTelecomId) ||
          !states.contains(1) ||
          states.any((s) => s != 0 && s != 1)) {
        throw StateError(
          'Expected only our still-ringing virtual-modem call at $stage: $list; states=$states',
        );
      }
      ownedTelecomId ??= actualCalls.single[1];
    } else if (callLines.isNotEmpty ||
        states.isEmpty ||
        states.any((s) => s != 0) ||
        activeTelecom == null ||
        activeTelecom.trim().isNotEmpty) {
      throw StateError(
        'Refuse an occupied or unrecognized target at $stage: $list; states=$states; activeTelecom=$activeTelecom',
      );
    }
    return {
      'modemCalls': callLines,
      'telecomCallId': ringing ? ownedTelecomId : null,
      'incomingNumbers': incomingNumbers,
      'telephonyStates': states,
      'source': 'independent host adb virtual modem + telephony + Telecom',
    };
  }

  Future<Map<String, Object?>> waitModem(
    String stage, {
    required bool ringing,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      try {
        return await modem(stage, ringing: ringing);
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  Future<String> settings() async {
    final output = await shell([
      'am',
      'start',
      '-W',
      '-a',
      'android.settings.SETTINGS',
    ]);
    if (output.contains('Error') || output.contains('Exception')) {
      throw StateError(output);
    }
    final resumed = await foreground();
    if (!resumed.contains('com.android.settings')) {
      throw StateError(
        'Settings must be the actual target foreground: $resumed',
      );
    }
    return resumed;
  }

  Future<void> capture(String stage) async {
    for (final device in {'controller': controller, 'target': target}.entries) {
      final result = await runProcess(
        adb,
        ['-s', device.value, 'exec-out', 'screencap', '-p'],
        stdoutEncoding: null,
        timeout: const Duration(seconds: 15),
      );
      final bytes = result.stdout as List<int>;
      if (result.exitCode != 0 ||
          bytes.length < 8 ||
          bytes.take(8).join(',') != '137,80,78,71,13,10,26,10') {
        throw StateError('Could not capture the actual ${device.key} display.');
      }
      final filename = '${device.key}-$stage.png';
      await File('${directory.path}/$filename')
          .writeAsBytes(bytes, flush: true);
      screenshots.add(filename);
    }
  }

  Future<void> cleanupTarget() async {
    if (!callOwned) return;
    await adbTarget(['emu', 'gsm', 'cancel', number]);
    await waitModem('cleanup-target', ringing: false);
    await settings();
    callOwned = false;
    targetRestored = true;
  }

  Future<Map<String, Object?>> inspect(String stage) async {
    Map<String, Object?> evidence;
    if (stage == 'prepare-ringing-settings') {
      // 取得所有权或创建任何对象前先检查空闲。
      await modem('initial-idle', ringing: false);
      final initialForeground = await settings();
      callOwned = true; // 调制解调器已应用请求但回执超时时，也须清理。
      await adbTarget(['emu', 'gsm', 'call', number]);
      evidence = await waitModem(stage, ringing: true);
      evidence['initialForeground'] = initialForeground;
      evidence['foreground'] = await settings();
    } else if (stage == 'before-open') {
      evidence = await modem(stage, ringing: true);
      final resumed = await foreground();
      if (!resumed.contains('com.android.settings') ||
          resumed.toLowerCase().contains('incall')) {
        throw StateError(
          'The product action must start with target Settings visible: $resumed',
        );
      }
      evidence['foreground'] = resumed;
      await capture(stage);
    } else if (stage == 'decoded-incall') {
      var resumed = '';
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      do {
        resumed = await foreground();
        if (resumed.contains('InCallActivity') &&
            (resumed.contains('dialer') || resumed.contains('incallui'))) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      } while (DateTime.now().isBefore(deadline));
      if (!resumed.contains('InCallActivity') ||
          !(resumed.contains('dialer') || resumed.contains('incallui'))) {
        throw StateError(
          'No actual foreground InCallActivity after the CallsPage action: $resumed',
        );
      }
      evidence = await modem(stage, ringing: true);
      evidence['foreground'] = resumed;
      await File('${directory.path}/$stage-activity.txt')
          .writeAsString(await shell(['dumpsys', 'activity', 'activities']));
      await capture(stage);
      // 主控截图后再次核对，确保通话存活证据覆盖捕获画面，而非仅覆盖此前的系统请求。
      //
      await modem('after-capture', ringing: true);
    } else if (stage == 'cleanup-target') {
      await cleanupTarget();
      evidence = {
        'exactNumberCancelled': number,
        'targetIdle': targetRestored,
        'foreground': await foreground(),
      };
    } else {
      throw StateError('Unexpected checkpoint: $stage');
    }
    evidence['stage'] = stage;
    checks.add(evidence);
    return evidence;
  }

  final driver = await FlutterDriver.connect();
  var finished = false;
  var checkpointSequence = 0;
  String? runId;
  String? previousId;
  final expected = [
    'prepare-ringing-settings',
    'before-open',
    'decoded-incall',
    'cleanup-target',
  ];
  final inspection =
      () async {
        final deadline = DateTime.now().add(const Duration(minutes: 7));
        while (!finished && DateTime.now().isBefore(deadline)) {
          try {
            final response = await driverRpc(
              driver.serviceClient.callServiceExtension(
                'ext.connect.currentCallUi',
                isolateId: driver.appIsolate.id,
              ),
            );
            if (finished) return;
            final checkpoint = response.json?['checkpoint'];
            if (checkpoint is Map<String, dynamic> &&
                checkpoint['id'] != previousId) {
              final checkpointId = checkpoint['id'] as String;
              previousId = checkpointId;
              String? error;
              Map<String, Object?>? result;
              try {
                runId ??= checkpoint['runId'] as String;
                final stage = checkpoint['name'] as String;
                // 清理检查点可以在前一阶段失败后执行，但创建和打开检查点不可重放或乱序接受。
                //
                final cleanup = stage == 'cleanup-target';
                if (checkpoint['runId'] != runId ||
                    checkpoint['sequence'] != checkpointSequence + 1 ||
                    (!cleanup && stage != expected[checkpointSequence]) ||
                    (cleanup && checkpointSequence == 0)) {
                  throw StateError(
                    'Out-of-order or replayed current-call checkpoint: $checkpoint',
                  );
                }
                checkpointSequence++;
                result = await inspect(stage);
              } catch (failure) {
                error = failure.toString();
                inspectionError ??= failure;
              }
              if (finished) return;
              await driverRpc(
                driver.serviceClient.callServiceExtension(
                  'ext.connect.currentCallUi',
                  isolateId: driver.appIsolate.id,
                  args: {
                    'ack': checkpointId,
                    'error': ?error,
                    if (result != null) 'result': jsonEncode(result),
                  },
                ),
              );
            }
          } catch (error) {
            if (finished) return;
            if (!error.toString().contains('ext.connect.currentCallUi') &&
                !error.toString().contains('Method not found')) {
              rethrow;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!finished) {
          throw StateError(
            'Timed out inspecting the actual current system call UI.',
          );
        }
      }().catchError((Object error) {
        inspectionError ??= error;
      });
  await withDriverCleanup(
    () async {
      await integrationDriver(
        driver: driver,
        writeResponseOnFailure: true,
        responseDataCallback: (data) async {
          finished = true;
          await inspection;
          // Flutter 在清理检查点前中止时也必须执行。
          try {
            await cleanupTarget();
          } catch (error, stack) {
            inspectionError = DriverCleanupException(inspectionError, null, [
              DriverCleanupFailure('owned incoming call fixture', error, stack),
            ]);
          }
          final metadata = {...?data}..remove('screenshots');
          metadata.addAll({
            'target': target,
            'controller': controller,
            'syntheticNumber': number,
            'runId': runId,
            'independentCallChecks': checks,
            'savedScreenshots': screenshots,
            'targetRestored': targetRestored,
            'inspectionError': inspectionError?.toString(),
          });
          await File('${directory.path}/result.json')
              .writeAsString(jsonEncode(metadata), flush: true);
          if (inspectionError != null ||
              !targetRestored ||
              checks.map((c) => c['stage']).join(',') != expected.join(',') ||
              [
                'currentCallUiComplete',
                'incomingCallReminderHandled',
                'formalCallsPageObservedRinging',
                'formalOpenSystemCallActionVerified',
                'decodedFrameVerified',
                'fullRemotePageVerified',
                'callRemainsRinging',
                'ownedSessionsStopped',
                'targetFixtureRestored',
                'observationRestored',
                'settingsRestored',
                'connectionsRestored',
                'focusRestored',
                'ownedCleanupComplete',
              ].any((key) => metadata[key] != true) ||
              !screenshots.contains('controller-decoded-incall.png')) {
            throw StateError(
              'Actual CallsPage → system call UI acceptance did not complete: ${inspectionError ?? 'missing required evidence/cleanup'}',
            );
          }
        },
      );
    },
    () => {
      'current-call inspection': () async {
        finished = true;
        await inspection;
      },
      'owned incoming call': cleanupTarget,
      'driver connection': () => driverRpc(driver.close()),
    },
  );
}
