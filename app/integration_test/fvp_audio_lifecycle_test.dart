import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:interop_bridge/src/interop_exception.dart';
import 'package:interop_bridge/src/media/portable_audio.dart';
import 'package:interop_bridge/src/media/portable_video.dart';
import 'package:interop_bridge/src/rust/api.dart' as core;
import 'package:interop_bridge/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';

/// Opt-in real host/target test. Uses the public MDK audio-only Player and the
/// thin OS focus/FGS adapter, never audio.start on the old native PCM player.
/// Clock/source evidence is deliberately not an assertion of audible samples.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shared fvp audio-only lifecycle has honest playback evidence', (
    tester,
  ) async {
    const channel = MethodChannel('dev.scrcpyconnect/platform');
    const nativeEvents = EventChannel('dev.scrcpyconnect/media_events');
    final support = await getApplicationSupportDirectory();
    final report = <AudioJson>[];
    binding.reportData = {'fvpAudioLifecycle': report};
    final emitted = <AudioJson>[];
    var disposed = false;
    String? device, source, session;
    AudioJson? stream;
    Future<AudioJson> request(String method, AudioJson params) async {
      final envelope = jsonDecode(
        await core.invoke(
          requestJson: jsonEncode({'command': method, 'params': params}),
        ),
      ) as AudioJson;
      if (envelope['ok'] != true) {
        throw StateError('$method: ${envelope['error']}');
      }
      return envelope['data'] as AudioJson;
    }

    final outputs = PortableAudioOutputs(
      core: request,
      platform: (method, params) async {
        final raw = await channel.invokeMethod<Object?>(method, params);
        return raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
      },
      emit: emitted.add,
      isDisposed: () => disposed,
    );
    final video = PortableVideoOutputs(
      core: request,
      emit: emitted.add,
      isDisposed: () => disposed,
    );
    final subscription = nativeEvents.receiveBroadcastStream().listen((
      dynamic raw,
    ) {
      if (raw is Map) {
        unawaited(outputs.handlePlatformEvent(Map<String, dynamic>.from(raw)));
      }
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('共享声音实际生命周期验证'))),
    );
    await tester.runAsync(() async {
      await RustLib.init();
      await core.initialize(
        dataDirectory: '${support.path}/fvp-audio-lifecycle',
      );
    });
    try {
      await tester.runAsync(() async {
        await outputs.setVisible(
          binding.lifecycleState == AppLifecycleState.resumed,
        );
        final added = await request('devices.add', {
          'address': const String.fromEnvironment(
            'CONNECT_E2E_ADDRESS',
            defaultValue: '10.0.2.2',
          ),
          'port': int.parse(
            const String.fromEnvironment(
              'CONNECT_E2E_PORT',
              defaultValue: '15556',
            ),
          ),
        });
        device = (added['device'] as AudioJson)['id'] as String;
        await request('devices.connect', {'deviceId': device});
        final capture = await request('session.start', {
          'deviceId': device,
          'maxSize': 640,
          'maxFps': 30,
        });
        session = capture['sessionId'] as String;
        final rendered = await video.start(capture);
        await request('session.ready', {...capture, ...rendered});
        stream = await request('audio.start', {'deviceId': device});
        source = stream!['sourceId'] as String;
        final ready = await outputs.start(stream!);
        report.add({'stage': 'ready', ...ready});
        expect(ready['mediaInfoReady'], true);
        expect(ready['playingConfirmed'], true);
        expect(ready['sourcePcmReceived'], true);
        expect(ready['playbackClockAdvanced'], true);
        expect(ready.containsKey('bytesWritten'), false);
        expect(ready['speakerSamplesVerified'], false);
        final attached = await request('audio.ready', ready);
        expect(attached['nativeAttached'], true);
        final paused = await outputs.pause(source!);
        await request('audio.presentation', paused);
        expect(paused['playState'], 'paused');
        final pauseClock = <int>[outputs.status(source!)['positionMs'] as int];
        for (var sample = 0; sample < 5; sample++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          pauseClock.add(outputs.status(source!)['positionMs'] as int);
        }
        report.add({
          'stage': 'paused',
          ...paused,
          'clockSamplesEvery200Ms': pauseClock,
        });
        expect(
          pauseClock.last - pauseClock.first,
          lessThanOrEqualTo(150),
          reason: 'Paused output may settle a bounded renderer buffer, not continue playing.',
        );
        expect(
          (pauseClock.last - pauseClock[pauseClock.length - 2]).abs(),
          lessThanOrEqualTo(20),
          reason: 'The real audio clock must settle and stay paused.',
        );
        final configured = await outputs.volume(
          source!,
          volume: .25,
          muted: true,
        );
        expect(configured['volumeConfigured'], true);
        expect(configured['volumeOutputVerified'], false);
        await request('audio.volume', configured);
        final resumed = await outputs.resume(source!);
        await request('audio.presentation', resumed);
        expect(resumed['playState'], 'playing');
        final before = outputs.status(source!)['positionMs'] as int;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final after = outputs.status(source!)['positionMs'] as int;
        expect(after, greaterThan(before));
        report.add({
          'stage': 'resumed',
          ...resumed,
          'clockDeltaMs': after - before,
        });
        report.add({'stage': 'stopped', ...await outputs.stop(source!)});
        await request('audio.stop', {'sourceId': source, 'deviceId': device});
        source = null;
      });
    } catch (error) {
      report.add({
        'stage': 'failure',
        'code': error is InteropException ? error.code : 'test_failure',
        'reason': '$error',
        if (error is InteropException) 'details': error.details,
      });
      rethrow;
    } finally {
      await tester.runAsync(() async {
        await outputs.dispose();
        await video.dispose();
        if (session != null) {
          await request('session.stop', {'sessionId': session});
        }
        disposed = true;
        await subscription.cancel();
        if (source != null) {
          await request('audio.stop', {'sourceId': source, 'deviceId': device});
        }
        if (device != null) {
          await request('devices.disconnect', {'deviceId': device});
        }
      });
      debugPrint('[fvp-audio-lifecycle] ${jsonEncode(report)}');
    }
    expect(tester.takeException(), isNull);
    binding.reportData!['mediaAcceptanceComplete'] = true;
  }, timeout: const Timeout(Duration(minutes: 3)));
}
