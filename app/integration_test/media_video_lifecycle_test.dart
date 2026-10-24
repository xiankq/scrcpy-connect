import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/media/output/video_output_coordinator.dart';
import 'package:scrcpy_connect/media/output/video_player_port.dart';
import 'package:scrcpy_connect/media/output/video_presentation.dart';
import 'package:scrcpy_connect/media/quality/video_quality_policy.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart'
    show ApplicationCommandException;

import 'package:path_provider/path_provider.dart';

import 'support/media_owner_fixture.dart';

/// 真实设备可选目标；Texture 控件挂载前适配器必须已取得首批解码像素，这比早期直接 Player 探测更严格，不调用应用原生视频方法。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('portable video actual first frame and exact-session lifecycle', (
    tester,
  ) async {
    final report = <Map<String, dynamic>>[];
    binding.reportData = {'portableVideoLifecycle': report};
    final support = await getApplicationSupportDirectory();
    final temporary = await getTemporaryDirectory();
    await temporary.create(recursive: true);
    final events = <VideoJson>[];
    var disposed = false;
    MediaOwnerFixture? fixture;
    Future<VideoJson> request(String command, VideoJson params) async {
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

    final outputs = VideoOutputCoordinator(
      request: request,
      openSource: (stream, generation) =>
          fixture!.videoSource.openSource(stream, generation),
      emit: events.add,
      isDisposed: () => disposed,
    );
    final presentation = VideoPresentation(
      request: request,
      pauseOutput: outputs.pause,
      resumeOutput: outputs.resume,
    );
    var capturedSurface = false;
    String? device;
    String? activeSession;
    try {
      await tester.runAsync(() async {
        const address = String.fromEnvironment(
          'CONNECT_E2E_ADDRESS',
          defaultValue: '10.0.2.2',
        );
        final port = int.parse(
          const String.fromEnvironment(
            'CONNECT_E2E_PORT',
            defaultValue: '15556',
          ),
        );
        fixture = await MediaOwnerFixture.open(
          dataDirectory:
              const String.fromEnvironment('CONNECT_E2E_DATA_DIRECTORY').isEmpty
              ? '${support.path}/portable-video-lifecycle'
              : const String.fromEnvironment('CONNECT_E2E_DATA_DIRECTORY'),
          address: Uri(host: address, port: port).authority,
        );
        device = fixture!.deviceId;
      });
      for (final codec in const String.fromEnvironment(
        'CONNECT_MEDIA_CODECS',
        defaultValue: 'h264',
      ).split(',')) {
        VideoJson? ready;
        final evidence = <String, dynamic>{'codec': codec};
        report.add(evidence);
        try {
          await tester.runAsync(() async {
            final watch = Stopwatch()..start();
            final stream = await request('session.start', {
              ...defaultVideoQuality,
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
            // 此时没有 Texture 控件；超时表示挂载前就绪契约失败，不能伪造就绪回执。
            try {
              ready = await outputs.start(stream);
            } on ApplicationCommandException catch (error) {
              evidence['startupFailure'] = error.details;
              rethrow;
            }
            evidence['firstDecodedFrameMs'] = watch.elapsedMilliseconds;
            evidence['firstFrame'] = ready;
            expect(
              watch.elapsedMilliseconds,
              lessThan(
                const int.fromEnvironment(
                  'CONNECT_MEDIA_MAX_FIRST_FRAME_MS',
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
          final surfaceKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              home: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    aspectRatio:
                        (ready!['decodedWidth'] as int) /
                        (ready!['decodedHeight'] as int),
                    child: RepaintBoundary(
                      key: surfaceKey,
                      child: Texture(textureId: ready!['textureId'] as int),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          if (Platform.isAndroid && !capturedSurface) {
            await binding.convertFlutterSurfaceToImage();
            capturedSurface = true;
          }
          await tester.pump();
          const surfaceHoldMs = int.fromEnvironment(
            'CONNECT_MEDIA_SURFACE_HOLD_MS',
          );
          if (surfaceHoldMs > 0) {
            await tester.runAsync(
              () => Future<void>.delayed(Duration(milliseconds: surfaceHoldMs)),
            );
          }
          if (Platform.isAndroid || Platform.isIOS) {
            await binding.takeScreenshot('portable-$codec');
          }
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            final boundary =
                surfaceKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            try {
              final pixels = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              final rgba = pixels!.buffer.asUint8List();
              final colors = <int>{};
              for (var i = 0; i < rgba.length; i += 4) {
                colors.add(rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2]);
              }
              evidence['flutterComposedColors'] = colors.length;
              expect(
                colors.length,
                greaterThan(32),
                reason:
                    'The composed Flutter texture must contain Settings pixels',
              );
              evidence['flutterTextureReadbackVerified'] = true;
            } finally {
              image.dispose();
            }
          }
          await tester.runAsync(() async {
            VideoJson? resumed;
            if (!const bool.fromEnvironment('CONNECT_MEDIA_FIRST_FRAME_ONLY')) {
              const cycles = int.fromEnvironment(
                'CONNECT_MEDIA_PAUSE_CYCLES',
                defaultValue: 1,
              );
              expect(cycles, inInclusiveRange(1, 20));
              for (var cycle = 0; cycle < cycles; cycle++) {
                final VideoJson paused;
                try {
                  paused = await presentation.request('session.pause', {
                    'sessionId': activeSession,
                  });
                } on ApplicationCommandException catch (error) {
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
        try {
          await outputs.dispose();
          disposed = true;
        } finally {
          await fixture?.close();
        }
      });
    }
    expect(tester.takeException(), isNull);
    binding.reportData!['mediaAcceptanceComplete'] = true;
  }, timeout: const Timeout(Duration(minutes: 12)));
}
