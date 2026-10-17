import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:interop_bridge/src/media/fvp_video_player.dart';
import 'package:interop_bridge/src/media/portable_video.dart';
import 'package:interop_bridge/src/media/video_presentation.dart';
import 'package:interop_bridge/src/rust/api.dart' as core;
import 'package:interop_bridge/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';

// Recognize the independent target's four bit color pattern, not a receipt,
// nonempty image, or different arbitrary pixels. Use the palette's channel
// ratios so RGB range/transfer conversion cannot masquerade as a stale frame.
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
  var hostReady = false;
  developer.registerExtension('ext.connect.videoPerformance', (_, args) async {
    if (args['ready'] == 'true') hostReady = true;
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'ready': hostReady}),
    );
  });
  testWidgets(
    'real decoded freshness, first frame, pause and repeated connections',
    (tester) async {
      const traceFrames = bool.fromEnvironment('CONNECT_PERF_TRACE_FRAMES');
      final rounds = <VideoJson>[];
      binding.reportData = {
        'videoPerformanceComplete': false,
        if (traceFrames) 'frameCorrelationComplete': false,
        'rounds': rounds,
      };
      Future<VideoJson> request(
        String command, [
        VideoJson params = const {},
      ]) async {
        final result = jsonDecode(
          await core.invoke(
            requestJson: jsonEncode({
              'command': command,
              'params': {
                ...params,
                if (traceFrames && command == 'media.open') 'traceFrames': true,
              },
            }),
          ),
        ) as VideoJson;
        if (result['ok'] != true) {
          throw StateError('$command: ${result['error']}');
        }
        return result['data'] as VideoJson;
      }

      Future<void> real(Future<void> Function() action) async {
        final completed = await tester.runAsync(() async {
          await action();
          return true;
        });
        if (completed != true) {
          throw StateError('Real-device stage failed; see original exception.');
        }
      }

      late VideoPlayerPort player;
      late List<VideoJson> decoderEvents;
      const decoderPolicy = String.fromEnvironment(
        'CONNECT_PERF_DECODER',
        defaultValue: 'platform',
      );
      const nativeOptions = String.fromEnvironment(
        'CONNECT_PERF_NATIVE_OPTIONS',
      );
      final decoderCandidates = switch (decoderPolicy) {
        'platform' => null,
        'native' => [
          'AMediaCodec${nativeOptions.isEmpty ? '' : ':$nativeOptions'}',
          'FFmpeg:thread_type=slice',
          'dav1d',
        ],
        'software' => const ['FFmpeg:thread_type=slice', 'dav1d'],
        'software-default' => const ['FFmpeg', 'dav1d'],
        _ => throw ArgumentError.value(decoderPolicy, 'CONNECT_PERF_DECODER'),
      };
      binding.reportData!['decoderPolicy'] = decoderPolicy;
      if (decoderPolicy == 'native') {
        binding.reportData!['nativeDecoderOptions'] = nativeOptions;
      }
      binding.reportData!['nativeFrameTrace'] = traceFrames;
      var disposed = false;
      final outputs = PortableVideoOutputs(
        core: request,
        emit: (_) {},
        isDisposed: () => disposed,
        playerFactory: () {
          final events = <VideoJson>[];
          decoderEvents = events;
          final instance = FvpVideoPlayer(
            videoDecoders: decoderCandidates,
            traceFrames: traceFrames,
          );
          // Closed by release along with this player's event stream. Retain
          // native decoder receipts, never infer a selection from priorities.
          instance.events.listen((event) {
            if (event['category'] == 'decoder.video' ||
                event['category'] == 'video.frameTrace') {
              events.add({...event});
            }
          });
          return player = instance;
        },
      );
      final presentation = VideoPresentation(
        core: request,
        pauseOutput: outputs.pause,
        resumeOutput: outputs.resume,
      );
      String? device, session;
      var expected = 0;
      try {
        await real(() async {
          final deadline = Stopwatch()..start();
          while (!hostReady) {
            if (deadline.elapsed > const Duration(seconds: 40)) {
              throw StateError('Host fixture not ready.');
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          await RustLib.init();
          final support = await getApplicationSupportDirectory();
          await core.initialize(
            dataDirectory: '${support.path}/video-performance',
          );
          final added = await request('devices.add', {
            'address': const String.fromEnvironment(
              'CONNECT_E2E_ADDRESS',
              defaultValue: '10.0.2.2',
            ),
            'port': const int.fromEnvironment(
              'CONNECT_E2E_PORT',
              defaultValue: 25556,
            ),
          });
          device = (added['device'] as VideoJson)['id'] as String;
        });
        const roundCount = int.fromEnvironment(
          'CONNECT_PERF_ROUNDS',
          defaultValue: 4,
        );
        const transitions = int.fromEnvironment(
          'CONNECT_PERF_TRANSITIONS',
          defaultValue: 8,
        );
        const keepConnection = bool.fromEnvironment(
          'CONNECT_PERF_KEEP_CONNECTION',
        );
        expect(roundCount, inInclusiveRange(1, 20));
        expect(transitions, inInclusiveRange(2, 100));
        var converted = false;
        final textureKey = GlobalKey();
        for (var round = 0; round < roundCount; round++) {
          final evidence = <String, dynamic>{
            'round': round,
            'inputToDecodedMs': <int>[],
            'samples': <VideoJson>[],
          };
          rounds.add(evidence);
          late VideoJson ready;
          await real(() async {
            final connected = Stopwatch()..start();
            if (!keepConnection || round == 0) {
              await request('devices.connect', {'deviceId': device});
            }
            evidence['connectMs'] = connected.elapsedMilliseconds;
            evidence['connectionReused'] = keepConnection && round > 0;
            final watch = Stopwatch()..start();
            final stream = await request('session.start', {
              'deviceId': device,
              'videoCodec': 'h264',
              'maxSize': 640,
              'maxFps': 30,
              'bitRate': 2000000,
            });
            session = stream['sessionId'] as String;
            evidence['sessionId'] = session;
            evidence['quality'] = stream['quality'];
            evidence['coreStartMs'] = watch.elapsedMilliseconds;
            evidence['coreStartupTimingMs'] = stream['captureStartupTimingMs'];
            if (keepConnection && round > 0) {
              expect(
                (stream['captureStartupTimingMs'] as VideoJson)['validatedMs'],
                lessThanOrEqualTo(
                  const int.fromEnvironment(
                    'CONNECT_PERF_MAX_WARM_VALIDATION_MS',
                    defaultValue: 5000,
                  ),
                ),
                reason: 'Repeated capture on an existing connection must meet its validation budget.',
              );
            }
            ready = await outputs.start(stream);
            evidence['decoderEvents'] = decoderEvents;
            if (decoderPolicy.startsWith('software')) {
              expect(
                decoderEvents.any(
                  (event) => event['error'] == 0 && event['detail'] == 'FFmpeg',
                ),
                true,
                reason: 'The software comparison requires an actual FFmpeg open receipt.',
              );
            }
            if (decoderPolicy == 'native') {
              expect(
                decoderEvents.any(
                  (event) =>
                      event['error'] == 0 && event['detail'] == 'AMediaCodec',
                ),
                true,
                reason: 'The native comparison requires an actual AMediaCodec open receipt.',
              );
            }
            evidence['startToDecodedMs'] = watch.elapsedMilliseconds;
            evidence['outputStartupTimingMs'] = ready['outputStartupTimingMs'];
            await request('session.ready', {
              'sessionId': session,
              'textureId': ready['textureId'],
            });
            final pixels = await player.snapshot(width: 64, height: 64);
            expect(pixels, isNotNull);
            evidence['initialSampleRGBA'] = [
              for (var bit = 0; bit < 4; bit++)
                pixels!.rgba.sublist(
                  (32 * 64 + (64 * (bit + .5) / 4).floor()) * 4,
                  (32 * 64 + (64 * (bit + .5) / 4).floor()) * 4 + 4,
                ),
            ];
            expect(pattern(pixels!.rgba, 64, 64), expected);
          });
          await tester.pumpWidget(
            MaterialApp(
              home: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    aspectRatio:
                        (ready['decodedWidth'] as int) /
                        (ready['decodedHeight'] as int),
                    child: Texture(
                      key: textureKey,
                      textureId: ready['textureId'] as int,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await real(() async {
            final before = await request('media.status', {
              'relayId': ready['relayId'],
            });
            final observation = Stopwatch()..start();
            for (var sample = 0; sample < transitions; sample++) {
              expected = (expected + 1) & 15;
              final traceBefore = (player as FvpVideoPlayer).frameTrace;
              final watch = Stopwatch()..start();
              await request('session.key', {
                'sessionId': session,
                'keyCode': 20,
                'action': 'press',
              });
              final controlMs = watch.elapsedMilliseconds;
              final reads = <int>[];
              while (true) {
                final read = Stopwatch()..start();
                final pixels = await player
                    .snapshot(width: 64, height: 64)
                    .timeout(const Duration(seconds: 3));
                reads.add(read.elapsedMilliseconds);
                if (pixels != null &&
                    pattern(pixels.rgba, 64, 64) == expected) {
                  break;
                }
                if (watch.elapsed > const Duration(seconds: 3)) {
                  throw StateError(
                    'Stale decoded pixels: round=$round sample=$sample expected=$expected',
                  );
                }
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
              final totalMs = watch.elapsedMilliseconds;
              (evidence['inputToDecodedMs'] as List<int>).add(totalMs);
              final traceAfter = (player as FvpVideoPlayer).frameTrace;
              VideoJson? matchedFrame;
              if (traceAfter != null) {
                final snapshot = traceAfter['snapshot'] as VideoJson;
                final pts = snapshot['ptsSeconds'] as num;
                final decoded = (traceAfter['decoded'] as List)
                    .cast<VideoJson>()
                    .where(
                      (frame) =>
                          ((frame['ptsSeconds'] as num) - pts).abs() < .000001,
                    )
                    .toList();
                expect(
                  decoded,
                  isNotEmpty,
                  reason: 'Trace must observe the same PTS actually returned by the renderer.',
                );
                matchedFrame = decoded.last;
              }
              final sampleEvidence = <String, dynamic>{
                'counter': expected,
                'controlMs': controlMs,
                'snapshotMs': reads,
                'totalMs': totalMs,
                'traceBefore': ?traceBefore,
                'traceAfter': ?traceAfter,
                if (matchedFrame != null)
                  'decodeToSnapshotUs':
                      (traceAfter!['snapshot'] as VideoJson)['elapsedUs'] -
                      matchedFrame['elapsedUs'],
              };
              if (matchedFrame != null) {
                // Read this sample's relay receipt before a long run can evict
                // it from the bounded native ring. This runs after timing ends.
                final transferred = await request('media.status', {
                  'relayId': ready['relayId'],
                });
                final pts =
                    (traceAfter!['snapshot'] as VideoJson)['ptsSeconds'] as num;
                final matches = (transferred['frameTrace'] as List)
                    .cast<VideoJson>()
                    .where(
                      // MDK's seconds conversion may truncate one microsecond.
                      (frame) =>
                          ((frame['ptsUs'] as num) - pts * 1000000).abs() <=
                          1.1,
                    )
                    .toList();
                expect(matches, hasLength(1));
                final forwarded = matches.single;
                final origin = traceAfter['clockOriginUs'] as int;
                sampleEvidence['relayFrame'] = forwarded;
                sampleEvidence['relayWriteUs'] =
                    (forwarded['writtenUs'] as int) -
                    (forwarded['writeStartedUs'] as int);
                sampleEvidence['relayToDecodeUs'] =
                    origin +
                    (matchedFrame['elapsedUs'] as int) -
                    (forwarded['writtenUs'] as int);
                sampleEvidence['inputToRelayUs'] =
                    (forwarded['muxStartedUs'] as int) -
                    (traceBefore!['nowElapsedUs'] as int) -
                    origin;
                expect(
                  sampleEvidence['relayToDecodeUs'] as int,
                  greaterThanOrEqualTo(0),
                );
              }
              (evidence['samples'] as List<VideoJson>).add(sampleEvidence);
            }
            final after = await request('media.status', {
              'relayId': ready['relayId'],
            });
            evidence['transferObservation'] = {
              'elapsedMs': observation.elapsedMilliseconds,
              'packets': (after['packets'] as int) - (before['packets'] as int),
              'bytes': (after['bytes'] as int) - (before['bytes'] as int),
              'frameTrace': ?after['frameTrace'],
            };
            const idleMs = int.fromEnvironment('CONNECT_PERF_IDLE_MS');
            expect(idleMs, inInclusiveRange(0, 10000));
            if (idleMs > 0) {
              final idle = Stopwatch()..start();
              await Future<void>.delayed(Duration(milliseconds: idleMs));
              final end = await request('media.status', {
                'relayId': ready['relayId'],
              });
              evidence['idleTransferObservation'] = {
                'elapsedMs': idle.elapsedMilliseconds,
                'packets': (end['packets'] as int) - (after['packets'] as int),
                'bytes': (end['bytes'] as int) - (after['bytes'] as int),
              };
            }
            final paused = await presentation.request('session.pause', {
              'sessionId': session,
            });
            expect(paused['capturePaused'], true);
            final resumed = await presentation.request('session.resume', {
              'sessionId': session,
            });
            expect(resumed['firstFrameDecoded'], true);
            expect(resumed['capturePaused'], false);
            evidence['pauseResumeVerified'] = true;
          });
          await tester.pump();
          if (!converted) {
            await binding.convertFlutterSurfaceToImage();
            converted = true;
          }
          await tester.pump();
          // Android's integration screenshot helper acquires an ImageView frame
          // before scheduling/waiting for the next Android frames. A successful
          // copy can therefore still contain the preceding round's composition.
          // Require actual new pixels within a bound; retain every stale capture.
          final surfaceWatch = Stopwatch()..start();
          final surfaceSamples = <VideoJson>[];
          evidence['surfaceSamples'] = surfaceSamples;
          for (var attempt = 0; attempt < 8; attempt++) {
            final screenshot = await binding
                .takeScreenshot(
                  attempt == 0
                      ? 'video-performance-$round'
                      : 'video-performance-$round-retry-$attempt',
                )
                .timeout(const Duration(seconds: 3));
            final imageCodec = await ui.instantiateImageCodec(
              Uint8List.fromList(screenshot),
            );
            final frame = await imageCodec.getNextFrame();
            try {
              final rgba = await frame.image.toByteData();
              final box =
                  textureKey.currentContext!.findRenderObject()! as RenderBox;
              final origin = box.localToGlobal(Offset.zero);
              final scaleX =
                  frame.image.width *
                  tester.view.devicePixelRatio /
                  tester.view.physicalSize.width;
              final scaleY =
                  frame.image.height *
                  tester.view.devicePixelRatio /
                  tester.view.physicalSize.height;
              final region = ui.Rect.fromLTWH(
                origin.dx * scaleX,
                origin.dy * scaleY,
                box.size.width * scaleX,
                box.size.height * scaleY,
              );
              final actual = pattern(
                rgba!.buffer.asUint8List(),
                frame.image.width,
                frame.image.height,
                region: region,
              );
              surfaceSamples.add({
                'counter': actual,
                'elapsedMs': surfaceWatch.elapsedMilliseconds,
              });
              evidence['presentedCounter'] = actual;
              if (actual == expected) break;
            } finally {
              frame.image.dispose();
              imageCodec.dispose();
            }
            if (surfaceWatch.elapsed > const Duration(milliseconds: 1500)) {
              break;
            }
            await tester.pump();
          }
          expect(
            evidence['presentedCounter'],
            expected,
            reason: 'The actual Flutter surface must show the newest target pattern within the bounded verification.',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await real(() async {
            final stopped = await outputs.stop(session!);
            evidence['stop'] = stopped;
            for (final output
                in (stopped['outputs'] as List)
                    .whereType<Map<Object?, Object?>>()) {
              expect(output['textureDetached'], true);
              expect(output['cleanupUnconfirmed'], isNot(true));
              expect(output['disposeDeferred'], isNot(true));
            }
            await request('session.stop', {'sessionId': session});
            session = null;
            if (!keepConnection) {
              await request('devices.disconnect', {'deviceId': device});
            }
          });
        }
        if (traceFrames) binding.reportData!['frameCorrelationComplete'] = true;
        final timings = [
          for (final round in rounds)
            ...(round['inputToDecodedMs'] as List<int>),
        ]..sort();
        final p95 = timings[(timings.length * .95).ceil() - 1];
        final p50 = timings[(timings.length * .50).ceil() - 1];
        binding.reportData!['inputToDecodedP50Ms'] = p50;
        binding.reportData!['inputToDecodedP95Ms'] = p95;
        expect(
          p50,
          lessThanOrEqualTo(
            const int.fromEnvironment(
              'CONNECT_PERF_MAX_P50_MS',
              defaultValue: 3000,
            ),
          ),
          reason: 'Typical new decoded pixels must meet the requested latency budget.',
        );
        expect(
          p95,
          lessThanOrEqualTo(
            const int.fromEnvironment(
              'CONNECT_PERF_MAX_P95_MS',
              defaultValue: 3000,
            ),
          ),
          reason: 'Actual new decoded pixels must meet the requested latency budget.',
        );
        binding.reportData!['videoPerformanceComplete'] = true;
      } finally {
        await tester.runAsync(() async {
          await outputs.dispose();
          disposed = true;
          if (session != null) {
            await request('session.stop', {'sessionId': session});
          }
          if (device != null) {
            await request('devices.disconnect', {'deviceId': device});
          }
        });
      }
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
