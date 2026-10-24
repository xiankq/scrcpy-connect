import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/media/output/audio_player_port.dart';
import 'package:scrcpy_connect/platform/audio/mixer_audio_focus_registry.dart';
import 'package:scrcpy_connect/media/output/audio_output_coordinator.dart';
import 'package:scrcpy_connect/media/output/video_output_coordinator.dart';
import 'package:scrcpy_connect/media/quality/video_quality_policy.dart';
import 'package:scrcpy_connect/application/lifecycle/ordered_disposal.dart';

import 'support/media_owner_fixture.dart';

import 'package:path_provider/path_provider.dart';

/// 使用直接 PCM 输出和系统焦点、前台服务适配器的真实宿主与目标测试；原生接受字节证据不代表扬声器实际可听。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('remote PCM audio-only lifecycle has honest playback evidence', (
    tester,
  ) async {
    const channel = MethodChannel('dev.scrcpyconnect/platform');
    const nativeEvents = EventChannel('dev.scrcpyconnect/media_events');
    final support = await getApplicationSupportDirectory();
    final report = <AudioJson>[];
    binding.reportData = {'mediaAudioLifecycle': report};
    final emitted = <AudioJson>[];
    var disposed = false;
    String? device, source;
    AudioJson? stream;
    MediaOwnerFixture? owner;
    Future<AudioJson> request(String method, AudioJson params) async {
      final fixture = owner!;
      if (fixture.sessions.handles(method)) {
        return fixture.sessions.command(method, params);
      }
      if (method.startsWith('audio.')) {
        return Map<String, dynamic>.from(
          await fixture.audio.command(method, params),
        );
      }
      if (method == 'media.open' && params['kind'] == 'audio') {
        return Map<String, dynamic>.from(
          await fixture.audio.openSource(
            params['sourceId'] as String,
            generation: params['generation'] as int? ?? 1,
          ),
        );
      }
      if (method == 'media.status') {
        return fixture.sourceStatus(params['relayId'] as String);
      }
      throw ApplicationCommandException(
        'unknown_command',
        '测试没有提供此媒体操作：$method',
      );
    }

    final mixerAudio = MixerAudioFocusRegistry(
      backgroundPlaybackSupported: !Platform.isIOS,
    );
    final outputs = AudioOutputCoordinator(
      request: request,
      platform: (method, params) async {
        if (!Platform.isAndroid) return mixerAudio.request(method, params);
        final raw = await channel.invokeMethod<Object?>(method, params);
        return raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
      },
      emit: emitted.add,
      isDisposed: () => disposed,
    );
    final video = VideoOutputCoordinator(
      request: request,
      openSource: (stream, generation) =>
          owner!.videoSource.openSource(stream, generation),
      emit: emitted.add,
      isDisposed: () => disposed,
    );
    final subscription = Platform.isAndroid
        ? nativeEvents.receiveBroadcastStream().listen((dynamic raw) {
            if (raw is Map) {
              unawaited(
                outputs.handlePlatformEvent(Map<String, dynamic>.from(raw)),
              );
            }
          })
        : null;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('共享声音实际生命周期验证'))),
    );
    try {
      await tester.runAsync(() async {
        owner = await MediaOwnerFixture.open(
          dataDirectory:
              const String.fromEnvironment('CONNECT_E2E_DATA_DIRECTORY').isEmpty
              ? '${support.path}/media-audio-lifecycle'
              : const String.fromEnvironment('CONNECT_E2E_DATA_DIRECTORY'),
          address:
              '${const String.fromEnvironment('CONNECT_E2E_ADDRESS', defaultValue: '10.0.2.2')}:'
              '${const String.fromEnvironment('CONNECT_E2E_PORT', defaultValue: '15556')}',
        );
        device = owner!.deviceId;
        await outputs.setVisible(
          binding.lifecycleState == AppLifecycleState.resumed,
        );
        await outputs.policy(
          const bool.fromEnvironment('CONNECT_MEDIA_BACKGROUND_AUDIO'),
        );
        final capture = await request('session.start', {
          ...defaultVideoQuality,
          'deviceId': device,
          'maxSize': 640,
          'maxFps': 30,
        });
        final rendered = await video.start(capture);
        await request('session.ready', {...capture, ...rendered});
        stream = await request('audio.start', {'deviceId': device});
        source = stream!['sourceId'] as String;
        final AudioJson ready;
        try {
          ready = await outputs.start(stream!);
        } catch (error) {
          report.add({
            'stage': 'native-start-failure',
            'code': error is ApplicationCommandException
                ? error.code
                : 'test_failure',
            'status': outputs.status(),
            if (error is ApplicationCommandException) 'details': error.details,
          });
          rethrow;
        }
        report.add({'stage': 'ready', ...ready});
        expect(ready['mediaInfoReady'], true);
        expect(ready['playingConfirmed'], true);
        expect(ready['sourcePcmReceived'], true);
        expect(ready['playbackClockAdvanced'], true);
        expect(ready['nativeReady'], true);
        expect(ready['bytesWritten'], greaterThan(0));
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
        'code': error is ApplicationCommandException
            ? error.code
            : 'test_failure',
        'reason': '$error',
        if (error is ApplicationCommandException) 'details': error.details,
      });
      rethrow;
    } finally {
      await tester.runAsync(() async {
        disposed = true;
        await OrderedDisposal([
          outputs.dispose,
          () async {
            await video.dispose();
          },
          () async {
            await subscription?.cancel();
          },
          () async {
            await owner?.close();
          },
        ]).run();
      });
      debugPrint('[media-audio-lifecycle] ${jsonEncode(report)}');
    }
    expect(tester.takeException(), isNull);
    binding.reportData!['mediaAcceptanceComplete'] = true;
  }, timeout: const Timeout(Duration(minutes: 3)));
}
