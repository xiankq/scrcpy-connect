import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:integration_test/integration_test.dart';
import 'package:interop_bridge/src/media/fvp_video_player.dart';
import 'package:interop_bridge/src/media/portable_video.dart';
import 'package:interop_bridge/src/media/video_presentation.dart';
import 'package:interop_bridge/src/native_runtime.dart';
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
    'real decoded freshness, first frame, pause and repeated device connections',
    (tester) async {
      const traceFrames = bool.fromEnvironment('CONNECT_PERF_TRACE_FRAMES');
      const traceClock = bool.fromEnvironment('CONNECT_PERF_TRACE_CLOCK');
      const adbBurst = bool.fromEnvironment('CONNECT_PERF_ADB_BURST');
      expect(
        !traceClock || traceFrames,
        true,
        reason: 'Clock brackets require the existing native frame clock.',
      );
      final rounds = <VideoJson>[];
      binding.reportData = {
        'videoPerformanceComplete': false,
        if (traceFrames) 'frameCorrelationComplete': false,
        if (traceClock) 'clockBracketsRequested': true,
        'adbBurstRequested': adbBurst,
        'binding': 'IntegrationTestWidgetsFlutterBinding',
        'framePolicy': binding.framePolicy.name,
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
                if (traceFrames &&
                    (command == 'media.open' || command == 'session.start'))
                  'traceFrames': true,
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

      Future<List<VideoJson>> clockProbes(String sessionId) async => [
        for (var probe = 0; probe < 3; probe++)
          await request('session.clock.probe', {'sessionId': sessionId}),
      ];

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
      // Global SDK experiments belong to this isolated test process, not the
      // product's player factory or a per-session setting that could race other
      // players. Defaults preserve the plugin's existing global configuration.
      const gpuProfiler = int.fromEnvironment(
        'CONNECT_PERF_GPU_PROFILER',
        defaultValue: -1,
      );
      const renderBufferFrames = int.fromEnvironment(
        'CONNECT_PERF_RENDER_BUFFER_FRAMES',
      );
      expect(gpuProfiler, anyOf(-1, 0, 1));
      expect(renderBufferFrames, greaterThanOrEqualTo(0));
      if (gpuProfiler >= 0) {
        mdk.setGlobalOption('profiler.gpu', gpuProfiler);
      }
      if (renderBufferFrames > 0) {
        mdk.setGlobalOption('videoout.buffer_frames', renderBufferFrames);
      }
      binding.reportData!['gpuProfilerRequested'] = gpuProfiler;
      binding.reportData!['renderBufferFramesRequested'] = renderBufferFrames;
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
      var inputSequence = 0;
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
          await initializeNativeRuntime(
            dataDirectory: '${support.path}/video-performance',
          );
          // Persisted test state must not leak the previous comparison mode.
          await request('settings.update', {'adbBurstMode': adbBurst});
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
        const maxSize = int.fromEnvironment(
          'CONNECT_PERF_MAX_SIZE',
          defaultValue: 640,
        );
        const maxFps = int.fromEnvironment(
          'CONNECT_PERF_MAX_FPS',
          defaultValue: 30,
        );
        const bitRate = int.fromEnvironment(
          'CONNECT_PERF_BIT_RATE',
          defaultValue: 2000000,
        );
        const videoCodec = String.fromEnvironment(
          'CONNECT_PERF_CODEC',
          defaultValue: 'h264',
        );
        const videoEncoder = String.fromEnvironment('CONNECT_PERF_ENCODER');
        const snapshotStress = int.fromEnvironment(
          'CONNECT_PERF_SNAPSHOT_STRESS',
        );
        expect(roundCount, inInclusiveRange(1, 20));
        expect(transitions, inInclusiveRange(2, 100));
        expect(maxSize, inInclusiveRange(320, 4096));
        expect(maxFps, inInclusiveRange(1, 120));
        expect(bitRate, inInclusiveRange(500000, 50000000));
        expect(videoCodec, isIn(['h264', 'h265', 'av1', 'vp8', 'vp9']));
        binding.reportData!['requestedVideoCodec'] = videoCodec;
        binding.reportData!['requestedVideoEncoder'] = videoEncoder;
        expect(snapshotStress, inInclusiveRange(0, 10000));
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
              final connection = await request('devices.connect', {
                'deviceId': device,
              });
              evidence['adbBurstActive'] = connection['adbBurstActive'];
              expect(
                connection['adbBurstActive'],
                adbBurst,
                reason: 'The transport comparison requires the actual negotiated mode.',
              );
            } else {
              evidence['adbBurstActive'] = rounds.first['adbBurstActive'];
            }
            evidence['connectMs'] = connected.elapsedMilliseconds;
            evidence['connectionReused'] = keepConnection && round > 0;
            final watch = Stopwatch()..start();
            final stream = await request('session.start', {
              'deviceId': device,
              'videoCodec': videoCodec,
              if (videoEncoder.isNotEmpty) 'videoEncoder': videoEncoder,
              'maxSize': maxSize,
              'maxFps': maxFps,
              'bitRate': bitRate,
            });
            session = stream['sessionId'] as String;
            evidence['sessionId'] = session;
            evidence['quality'] = stream['quality'];
            evidence['coreStartMs'] = watch.elapsedMilliseconds;
            evidence['coreStartupTimingMs'] = stream['captureStartupTimingMs'];
            final startup = stream['captureStartupTimingMs'] as VideoJson;
            evidence['postKeyFrameMs'] =
                (startup['totalMs'] as int) -
                (startup['encodedKeyFrameMs'] as int);
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
            // Stop this milestone before optional diagnostic reads add work.
            evidence['startToDecodedMs'] = watch.elapsedMilliseconds;
            if (traceFrames) {
              // Bound the native observation clock against this startup watch.
              // Keep the first verification snapshot before the next readback
              // replaces it; decoded callbacks registered after prepare may
              // omit earlier frames, so these are first-observed callbacks.
              final beforeUs = watch.elapsedMicroseconds;
              final trace = (player as FvpVideoPlayer).frameTrace;
              final afterUs = watch.elapsedMicroseconds;
              evidence['startupFrameTrace'] = {
                'watchBeforeUs': beforeUs,
                'watchAfterUs': afterUs,
                'metrics': trace,
              };
            }
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
            evidence['decodedWidth'] = ready['decodedWidth'];
            evidence['decodedHeight'] = ready['decodedHeight'];
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
            // Isolate renderer readback from pause/resume and disposal. Await
            // every native completion: this deliberately never overlaps calls.
            if (snapshotStress > 0) {
              final watch = Stopwatch()..start();
              for (var index = 0; index < snapshotStress; index++) {
                final pixels = await player
                    .snapshot(width: 64, height: 64)
                    .timeout(const Duration(seconds: 3));
                expect(pixels, isNotNull);
                expect(pattern(pixels!.rgba, 64, 64), expected);
                if ((index + 1) % 100 == 0 || index + 1 == snapshotStress) {
                  final progress = {
                    'round': round,
                    'completed': index + 1,
                    'elapsedMs': watch.elapsedMilliseconds,
                  };
                  evidence['snapshotStress'] = progress;
                  // Preserve the last completed receipt even after SIGABRT.
                  debugPrint('VIDEO_SNAPSHOT_STRESS ${jsonEncode(progress)}');
                }
              }
            }
            if (traceClock) {
              evidence['clockBefore'] = await clockProbes(session!);
            }
            final before = await request('media.status', {
              'relayId': ready['relayId'],
            });
            final observation = Stopwatch()..start();
            for (var sample = 0; sample < transitions; sample++) {
              expected = (expected + 1) & 15;
              inputSequence++;
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
                'fixtureSequence': inputSequence,
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
                // The downstream reader may finish before the upstream
                // write_all future resumes and publishes its receipt. Wait
                // only for diagnostics, after the measured interval ends.
                final receiptWait = Stopwatch()..start();
                late List<VideoJson> rawFrames;
                do {
                  final transport = await request('session.list');
                  final capture = (transport['sessions'] as List)
                      .cast<VideoJson>()
                      .singleWhere((entry) => entry['sessionId'] == session);
                  rawFrames = (capture['transportTrace'] as List)
                      .cast<VideoJson>()
                      .where(
                        (frame) =>
                            frame['sourcePtsUs'] == forwarded['sourcePtsUs'],
                      )
                      .toList();
                  if (rawFrames.isNotEmpty ||
                      receiptWait.elapsed >= const Duration(seconds: 1)) {
                    break;
                  }
                  await Future<void>.delayed(const Duration(milliseconds: 2));
                } while (true);
                expect(rawFrames, hasLength(1));
                final raw = rawFrames.single;
                sampleEvidence['transportFrame'] = raw;
                // The first complete ADB WRTE is buffered before AdbStream
                // delivers its first byte; this is not total wire receive time.
                sampleEvidence['adbStreamReadUs'] =
                    (raw['readCompletedUs'] as int) -
                    (raw['firstByteUs'] as int);
                sampleEvidence['rawWriteUs'] =
                    (raw['writtenUs'] as int) - (raw['writeStartedUs'] as int);
                sampleEvidence['readToRelayUs'] =
                    (forwarded['muxStartedUs'] as int) -
                    (raw['readCompletedUs'] as int);
                // A socket reader may run before the writer resumes after
                // write_all. Preserve this signed overlap rather than clamp.
                sampleEvidence['rawWrittenToRelayUs'] =
                    (forwarded['muxStartedUs'] as int) -
                    (raw['writtenUs'] as int);
                expect(
                  sampleEvidence['readToRelayUs'] as int,
                  greaterThanOrEqualTo(0),
                );
                expect(
                  sampleEvidence['relayToDecodeUs'] as int,
                  greaterThanOrEqualTo(0),
                );
              }
              (evidence['samples'] as List<VideoJson>).add(sampleEvidence);
              debugPrint(
                'VIDEO_INPUT_SAMPLE ${jsonEncode({
                  'round': round,
                  for (final key in const ['fixtureSequence', 'counter', 'controlMs', 'totalMs', 'relayFrame', 'transportFrame', 'inputToRelayUs', 'relayToDecodeUs', 'decodeToSnapshotUs', 'adbStreamReadUs', 'rawWriteUs', 'readToRelayUs', 'rawWrittenToRelayUs']) key: sampleEvidence[key],
                })}',
              );
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
            if (traceClock) {
              evidence['clockAfter'] = await clockProbes(session!);
            }
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
            const pauseCycles = int.fromEnvironment(
              'CONNECT_PERF_PAUSE_CYCLES',
              defaultValue: 1,
            );
            expect(pauseCycles, inInclusiveRange(1, 50));
            final pauseSamples = <VideoJson>[];
            evidence['pauseSamples'] = pauseSamples;
            for (var cycle = 0; cycle < pauseCycles; cycle++) {
              final sample = <String, dynamic>{
                'cycle': cycle,
                'stage': 'pause',
              };
              pauseSamples.add(sample);
              final watch = Stopwatch()..start();
              late VideoJson paused;
              try {
                paused = await presentation.request('session.pause', {
                  'sessionId': session,
                });
              } catch (error) {
                sample['error'] = '$error';
                sample['failedAfterMs'] = watch.elapsedMilliseconds;
                try {
                  final sessions = await request('session.list');
                  final snapshot = (sessions['sessions'] as List)
                      .cast<VideoJson>()
                      .singleWhere((entry) => entry['sessionId'] == session);
                  sample['failureState'] = {
                    for (final key in const [
                      'status',
                      'capturePaused',
                      'presentationOnly',
                      'awaitingSession',
                    ])
                      key: snapshot[key],
                  };
                } catch (inspectionError) {
                  sample['failureStateError'] = '$inspectionError';
                }
                rethrow;
              }
              sample['pauseMs'] = watch.elapsedMilliseconds;
              expect(paused['capturePaused'], false);
              expect(paused['presentationOnly'], true);
              // Change the independent target while presentation is paused. A
              // resumed callback or an old snapshot cannot satisfy freshness.
              sample['stage'] = 'changeWhilePaused';
              expected = (expected + 1) & 15;
              inputSequence++;
              await request('session.key', {
                'sessionId': session,
                'keyCode': 20,
                'action': 'press',
              });
              sample['expectedCounter'] = expected;
              sample['fixtureSequence'] = inputSequence;
              sample['stage'] = 'resume';
              watch.reset();
              final resumed = await presentation.request('session.resume', {
                'sessionId': session,
              });
              sample['resumeMs'] = watch.elapsedMilliseconds;
              expect(resumed['firstFrameDecoded'], true);
              expect(resumed['capturePaused'], false);
              sample['stage'] = 'newPixels';
              while (true) {
                final pixels = await player
                    .snapshot(width: 64, height: 64)
                    .timeout(const Duration(seconds: 3));
                if (pixels != null &&
                    pattern(pixels.rgba, 64, 64) == expected) {
                  break;
                }
                if (watch.elapsed > const Duration(seconds: 3)) {
                  throw StateError(
                    'Resume retained old pixels: round=$round cycle=$cycle expected=$expected',
                  );
                }
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
              sample['resumeToFreshMs'] = watch.elapsedMilliseconds;
              sample['stage'] = 'complete';
              // Preserve completed cycles in the host log even if a native
              // decoder crash prevents the final JSON response from arriving.
              debugPrint(
                'VIDEO_PAUSE_SAMPLE ${jsonEncode({'round': round, ...sample})}',
              );
            }
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
        const maxStartMs = int.fromEnvironment(
          'CONNECT_PERF_MAX_START_MS',
          defaultValue: 5000,
        );
        const maxPostKeyFrameMs = int.fromEnvironment(
          'CONNECT_PERF_MAX_POST_KEYFRAME_MS',
          defaultValue: 5000,
        );
        const maxP50Ms = int.fromEnvironment(
          'CONNECT_PERF_MAX_P50_MS',
          defaultValue: 3000,
        );
        const maxP95Ms = int.fromEnvironment(
          'CONNECT_PERF_MAX_P95_MS',
          defaultValue: 3000,
        );
        // Preserve every independent verdict even if the first assertion fails.
        // The overall receipt still requires all budgets to pass.
        binding.reportData!.addAll({
          'budgetsMs': {
            'start': maxStartMs,
            'postKeyFrame': maxPostKeyFrameMs,
            'inputP50': maxP50Ms,
            'inputP95': maxP95Ms,
          },
          'startupBudgetMet': rounds.every(
            (round) => (round['startToDecodedMs'] as int) <= maxStartMs,
          ),
          'postKeyFrameBudgetMet': rounds.every(
            (round) => (round['postKeyFrameMs'] as int) <= maxPostKeyFrameMs,
          ),
          'inputLatencyBudgetMet': p50 <= maxP50Ms && p95 <= maxP95Ms,
        });
        for (final round in rounds) {
          expect(
            round['postKeyFrameMs'],
            lessThanOrEqualTo(maxPostKeyFrameMs),
            reason:
                'Post-keyframe startup work must meet its independent budget.',
          );
          expect(
            round['startToDecodedMs'],
            lessThanOrEqualTo(maxStartMs),
            reason: 'Every first decoded frame must meet the requested startup budget.',
          );
        }
        expect(
          p50,
          lessThanOrEqualTo(maxP50Ms),
          reason: 'Typical new decoded pixels must meet the requested latency budget.',
        );
        expect(
          p95,
          lessThanOrEqualTo(maxP95Ms),
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
