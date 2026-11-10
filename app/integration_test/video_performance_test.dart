import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:scrcpy_connect/services/video_player.dart';
import 'package:scrcpy_connect/services/video_output_service.dart';
import 'package:scrcpy_connect/services/video_quality_policy.dart';
import 'package:path_provider/path_provider.dart';

import 'support/media_owner_fixture.dart';

// 独立夹具在每次 DPAD_DOWN 改变四条色带；识别其序列以检测旧帧，不单凭回执。
int? pattern(List<int> rgba, int width, int height, {ui.Rect? region}) {
  final bounds =
      region ?? ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  var counter = 0;
  for (var bit = 0; bit < 4; bit++) {
    final x = (bounds.left + bounds.width * (bit + .5) / 4).floor();
    final offset = (bounds.center.dy.floor() * width + x) * 4;
    final r = rgba[offset], g = rgba[offset + 1], b = rgba[offset + 2];
    if (r > 30 && r > g * 1.5 && r > b * 1.5) {
      counter |= 1 << bit;
    } else if (!(b > 60 && b > r * 1.5 && g > r * 1.5)) {
      return null;
    }
  }
  return counter;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var fixtureReady = false;
  developer.registerExtension('ext.connect.videoPerformance', (_, args) async {
    if (args['ready'] == 'true') fixtureReady = true;
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'ready': fixtureReady}),
    );
  });
  testWidgets('packet decoder preserves freshness across repeated sessions', (
    tester,
  ) async {
    final rounds = <VideoJson>[];
    binding.reportData = {
      'videoPerformanceComplete': false,
      'backend': 'media_codec',
      'measurement':
          'input request to recognized readback; includes readback overhead',
      'rounds': rounds,
    };
    MediaOwnerFixture? fixture;
    Future<VideoJson> request(
      String command, [
      VideoJson params = const {},
    ]) async {
      final owner = fixture;
      if (owner == null) throw StateError('媒体测试所有者尚未打开。');
      if (command.startsWith('session.')) {
        return owner.sessions.command(command, params);
      }
      if (command == 'media.status') {
        final source = params['relayId'];
        if (source is! String || source.isEmpty) {
          throw ArgumentError.value(source, 'relayId', '缺少精确原生来源身份。');
        }
        return owner.sourceStatus(source);
      }
      throw UnsupportedError('媒体测试不处理 $command');
    }

    Future<T> real<T>(Future<T> Function() action) async =>
        (await tester.runAsync(action)) as T;
    var disposed = false;
    late VideoPlayer player;
    final decoderEvents = <VideoJson>[];
    final outputs = VideoOutputService(
      request: request,
      openSource: (stream, generation) =>
          fixture!.videoSource.openSource(stream, generation),
      emit: (_) {},
      isDisposed: () => disposed,
      playerFactory: () {
        player = VideoPlayer();
        player.events.listen((event) {
          if (event['category'] == 'decoder.video') {
            decoderEvents.add({...event});
          }
        });
        return player;
      },
    );
    final textureKey = GlobalKey();
    String? device, session;
    var expected = 0;
    try {
      await real(() async {
        final deadline = Stopwatch()..start();
        while (!fixtureReady) {
          if (deadline.elapsed > const Duration(seconds: 40)) {
            throw StateError('Fixture not ready');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        final support = await getApplicationSupportDirectory();
        const address = String.fromEnvironment(
          'CONNECT_E2E_ADDRESS',
          defaultValue: '10.0.2.2',
        );
        const port = int.fromEnvironment(
          'CONNECT_E2E_PORT',
          defaultValue: 15556,
        );
        fixture = await MediaOwnerFixture.open(
          dataDirectory:
              const String.fromEnvironment('CONNECT_E2E_DATA_DIRECTORY').isEmpty
              ? '${support.path}/packet-video-performance'
              : const String.fromEnvironment('CONNECT_E2E_DATA_DIRECTORY'),
          address: Uri(host: address, port: port).authority,
        );
        device = fixture!.deviceId;
      });
      const count = int.fromEnvironment('CONNECT_PERF_ROUNDS', defaultValue: 3);
      const transitions = int.fromEnvironment(
        'CONNECT_PERF_TRANSITIONS',
        defaultValue: 8,
      );
      if (count < 1 || count > 30 || transitions < 1 || transitions > 100) {
        throw StateError('Invalid sample count');
      }
      for (var round = 0; round < count; round++) {
        final evidence = <String, dynamic>{
          'round': round,
          'inputToDecodedMs': <int>[],
        };
        rounds.add(evidence);
        decoderEvents.clear();
        final ready = await real(() async {
          final watch = Stopwatch()..start();
          final stream = await request('session.start', {
            ...defaultVideoQuality,
            'deviceId': device,
            'videoCodec': 'h264',
            'maxSize': 720,
            'maxFps': 60,
          });
          session = stream['sessionId'] as String;
          final coreStartMs = watch.elapsedMilliseconds;
          evidence['coreStartMs'] = coreStartMs;
          evidence['coreStartupTimingMs'] = stream['captureStartupTimingMs'];
          final output = await outputs.start(stream);
          evidence['startToDecodedMs'] = watch.elapsedMilliseconds;
          evidence['outputToDecodedMs'] =
              watch.elapsedMilliseconds - coreStartMs;
          evidence['decoderEvents'] = List<VideoJson>.from(decoderEvents);
          await request('session.ready', {'sessionId': session, ...output});
          final pixels = await player.snapshot(width: 64, height: 64);
          if (pixels == null ||
              pattern(pixels.rgba, pixels.width, pixels.height) == null) {
            throw StateError('Fixture pixels not recognized');
          }
          expected = pattern(pixels.rgba, pixels.width, pixels.height)!;
          return output;
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: textureKey,
                child: AspectRatio(
                  aspectRatio:
                      (ready['decodedWidth'] as num) /
                      (ready['decodedHeight'] as num),
                  child: Texture(textureId: ready['textureId'] as int),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await real(() async {
          for (var sample = 0; sample < transitions; sample++) {
            expected = (expected + 1) & 15;
            final watch = Stopwatch()..start();
            await request('session.key', {
              'sessionId': session,
              'captureGeneration': ready['captureGeneration'],
              'keyCode': 20,
              'action': 'press',
            });
            while (true) {
              final pixels = await player.snapshot(width: 64, height: 64);
              if (pixels != null &&
                  pattern(pixels.rgba, pixels.width, pixels.height) ==
                      expected) {
                break;
              }
              if (watch.elapsed > const Duration(seconds: 3)) {
                throw StateError('Stale decoded frame');
              }
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            (evidence['inputToDecodedMs'] as List<int>).add(
              watch.elapsedMilliseconds,
            );
          }
          await outputs.pause(session!);
          await request('session.pause', {'sessionId': session});
          await request('session.resume', {'sessionId': session});
          await outputs.resume(session!);
        });
        await tester.pump(const Duration(milliseconds: 100));
        final surface =
            textureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await surface.toImage(pixelRatio: .25);
        try {
          final rgba = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(rgba, isNotNull);
          final observed = pattern(
            rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
            image.width,
            image.height,
          );
          expect(
            observed,
            expected,
            reason: 'The Flutter texture must show the latest fixture counter',
          );
          evidence['flutterReadbackCaptured'] = true;
          evidence['flutterCounterMatched'] = true;
        } finally {
          image.dispose();
        }
        await tester.pumpWidget(const SizedBox());
        await real(() async {
          evidence['stop'] = await outputs.stop(session!);
          await request('session.stop', {'sessionId': session});
          session = null;
        });
      }
      final timings = [
        for (final round in rounds) ...(round['inputToDecodedMs'] as List<int>),
      ]..sort();
      binding.reportData!['inputToDecodedP50Ms'] =
          timings[(timings.length * .50).ceil() - 1];
      binding.reportData!['inputToDecodedP95Ms'] =
          timings[(timings.length * .95).ceil() - 1];
      for (final round in rounds) {
        expect(
          round['startToDecodedMs'],
          lessThanOrEqualTo(
            const int.fromEnvironment(
              'CONNECT_PERF_MAX_START_MS',
              defaultValue: 1000,
            ),
          ),
        );
      }
      expect(
        binding.reportData!['inputToDecodedP95Ms'],
        lessThanOrEqualTo(
          const int.fromEnvironment(
            'CONNECT_PERF_MAX_P95_MS',
            defaultValue: 300,
          ),
        ),
      );
      expect(
        binding.reportData!['inputToDecodedP50Ms'],
        lessThanOrEqualTo(
          const int.fromEnvironment(
            'CONNECT_PERF_MAX_P50_MS',
            defaultValue: 200,
          ),
        ),
      );
      binding.reportData!['videoPerformanceComplete'] = true;
    } finally {
      await tester.pumpWidget(const SizedBox());
      await real(() async {
        try {
          disposed = true;
          await outputs.dispose();
          if (session != null) {
            await request('session.stop', {'sessionId': session});
          }
        } finally {
          await fixture?.close();
        }
      });
    }
  });
}
