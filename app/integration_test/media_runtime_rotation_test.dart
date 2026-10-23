import 'dart:async';
import 'dart:ui' as ui;

import 'package:device_runtime/device_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Exercises decoded geometry through the production assembly, rather than
/// replacing the player or calling the raw Rust core around that assembly.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'assembled runtime tracks decoded rotation without replacing output',
    (tester) async {
      final evidence = <String, dynamic>{};
      binding.reportData = {'assembledRotation': evidence};
      DeviceRuntime? runtime;
      StreamSubscription<Map<String, dynamic>>? subscription;
      final events = <Map<String, dynamic>>[];
      String? device, session;
      var rotations = 0;
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

      Future<Map<String, dynamic>> currentSession() async {
        final snapshot = await runtime!.request('state.snapshot');
        return Map<String, dynamic>.from(
          (snapshot['sessions'] as List).singleWhere(
            (item) => item['sessionId'] == session,
          ) as Map,
        );
      }

      Future<Map<String, dynamic>> waitGeometry(bool landscape) async {
        final deadline = DateTime.now().add(const Duration(seconds: 12));
        Map<String, dynamic> current = {};
        while (DateTime.now().isBefore(deadline)) {
          current = await currentSession();
          final w = current['decodedWidth'] as num? ?? 0;
          final h = current['decodedHeight'] as num? ?? 0;
          final captureW = current['width'] as num? ?? 0;
          final captureH = current['height'] as num? ?? 0;
          if (w > 0 &&
              h > 0 &&
              (w > h) == landscape &&
              captureW > 0 &&
              captureH > 0 &&
              (w / h - captureW / captureH).abs() < .005) {
            return current;
          }
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
        throw StateError(
          'Decoded and capture geometry did not converge: $current',
        );
      }

      Future<int> render(Map<String, dynamic> receipt) async {
        final surface = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: AspectRatio(
                aspectRatio:
                    (receipt['decodedWidth'] as num) /
                    (receipt['decodedHeight'] as num),
                child: RepaintBoundary(
                  key: surface,
                  child: Texture(textureId: receipt['textureId'] as int),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final image =
            await (surface.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          final colors = <int>{};
          for (var i = 0; i < bytes.length; i += 4) {
            colors.add(bytes[i] << 16 | bytes[i + 1] << 8 | bytes[i + 2]);
          }
          expect(colors.length, greaterThan(32));
          return colors.length;
        } finally {
          image.dispose();
        }
      }

      try {
        runtime = await real(() async {
          final support = await getApplicationSupportDirectory();
          return DeviceRuntime.initialize(
            dataDirectory:
                const String.fromEnvironment('CONNECT_E2E_DATA_DIRECTORY')
                    .isEmpty
                ? '${support.path}/assembled-media-rotation'
                : const String.fromEnvironment('CONNECT_E2E_DATA_DIRECTORY'),
            connectionPolicy: const ConnectionPolicy(
              requestAuthorization: true,
              healthEnabled: false,
              reconnectEnabled: false,
            ),
          );
        });
        subscription = runtime!.events.listen(events.add);
        final initial = await real(() async {
          await runtime!.request('settings.update', {
            'backgroundKeepAlive': false,
          });
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
          });
          session = result['sessionId'] as String;
          expect(result['firstFrameDecoded'], true);
          expect(result['backend'], 'media_codec');
          // Keep a primary-screen session. packageName on session.start would
          // create an independent app display rather than rotate this screen.
          await runtime!.request('session.launch', {
            'sessionId': session,
            'packageName': 'com.android.settings',
          });
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          var foregroundReady = false;
          while (DateTime.now().isBefore(deadline)) {
            final foreground = await runtime!.request('apps.foreground', {
              'deviceId': device,
            });
            if (foreground['packageName'] == 'com.android.settings') {
              evidence['foreground'] = foreground;
              foregroundReady = true;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(foregroundReady, true, reason: 'Launcher may lock portrait');
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return currentSession();
        });
        evidence['initial'] = initial;
        evidence['initialTextureColors'] = await render(initial);
        final initiallyLandscape =
            (initial['decodedWidth'] as num) >
            (initial['decodedHeight'] as num);

        for (var index = 0; index < 2; index++) {
          final eventOffset = events.length;
          final changed = await real(() async {
            await runtime!.request('session.rotate', {'sessionId': session});
            rotations++;
            return waitGeometry(
              index == 0 ? !initiallyLandscape : initiallyLandscape,
            );
          });
          expect(changed['textureId'], initial['textureId']);
          expect(changed['rendererGeneration'], initial['rendererGeneration']);
          expect(changed['captureGeneration'], initial['captureGeneration']);
          expect(changed['status'], 'streaming');
          final metadata = events.skip(eventOffset).where((event) {
            final data = event['data'];
            return event['type'] == 'session.frame' &&
                data is Map &&
                data['sessionId'] == session &&
                data['metadataOnly'] == true &&
                data['decodedWidth'] == changed['decodedWidth'] &&
                data['decodedHeight'] == changed['decodedHeight'];
          }).toList();
          expect(metadata, isNotEmpty);
          final receipt = metadata.last['data'] as Map;
          expect(receipt['textureId'], initial['textureId']);
          expect(receipt['captureGeneration'], initial['captureGeneration']);
          expect(receipt['frameCount'], greaterThan(0));
          evidence['rotation$index'] = changed;
          evidence['rotation${index}TextureColors'] = await render(changed);
        }
        await real(() async {
          final count = events
              .where(
                (event) =>
                    event['type'] == 'session.frame' &&
                    (event['data'] as Map?)?['metadataOnly'] == true,
              )
              .length;
          await Future<void>.delayed(const Duration(milliseconds: 600));
          expect(
            events
                .where(
                  (event) =>
                      event['type'] == 'session.frame' &&
                      (event['data'] as Map?)?['metadataOnly'] == true,
                )
                .length,
            count,
            reason: 'Unchanged video frames must not reach Dart events',
          );
          expect(
            (await runtime!.request('session.pause', {
              'sessionId': session,
            }))['paused'],
            true,
          );
          expect(
            (await runtime!.request('session.resume', {
              'sessionId': session,
            }))['paused'],
            false,
          );
          expect(
            events.where((e) => e['type'] == 'session.output.changed'),
            isEmpty,
          );
          evidence['dimensionEvents'] = count;
          await runtime!.request('session.stop', {'sessionId': session});
          session = null;
          expect((await runtime!.request('session.list'))['sessions'], isEmpty);
        });
        expect(tester.takeException(), isNull);
        binding.reportData!['mediaAcceptanceComplete'] = true;
      } catch (error) {
        evidence['failure'] = '$error';
        evidence['geometryEvents'] = events
            .where(
              (event) => const {
                'session.updated',
                'session.frame',
                'session.output.changed',
              }.contains(event['type']),
            )
            .toList();
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await subscription?.cancel();
        await real(() async {
          if (runtime == null) return;
          try {
            if (session != null) {
              if (rotations.isOdd) {
                await runtime.request('session.rotate', {'sessionId': session});
              }
              await runtime!.request('session.stop', {'sessionId': session});
            }
            if (device != null) {
              await runtime!.request('devices.disconnect', {
                'deviceId': device,
              });
            }
          } finally {
            await runtime!.shutdown();
          }
        });
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
