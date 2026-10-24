import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:scrcpy_connect/connection/connection_policy.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/application/application_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// 使用应用装配的运行时，覆盖能力准入、包源识别、输出创建、音频策略和快照合并；原始核心解码器测试无法发现此边界缺失的编排。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('assembled runtime presents video and plays native PCM', (
    tester,
  ) async {
    final evidence = <String, dynamic>{};
    binding.reportData = {'assembledMedia': evidence};
    ApplicationSession? runtime;
    StreamSubscription<Map<String, dynamic>>? subscription;
    final events = <Map<String, dynamic>>[];
    String? device, session, audio;
    Future<T> real<T>(Future<T> Function() action) async {
      Object? value, failure;
      StackTrace? trace;
      await tester.runAsync(() async {
        try {
          value = await action();
        } catch (error, stack) {
          failure = error;
          trace = stack;
        }
      });
      if (failure != null) Error.throwWithStackTrace(failure!, trace!);
      return value as T;
    }

    try {
      runtime = await real(() async {
        final support = await getApplicationSupportDirectory();
        return ApplicationSession.initialize(
          dataDirectory:
              const String.fromEnvironment('CONNECT_E2E_DATA_DIRECTORY').isEmpty
              ? '${support.path}/assembled-media-lifecycle'
              : const String.fromEnvironment('CONNECT_E2E_DATA_DIRECTORY'),
          connectionPolicy: const ConnectionPolicy(
            requestAuthorization: true,
            healthEnabled: false,
            reconnectEnabled: false,
          ),
        );
      });
      subscription = runtime!.events.listen(events.add);
      final video = await real(() async {
        if (!Platform.isIOS) {
          await runtime!.request('settings.update', {
            'backgroundKeepAlive': const bool.fromEnvironment(
              'CONNECT_E2E_BACKGROUND_PLAYBACK',
            ),
          });
        }
        final added = await runtime!.request('devices.add', {
          'address': const String.fromEnvironment(
            'CONNECT_E2E_ADDRESS',
            defaultValue: '10.0.2.2',
          ),
          'port': const int.fromEnvironment(
            'CONNECT_E2E_PORT',
            defaultValue: 15556,
          ),
        });
        device = added['deviceId'] as String;
        await runtime!.request('devices.connect', {'deviceId': device});
        final result = await runtime!.request('session.start', {
          'deviceId': device,
          'videoCodec': 'h264',
          'maxSize': 640,
          'maxFps': 30,
        });
        session = result['sessionId'] as String;
        expect(result['textureId'], isA<int>());
        expect(result['firstFrameDecoded'], true);
        expect(result['backend'], 'media_codec');
        expect(result['decoderName'], isNotEmpty);
        evidence['video'] = result;
        return result;
      });
      final surfaceKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: AspectRatio(
              aspectRatio:
                  (video['decodedWidth'] as num) /
                  (video['decodedHeight'] as num),
              child: RepaintBoundary(
                key: surfaceKey,
                child: Texture(textureId: video['textureId'] as int),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final boundary =
          surfaceKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final colors = <int>{};
        for (var i = 0; i < bytes.length; i += 4) {
          colors.add(bytes[i] << 16 | bytes[i + 1] << 8 | bytes[i + 2]);
        }
        expect(colors.length, greaterThan(32));
        evidence['textureOnlyColors'] = colors.length;
      } finally {
        image.dispose();
      }
      await real(() async {
        final paused = await runtime!.request('session.pause', {
          'sessionId': session,
        });
        expect(paused['paused'], true);
        final resumed = await runtime!.request('session.resume', {
          'sessionId': session,
        });
        expect(resumed['paused'], false);
        expect(resumed['firstFrameDecoded'], true);
        final audioSamples = <Map<String, dynamic>>[];
        evidence['audioStartupSamples'] = audioSamples;
        final sampling = Timer.periodic(const Duration(milliseconds: 250), (
          _,
        ) async {
          try {
            final status = await runtime!.request('audio.status');
            if (audioSamples.length == 8) audioSamples.removeAt(0);
            audioSamples.add({
              'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
              'status': status,
            });
          } catch (_) {
            // 最终关闭可能与仅诊断用途的采样竞争。
          }
        });
        late final Map<String, dynamic> ready;
        try {
          ready = await runtime!.request('audio.start', {'deviceId': device});
        } on ApplicationCommandException catch (error) {
          evidence['audioFailure'] = {
            'code': error.code,
            'message': error.message,
            'details': error.details,
          };
          rethrow;
        } finally {
          sampling.cancel();
        }
        audio = ready['sourceId'] as String;
        expect(ready['nativeReady'], true);
        expect(ready['bytesWritten'], greaterThan(0));
        expect(ready['playingConfirmed'], true);
        evidence['audio'] = ready;
        final snapshot = await runtime!.request('state.snapshot');
        final sessions = snapshot['sessions'] as List;
        expect(
          sessions
              .where((item) => item['sessionId'] == session)
              .single['textureId'],
          video['textureId'],
        );
        final sources = snapshot['sources'] as List;
        expect(
          sources
              .where((item) => item['sourceId'] == audio)
              .single['nativeAttached'],
          true,
        );
        expect(snapshot['transfers'], isA<List<dynamic>>());
        await runtime!.request('audio.stop', {
          'deviceId': device,
          'sourceId': audio,
        });
        audio = null;
        await runtime!.request('session.stop', {'sessionId': session});
        session = null;
        expect((await runtime!.request('session.list'))['sessions'], isEmpty);
        evidence['outputReadyEvents'] = events
            .where((event) => event['type'] == 'session.output.ready')
            .length;
        expect(evidence['outputReadyEvents'], 1);
      });
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      binding.reportData!['mediaAcceptanceComplete'] = true;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await subscription?.cancel();
      await real(() async {
        final activeRuntime = runtime;
        if (activeRuntime == null) return;
        try {
          if (audio != null) {
            await activeRuntime.request('audio.stop', {
              'deviceId': device,
              'sourceId': audio,
            });
          }
          if (session != null) {
            await activeRuntime.request('session.stop', {'sessionId': session});
          }
          if (device != null) {
            await activeRuntime.request('devices.disconnect', {
              'deviceId': device,
            });
          }
        } finally {
          await activeRuntime.shutdown();
        }
      });
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
