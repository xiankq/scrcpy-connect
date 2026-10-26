import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import 'support/adb_fault_proxy.dart';
import '../../scripts/src/process.dart';

Future<void> main() async {
  const package = 'dev.scrcpyconnect.videofixture';
  final environment = Platform.environment;
  final faultName = environment['CONNECT_E2E_RECOVERY_FAULT'] ?? 'eof';
  final AdbRecoveryFault fault;
  switch (faultName) {
    case 'eof':
      fault = AdbRecoveryFault.eof;
    case 'blackhole':
      fault = AdbRecoveryFault.blackhole;
    default:
      throw StateError('CONNECT_E2E_RECOVERY_FAULT must be eof or blackhole.');
  }
  final adb = environment['CONNECT_E2E_ADB'];
  final target = environment['CONNECT_E2E_TARGET'];
  final controller = environment['CONNECT_E2E_DEVICE'];
  final apk = environment['CONNECT_E2E_VIDEO_FIXTURE'];
  if (adb == null ||
      adb.isEmpty ||
      target == null ||
      target.isEmpty ||
      controller == null ||
      controller.isEmpty ||
      target == controller ||
      apk == null ||
      apk.isEmpty) {
    throw StateError(
      'Set CONNECT_E2E_ADB, distinct DEVICE/TARGET, and CONNECT_E2E_VIDEO_FIXTURE.',
    );
  }
  final upstreamPort = int.tryParse(
    environment['CONNECT_E2E_UPSTREAM_PORT'] ?? '25556',
  );
  if (upstreamPort == null ||
      upstreamPort < 1 ||
      upstreamPort > 65535 ||
      upstreamPort == 25557) {
    throw StateError('Invalid CONNECT_E2E_UPSTREAM_PORT.');
  }
  final output = Directory(
    environment['CONNECT_E2E_CAPTURE_DIR'] ?? '/tmp/connect-e2e/video-recovery',
  );
  if (!output.absolute.uri.normalizePath().path.startsWith('/tmp/')) {
    throw StateError('Keep recovery evidence under /tmp.');
  }
  await output.create(recursive: true);
  if (!(await output.resolveSymbolicLinks()).startsWith('/tmp/')) {
    throw StateError('Keep recovery evidence under /tmp.');
  }
  Future<void> writeJson(String name, Object? value) async {
    await File('${output.path}/$name.json').writeAsString(jsonEncode(value));
  }

  Future<ProcessResult> runAdb(List<String> args) => runProcess(adb, [
    '-s',
    target,
    ...args,
  ], timeout: const Duration(seconds: 30));

  Future<String> command(List<String> args) async {
    final result = await runAdb(args);
    if (result.exitCode != 0) {
      throw StateError('Target ${args.first} failed (${result.exitCode}).');
    }
    return result.stdout as String;
  }

  Future<bool> fixtureExists() async {
    final result = await runAdb(['shell', 'pm', 'path', package]);
    if (result.exitCode != 0 &&
        (result.exitCode != 1 || '${result.stderr}'.trim().isNotEmpty)) {
      throw StateError('Cannot inspect fixture ownership.');
    }
    return '${result.stdout}'.trim().isNotEmpty;
  }

  if (await fixtureExists()) {
    throw StateError('Refusing to replace an existing fixture installation.');
  }
  final proxy = AdbFaultProxy(upstreamPort);
  FlutterDriver? driver;
  Future<void>? polling;
  var finished = false;
  var fixtureOwned = false;
  var cleanupFinished = false;
  Object? pollingError;
  Object? primaryError;
  Map<String, Object?>? faultChallenge;
  final cleanup = <String, Object?>{};

  Future<void> cleanUp() async {
    if (cleanupFinished) return;
    cleanupFinished = true;
    finished = true;
    Future<void> attempt(String name, Future<void> Function() action) async {
      try {
        await action();
        cleanup[name] = true;
      } catch (error) {
        cleanup[name] = false;
        cleanup['${name}Error'] = error.toString();
      }
    }

    await attempt('pollStopped', () async {
      await polling?.timeout(const Duration(seconds: 12));
    });
    await attempt('driverClosed', () async {
      await driver?.close().timeout(const Duration(seconds: 10));
    });
    await attempt('proxyClosed', proxy.close);
    await attempt(
      'proxyEvidenceSaved',
      () => writeJson('proxy-events', proxy.events),
    );
    if (fixtureOwned) {
      await attempt('uninstalled', () async {
        if (await fixtureExists()) {
          final result = await command(['uninstall', package]);
          if (!result.contains('Success')) {
            throw StateError('Fixture uninstall not confirmed.');
          }
        }
      });
      await attempt('absent', () async {
        if (await fixtureExists()) {
          throw StateError('Owned fixture remains installed.');
        }
      });
      await attempt('settingsRestored', () async {
        final result = await command([
          'shell',
          'am',
          'start',
          '-W',
          '-a',
          'android.settings.SETTINGS',
        ]);
        if (result.contains('Error') || result.contains('Exception')) {
          throw StateError('Cannot restore target Settings.');
        }
      });
    }
    await writeJson('cleanup', cleanup);
  }

  try {
    await proxy.start();
    // 安装前即确立所有权，确保部分安装或超时也能清理。
    fixtureOwned = true;
    if (!(await command(['install', apk])).contains('Success')) {
      throw StateError('Fixture installation not confirmed.');
    }
    final launch = await command([
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$package/.VideoPatternActivity',
      '--ez',
      'motion',
      'false',
    ]);
    if (launch.contains('Error') || launch.contains('Exception')) {
      throw StateError('Cannot launch the independent video fixture.');
    }
    final connected = await FlutterDriver.connect(logCommunicationToFile: false)
        .timeout(const Duration(seconds: 45));
    driver = connected;
    polling = () async {
      var ready = false;
      var cut = false;
      final deadline = DateTime.now().add(const Duration(minutes: 4));
      while (!finished && DateTime.now().isBefore(deadline)) {
        try {
          final response = await connected.serviceClient
              .callServiceExtension(
                'ext.connect.videoRecovery',
                isolateId: connected.appIsolate.id,
                args: ready ? null : {'ready': 'true', 'fault': fault.name},
              )
              .timeout(const Duration(seconds: 10));
          if (finished) return;
          ready = response.json?['ready'] == true;
          final checkpoint = response.json?['checkpoint'];
          if (checkpoint is Map && checkpoint['name'] == 'cut-transport') {
            if (!cut) {
              proxy.injectFault(fault);
              cut = true;
              if (fault == AdbRecoveryFault.blackhole) {
                // 静态编码器在故障期间可能没有输出；仅通过独立实验 ADB 修改本次夹具，ACK 前恢复初始判定内容；必须观察实际丢弃的上游帧，不能仅检查过滤器。
                //
                //
                //
                faultChallenge = {
                  'counterChanged': false,
                  'counterRestored': false,
                };
                await command(['shell', 'input', 'keyevent', '20']);
                faultChallenge!['counterChanged'] = true;
                final waiting = Stopwatch()..start();
                while (((proxy.faultEvidence['droppedBytes']
                                as Map)['upstream-to-controller']
                            as int) ==
                        0 &&
                    waiting.elapsed < const Duration(seconds: 3)) {
                  await Future<void>.delayed(const Duration(milliseconds: 25));
                }
                faultChallenge!['discardWaitMs'] = waiting.elapsedMilliseconds;
                final restored = await command([
                  'shell',
                  'am',
                  'start',
                  '-W',
                  '-n',
                  '$package/.VideoPatternActivity',
                  '--ez',
                  'motion',
                  'false',
                ]);
                if (restored.contains('Error') ||
                    restored.contains('Exception')) {
                  throw StateError('Cannot restore the owned fixture counter.');
                }
                faultChallenge!['counterRestored'] = true;
              }
              await writeJson('proxy-events', proxy.events);
            }
            await connected.serviceClient
                .callServiceExtension(
                  'ext.connect.videoRecovery',
                  isolateId: connected.appIsolate.id,
                  args: {'ack': 'cut-transport'},
                )
                .timeout(const Duration(seconds: 10));
          }
        } catch (error) {
          // integrationDriver 在调用回调前关闭 driver；并发任务只记录错误，不重新抛出。
          //
          if (!finished &&
              !error.toString().contains('Method not found') &&
              !error.toString().contains('ext.connect.videoRecovery')) {
            pollingError ??= error;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!finished) {
        pollingError ??= StateError(
          'Timed out waiting for recovery checkpoints.',
        );
      }
    }();
    await integrationDriver(
      driver: connected,
      writeResponseOnFailure: true,
      onScreenshot: (name, bytes, [args]) async {
        final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        await File('${output.path}/$safe.png').writeAsBytes(bytes);
        return true;
      },
      responseDataCallback: (data) async {
        finished = true;
        await polling;
        final report = {...?data}..remove('screenshots');
        report['proxyAcceptCount'] = proxy.accepts;
        report['proxyCutAcceptCount'] = proxy.faultAcceptCount;
        report['proxyReconnected'] = proxy.reconnected;
        report['proxyFault'] = fault.name;
        report['proxyFaultChallenge'] = faultChallenge;
        // 清理前先快照并验证；代理关闭不能制造旧主控 EOF 或满足恢复验收。
        //
        report['proxyFaultEvidence'] = proxy.faultEvidence;
        final evidenceErrors = proxy.recoveryEvidenceErrors();
        if (fault == AdbRecoveryFault.blackhole &&
            (faultChallenge?['counterChanged'] != true ||
                faultChallenge?['counterRestored'] != true)) {
          evidenceErrors.add(
            'Blackhole fixture frame challenge did not complete.',
          );
        }
        report['proxyFaultEvidenceErrors'] = evidenceErrors;
        report['pollingError'] = pollingError?.toString();
        // 验收检查与清理前先保存失败的应用结果。
        await writeJson('result', report);
        // integrationDriver 会退出 VM，不能仅由 finally 拥有清理责任。
        await cleanUp();
        if (report['videoRecoveryComplete'] != true) {
          throw StateError('Actual video recovery did not complete.');
        }
        if (evidenceErrors.isNotEmpty) {
          throw StateError(evidenceErrors.join(' '));
        }
        if (cleanup['uninstalled'] != true ||
            cleanup['absent'] != true ||
            cleanup['settingsRestored'] != true ||
            cleanup['proxyClosed'] != true ||
            cleanup['pollStopped'] != true) {
          throw StateError('Recovery fixture cleanup not confirmed.');
        }
      },
    ).timeout(const Duration(minutes: 5));
  } catch (error) {
    primaryError = error;
    rethrow;
  } finally {
    try {
      await cleanUp();
    } catch (_) {
      if (primaryError == null) rethrow;
    }
  }
}
