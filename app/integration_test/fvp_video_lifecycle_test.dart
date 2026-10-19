import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:interop_bridge/src/media/portable_video.dart';
import 'package:interop_bridge/src/media/video_presentation.dart';
import 'package:interop_bridge/interop_bridge.dart' show InteropException;
import 'package:interop_bridge/src/rust/api.dart' as core;
import 'package:interop_bridge/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';

/// Real-device opt-in target. The adapter must obtain its first decoded pixels
/// BEFORE a Texture widget is mounted; this is deliberately stronger than the
/// earlier direct-Player probe. No application native video methods are called.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('portable video actual first frame and exact-session lifecycle', (
    tester,
  ) async {
    final report = <Map<String, dynamic>>[];
    binding.reportData = {'portableVideoLifecycle': report};
    final support = await getApplicationSupportDirectory();
    final temporary = await getTemporaryDirectory();
    final events = <VideoJson>[];
    var disposed = false;
    Future<VideoJson> request(String command, VideoJson params) async {
      final result = jsonDecode(
        await core.invoke(
          requestJson: jsonEncode({'command': command, 'params': params}),
        ),
      ) as Map<String, dynamic>;
      if (result['ok'] != true) {
        throw StateError('$command: ${result['error']}');
      }
      return result['data'] as VideoJson;
    }

    final outputs = PortableVideoOutputs(
      core: request,
      emit: events.add,
      isDisposed: () => disposed,
    );
    final presentation = VideoPresentation(
      core: request,
      pauseOutput: outputs.pause,
      resumeOutput: outputs.resume,
    );
    var capturedSurface = false;
    String? device;
    String? activeSession;
    await tester.runAsync(() async {
      await RustLib.init();
      await core.initialize(
        dataDirectory: '${support.path}/portable-video-lifecycle',
      );
    });
    try {
      await tester.runAsync(() async {
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
        device = (added['device'] as VideoJson)['id'] as String;
        await request('devices.connect', {'deviceId': device});
      });
      for (final codec in const String.fromEnvironment(
        'CONNECT_FVP_CODECS',
        defaultValue: 'h264',
      ).split(',')) {
        VideoJson? ready;
        final evidence = <String, dynamic>{'codec': codec};
        report.add(evidence);
        try {
          await tester.runAsync(() async {
            final watch = Stopwatch()..start();
            final stream = await request('session.start', {
              'deviceId': device,
              'videoCodec': codec,
              'maxSize': 640,
              'maxFps': 30,
              'bitRate': 2000000,
            });
            activeSession = stream['sessionId'] as String;
            evidence['coreStartMs'] = watch.elapsedMilliseconds;
            evidence['coreStartupTimingMs'] = stream['captureStartupTimingMs'];
            watch.reset();
            // No Texture widget exists at this point. A timeout is a failed
            // premount readiness contract, never a fabricated ready receipt.
            try {
              ready = await outputs.start(stream);
            } on InteropException catch (error) {
              evidence['startupFailure'] = error.details;
              rethrow;
            }
            evidence['firstDecodedFrameMs'] = watch.elapsedMilliseconds;
            evidence['firstFrame'] = ready;
            expect(
              watch.elapsedMilliseconds,
              lessThan(
                const int.fromEnvironment(
                  'CONNECT_FVP_MAX_FIRST_FRAME_MS',
                  defaultValue: 5000,
                ),
              ),
            );
            expect(ready!['firstFrameDecoded'], true);
            expect(ready!['presentedToWidget'], false);
            expect(ready!['snapshotReceipts'], 1);
            expect(ready!['textureId'], greaterThanOrEqualTo(0));
            expect(ready!['decodedWidth'], greaterThan(0));
            expect(ready!['decodedHeight'], greaterThan(0));
            try {
              await request('session.ready', {
                'sessionId': activeSession,
                'textureId': ready!['textureId'],
              });
            } catch (_) {
              evidence['relayAtReadyFailure'] =
                  await request('media.status', {'relayId': ready!['relayId']})
                    ..remove('endpoint');
              rethrow;
            }
          });
          if (ready == null) return;
          await tester.pumpWidget(
            MaterialApp(
              home: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    aspectRatio:
                        (ready!['decodedWidth'] as int) /
                        (ready!['decodedHeight'] as int),
                    child: Texture(textureId: ready!['textureId'] as int),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          if (!capturedSurface) {
            await binding.convertFlutterSurfaceToImage();
            capturedSurface = true;
          }
          await tester.pump();
          await binding.takeScreenshot('portable-$codec');
          await tester.runAsync(() async {
            VideoJson? resumed;
            if (!const bool.fromEnvironment('CONNECT_FVP_FIRST_FRAME_ONLY')) {
              const cycles = int.fromEnvironment(
                'CONNECT_FVP_PAUSE_CYCLES',
                defaultValue: 1,
              );
              expect(cycles, inInclusiveRange(1, 20));
              for (var cycle = 0; cycle < cycles; cycle++) {
                final VideoJson paused;
                try {
                  paused = await presentation.request('session.pause', {
                    'sessionId': activeSession,
                  });
                } on InteropException catch (error) {
                  evidence['pauseFailure'] = error.details;
                  rethrow;
                }
                expect(paused['paused'], true);
                expect(paused['applied'], true);
                expect(paused['capturePaused'], false);
                expect(paused['presentationOnly'], true);
                resumed = await presentation.request('session.resume', {
                  'sessionId': activeSession,
                });
                expect(resumed['capturePaused'], false);
                expect(resumed['paused'], false);
                expect(resumed['snapshotReceipts'], cycle + 2);
              }
              evidence['pauseResumeCycles'] = cycles;
            }
            final shot = await outputs.screenshot(
              activeSession!,
              directory: temporary.path,
            );
            final file = File(shot['localPath'] as String);
            final png = await file.readAsBytes();
            expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
            final decoder = await ui.instantiateImageCodec(png);
            try {
              final frame = await decoder.getNextFrame();
              expect(frame.image.width, shot['width']);
              expect(frame.image.height, shot['height']);
              final rgba = await frame.image.toByteData();
              expect(rgba, isNotNull);
              final bytes = rgba!.buffer.asUint8List();
              final colors = <int>{};
              for (var i = 0; i < bytes.length; i += 4) {
                colors.add(
                  (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2],
                );
              }
              evidence['sampleColors'] = colors.length;
              expect(
                colors.length,
                greaterThan(32),
                reason: 'The known Settings screen must contain real decoded content.',
              );
              frame.image.dispose();
            } finally {
              decoder.dispose();
            }
            evidence.addAll({
              'presentationExercised': resumed != null,
              'resumed': ?resumed,
              'screenshotBytes': png.length,
              'stop': await outputs.stop(activeSession!),
            });
            await file.parent.delete(recursive: true);
          });
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        } finally {
          await tester.runAsync(() async {
            if (activeSession case final id?) {
              await outputs.stop(id);
              await request('session.stop', {'sessionId': id});
              activeSession = null;
            }
          });
        }
      }
      expect(
        events.where((event) => event['type'] == 'session.frame'),
        isEmpty,
      );
      debugPrint('[portable-video-lifecycle] ${jsonEncode(report)}');
    } finally {
      await tester.runAsync(() async {
        await outputs.dispose();
        disposed = true;
        if (device != null) {
          await request('devices.disconnect', {'deviceId': device});
        }
      });
    }
    expect(tester.takeException(), isNull);
    binding.reportData!['mediaAcceptanceComplete'] = true;
  }, timeout: const Timeout(Duration(minutes: 12)));
}
