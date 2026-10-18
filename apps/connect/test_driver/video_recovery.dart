import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

/// A byte-transparent fault point in the controller's actual ADB transport.
/// Socket.addStream propagates backpressure; no ADB payload is inspected/saved.
class _AdbProxy {
  _AdbProxy(this.upstreamPort);

  final int upstreamPort;
  final events = <Map<String, Object?>>[];
  final _pairs = <_SocketPair>{};
  final _tasks = <Future<void>>{};
  ServerSocket? _server;
  StreamSubscription<Socket>? _subscription;
  bool _closed = false;
  int accepts = 0;
  int? cutAcceptCount;

  void _event(String kind, [Map<String, Object?> details = const {}]) {
    events.add({
      'kind': kind,
      'at': DateTime.now().toUtc().toIso8601String(),
      'acceptCount': accepts,
      ...details,
    });
  }

  Future<void> start() async {
    _server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      25557,
      shared: false,
    ).timeout(const Duration(seconds: 10));
    _event('listening', {'port': 25557, 'upstreamPort': upstreamPort});
    _subscription = _server!.listen((socket) {
      if (_closed) {
        socket.destroy();
        return;
      }
      final pair = _SocketPair(++accepts, socket);
      _pairs.add(pair);
      _event('accept', {'socketId': pair.id});
      final task = _forward(pair);
      _tasks.add(task);
      unawaited(task.then((_) => _tasks.remove(task)));
    }, onError: (Object error) => _event('listener-error'));
  }

  Future<void> _forward(_SocketPair pair) async {
    try {
      final upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        upstreamPort,
        timeout: const Duration(seconds: 10),
      );
      pair.upstream = upstream;
      if (pair.closed || _closed) {
        upstream.destroy();
        return;
      }
      _event('upstream-connected', {'socketId': pair.id});
      Future<void> pipe(Socket source, Socket destination) async {
        try {
          await destination.addStream(source);
        } catch (_) {
          if (!pair.closed) _event('pipe-error', {'socketId': pair.id});
        } finally {
          // EOF or an error in either direction terminates the same ADB pair.
          pair.close();
        }
      }

      await Future.wait([
        pipe(pair.controller, upstream),
        pipe(upstream, pair.controller),
      ]);
    } catch (_) {
      if (!pair.closed) _event('upstream-error', {'socketId': pair.id});
    } finally {
      pair.close();
      _pairs.remove(pair);
      _event('closed', {'socketId': pair.id});
    }
  }

  void cutTransport() {
    if (cutAcceptCount != null) throw StateError('Transport already cut.');
    final active = _pairs.where((pair) => !pair.closed).toList();
    if (active.length != 1 || active.single.upstream == null) {
      throw StateError('Expected exactly one connected controller ADB socket.');
    }
    cutAcceptCount = accepts;
    _event('cut-transport', {'socketId': active.single.id});
    active.single.close();
  }

  bool get reconnected =>
      cutAcceptCount != null &&
      events.any(
        (event) =>
            event['kind'] == 'upstream-connected' &&
            (event['socketId']! as int) > cutAcceptCount!,
      );

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Destroy before awaiting the listener so no blocked pipe delays shutdown.
    for (final pair in _pairs) {
      pair.close();
    }
    await _server?.close().timeout(const Duration(seconds: 5));
    await _subscription?.cancel().timeout(const Duration(seconds: 5));
    await Future.wait(_tasks.toList()).timeout(const Duration(seconds: 15));
    _event('stopped');
  }
}

class _SocketPair {
  _SocketPair(this.id, this.controller);

  final int id;
  final Socket controller;
  Socket? upstream;
  bool closed = false;

  void close() {
    if (closed) return;
    closed = true;
    controller.destroy();
    upstream?.destroy();
  }
}

Future<void> main() async {
  const package = 'dev.scrcpyconnect.videofixture';
  final environment = Platform.environment;
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

  Future<ProcessResult> runAdb(List<String> args) => Process.run(adb, [
    '-s',
    target,
    ...args,
  ]).timeout(const Duration(seconds: 30));

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
  final proxy = _AdbProxy(upstreamPort);
  FlutterDriver? driver;
  Future<void>? polling;
  var finished = false;
  var fixtureOwned = false;
  var cleanupFinished = false;
  Object? pollingError;
  Object? primaryError;
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
    // Ownership begins before install so a partial/timeout install is cleaned.
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
                args: ready ? null : {'ready': 'true'},
              )
              .timeout(const Duration(seconds: 10));
          if (finished) return;
          ready = response.json?['ready'] == true;
          final checkpoint = response.json?['checkpoint'];
          if (checkpoint is Map && checkpoint['name'] == 'cut-transport') {
            if (!cut) {
              proxy.cutTransport();
              cut = true;
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
          // integrationDriver closes its driver before invoking our callback.
          // Record errors without rethrowing from this concurrent task.
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
        report['proxyCutAcceptCount'] = proxy.cutAcceptCount;
        report['proxyReconnected'] = proxy.reconnected;
        report['pollingError'] = pollingError?.toString();
        // Save the failing app result before acceptance checks and cleanup.
        await writeJson('result', report);
        // integrationDriver exits the VM: finally alone cannot own cleanup.
        await cleanUp();
        if (report['videoRecoveryComplete'] != true) {
          throw StateError('Actual video recovery did not complete.');
        }
        if (!proxy.reconnected) {
          throw StateError('No new actual controller ADB transport after cut.');
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
