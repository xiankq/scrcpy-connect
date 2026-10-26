import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/services/connection/connection_validation.dart';

import 'product_flow_test.dart' show waitFor;

// 配合 test/driver/integration_test.dart 和 CONNECT_E2E_ACCEPTANCE=media 运行。失败及关闭竞争由 device_quality_coordinator_test.dart、video_output_coordinator_test.dart 和 quality_reconfiguration_android.rs 覆盖；本测试提供真实 Flutter/MDK 双输出证据，不模拟渲染器、伪造就绪回执或逐窗口修改画质。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  binding.reportData = {'mediaAcceptanceComplete': false};
  testWidgets(
    'device quality rebuilds both real local outputs and future windows',
    (tester) async {
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
      await app.main();
      await waitFor(
        tester,
        () => find.byType(ConnectApp).evaluate().isNotEmpty,
        reason: 'Initialize the production app.',
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      await waitFor(
        tester,
        () =>
            !controller.snapshot().loading &&
            !controller.snapshot().reconciliationPending,
        reason: 'Finish real bridge reconciliation.',
      );
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 90));
      final originalSettings = await request('settings.get');
      final initialDevices = objects(
        (await request('devices.list'))['devices'],
      );
      final originalFocus = controller.snapshot().focusedDeviceId;
      final owned = <String>{};
      final events = <Json>[];
      final subscription = controller.eventStream().listen(events.add);
      final display = ValueNotifier<List<Json>>([]);
      OverlayEntry? overlay;
      String? deviceId;
      var created = false, initiallyConnected = false, qualityChanged = false;
      var converted = false;
      final evidence = <String, dynamic>{};
      binding.reportData!['deviceQuality'] = evidence;
      String idOf(Json record) =>
          value(record, 'sessionId', value(record, 'id'));
      Future<List<Json>> sessions() async => objects(
        (await request('session.list', {'deviceId': deviceId}))['sessions'],
      );
      bool verified(Json record) =>
          ['streaming', 'paused'].contains(record['status']) &&
          record['backend'] == 'media_codec' &&
          record['firstFrameDecoded'] == true &&
          record['evidence'] == 'media_codec.snapshot' &&
          record['qualityRebuilding'] != true &&
          record['outputRetained'] != true &&
          record['textureId'] is int &&
          (record['textureId'] as int) >= 0 &&
          (record['decodedWidth'] as num? ?? 0) > 0 &&
          (record['decodedHeight'] as num? ?? 0) > 0 &&
          record['captureGeneration'] is int &&
          record['outputCaptureGeneration'] == record['captureGeneration'] &&
          record['outputGeneration'] == record['rendererGeneration'];
      bool hasOutputEvent(Json record, int after) =>
          events.skip(after).any((event) {
            final output = jsonObject(event['data']);
            return const [
                  'session.output.ready',
                  'session.output.changed',
                ].contains(event['type']) &&
                event['deviceId'] == deviceId &&
                output['sessionId'] == idOf(record) &&
                output['captureGeneration'] == record['captureGeneration'] &&
                output['generation'] == record['rendererGeneration'] &&
                output['textureId'] == record['textureId'] &&
                output['firstFrameDecoded'] == true &&
                output['evidence'] == 'media_codec.snapshot';
          });
      Future<List<Json>> ready(Set<String> ids, {int after = 0}) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        do {
          final records = (await sessions())
              .where((item) => ids.contains(idOf(item)))
              .toList();
          if (records.length == ids.length &&
              records.every(
                (record) => verified(record) && hasOutputEvent(record, after),
              )) {
            return records;
          }
          await tester.pump(const Duration(milliseconds: 200));
        } while (DateTime.now().isBefore(deadline));
        fail('Real MDK outputs did not verify: ${await sessions()}');
      }

      Json receipt(Json record) => {
        for (final key in const [
          'sessionId',
          'status',
          'deviceId',
          'packageName',
          'taskId',
          'displayId',
          'displayDensity',
          'quality',
          'captureGeneration',
          'rendererGeneration',
          'outputCaptureGeneration',
          'outputGeneration',
          'textureId',
          'decodedWidth',
          'decodedHeight',
          'backend',
          'firstFrameDecoded',
          'evidence',
          'qualityRebuilding',
          'keepActive',
        ])
          key: record[key],
      };
      void assertQuality(Json record, int size, int fps, int bitRate) {
        final quality = jsonObject(record['quality']);
        expect(quality['maxSize'], size);
        expect(quality['maxFps'], fps);
        expect(quality['videoBitRate'], bitRate);
        expect(quality['videoCodec'], 'h264');
        expect(quality['preset'], size == 720 ? 'smooth' : 'balanced');
        expect(quality['videoEncoder'], isNull);
        expect(record['keepActive'], true);
        expect(
          (record['decodedWidth'] as int).clamp(0, size),
          record['decodedWidth'],
        );
        expect(
          (record['decodedHeight'] as int).clamp(0, size),
          record['decodedHeight'],
        );
      }

      Future<Json> open([String? package]) async {
        try {
          final result = await request('session.start', {
            'deviceId': deviceId,
            'packageName': ?package,
            'keepActive': true,
          });
          final id = idOf(result);
          expect(id, isNotEmpty);
          owned.add(id);
          return (await ready({id})).single;
        } on RequestFailure catch (error) {
          final detail = jsonObject(error.details);
          if (detail['deviceId'] == deviceId && idOf(detail).isNotEmpty) {
            owned.add(idOf(detail));
          }
          rethrow;
        }
      }

      Future<Json> settingsTask() async {
        final current = await request('apps.list', {
          'deviceId': deviceId,
          'filter': 'running',
        });
        expect(current['live'], true);
        expect(current['source'], 'runningTasks');
        return objects(
          current['apps'],
        ).singleWhere((item) => item['packageName'] == 'com.android.settings');
      }

      Future<void> capture(String name, List<Json> records) async {
        display.value = records;
        await tester.pump(const Duration(milliseconds: 300));
        final textures = find.byWidgetPredicate(
          (widget) =>
              widget is Texture &&
              records.any((record) => record['textureId'] == widget.textureId),
        );
        expect(textures, findsNWidgets(records.length));
        for (final record in records) {
          final snapshot = await request('session.screenshot', {
            'sessionId': idOf(record),
          });
          expect(snapshot['evidence'], 'media_codec.snapshot');
          expect(snapshot['generation'], record['rendererGeneration']);
          final file = File(value(snapshot, 'localPath'));
          try {
            final codec = await ui.instantiateImageCodec(
              await file.readAsBytes(),
              targetWidth: 32,
              targetHeight: 32,
            );
            try {
              final frame = await codec.getNextFrame();
              try {
                final pixels = await frame.image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                );
                expect(pixels, isNotNull);
                final colors = <int>{
                  for (
                    var offset = 0;
                    offset < pixels!.lengthInBytes;
                    offset += 4
                  )
                    pixels.getUint32(offset),
                };
                expect(
                  colors.length,
                  greaterThan(1),
                  reason: 'Reject a blank decoded texture.',
                );
              } finally {
                frame.image.dispose();
              }
            } finally {
              codec.dispose();
            }
          } finally {
            // 仅拥有本次截图新建的捕获目录。
            await file.delete();
            await file.parent.delete();
          }
        }
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
        }
        await tester.pump(const Duration(milliseconds: 250));
        await binding.takeScreenshot(name);
      }

      try {
        deviceId = responseDeviceId(
          await request('devices.add', {
            'address': address,
            'port': port,
            'attemptId':
                'device-quality-${DateTime.now().microsecondsSinceEpoch}',
          }),
        );
        created = !initialDevices.any((item) => item['id'] == deviceId);
        initiallyConnected = initialDevices.any(
          (item) => item['id'] == deviceId && item['status'] == 'connected',
        );
        await request('devices.connect', {'deviceId': deviceId});
        expect(
          await sessions(),
          isEmpty,
          reason: 'Use an isolated target; do not rebuild another owner’s sessions.',
        );
        await controller.focusDevice(deviceId);
        final initialScreen = await request('device.screen.state', {
          'deviceId': deviceId,
        });
        expect(
          initialScreen['screenOn'],
          true,
          reason: 'Prepare an awake target externally.',
        );
        expect(
          initialScreen['locked'],
          false,
          reason: 'Use an already unlocked target.',
        );
        qualityChanged = true;
        await request('session.quality', {
          'deviceId': deviceId,
          'preset': 'smooth',
          'videoCodec': 'h264',
          'videoEncoder': null,
        });
        final phone = await open();
        final application = await open('com.android.settings');
        expect(application['taskId'], isA<int>());
        expect((await settingsTask())['taskId'], application['taskId']);
        final before = await ready({idOf(phone), idOf(application)});
        for (final record in before) {
          assertQuality(record, 720, 30, 2000000);
        }
        // 覆盖层仅显示真实生产所有者创建的 MDK 纹理 ID；原 ConnectApp 与 provider 全程保持挂载。
        overlay = OverlayEntry(
          builder: (context) => Positioned.fill(
            child: Material(
              color: Colors.black,
              child: SafeArea(
                child: ValueListenableBuilder<List<Json>>(
                  valueListenable: display,
                  builder: (context, records, _) => Row(
                    children: [
                      for (final record in records)
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio:
                                  (record['decodedWidth'] as num) /
                                  (record['decodedHeight'] as num),
                              child: Texture(
                                key: ValueKey('quality-${idOf(record)}'),
                                textureId: record['textureId'] as int,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        Overlay.of(tester.element(find.byType(Scaffold).first)).insert(overlay);
        evidence['before'] = before.map(receipt).toList();
        await capture('device-quality-two-outputs-before', before);
        // 被遮挡但仍打开的窗口也应收到设备级设置，验证真实暂停的 MDK 输出与播放中的应用输出。
        await request('session.pause', {'sessionId': idOf(phone)});
        final paused = (await sessions()).singleWhere(
          (record) => idOf(record) == idOf(phone),
        );
        expect(paused['status'], 'paused');
        evidence['pausedBeforeRebuild'] = receipt(paused);
        final eventWatermark = events.length;
        final screenBefore = await request('device.screen.state', {
          'deviceId': deviceId,
        });
        final changed = await request('session.quality', {
          'deviceId': deviceId,
          'preset': 'balanced',
        });
        expect(changed['saved'], true);
        expect(changed['appliedToAll'], true, reason: '${changed['failures']}');
        expect(changed['failures'], isEmpty);
        expect(changed['skippedSessions'], isEmpty);
        expect(objects(changed['appliedSessions']).map(idOf).toSet(), owned);
        final after = await ready(owned, after: eventWatermark);
        for (final record in after) {
          final previous = before.singleWhere(
            (old) => idOf(old) == idOf(record),
          );
          assertQuality(record, 1280, 60, 8000000);
          expect(
            record['status'],
            idOf(record) == idOf(phone) ? 'paused' : 'streaming',
            reason: 'Rebuilding quality preserves each open presentation.',
          );
          expect(record['taskId'], previous['taskId']);
          expect(
            record['captureGeneration'],
            greaterThan(previous['captureGeneration'] as int),
          );
          expect(
            record['rendererGeneration'],
            greaterThan(previous['rendererGeneration'] as int),
          );
        }
        expect((await sessions()).map(idOf).toSet(), owned);
        expect((await settingsTask())['taskId'], application['taskId']);
        final screenAfter = await request('device.screen.state', {
          'deviceId': deviceId,
        });
        expect(screenAfter['screenOn'], screenBefore['screenOn']);
        expect(screenAfter['locked'], screenBefore['locked']);
        final qualityEvents = events
            .skip(eventWatermark)
            .where(
              (event) =>
                  owned.contains(value(jsonObject(event['data']), 'sessionId')),
            )
            .toList();
        expect(
          qualityEvents.where(
            (event) =>
                [
                  'session.stop.requested',
                  'session.failed',
                  'session.stopped',
                ].contains(event['type']) ||
                [
                  'stopped',
                  'stopping',
                  'failed',
                ].contains(jsonObject(event['data'])['status']),
          ),
          isEmpty,
        );
        for (final id in owned) {
          expect(
            qualityEvents.any(
              (event) =>
                  event['type'] == 'session.updated' &&
                  jsonObject(event['data'])['sessionId'] == id &&
                  jsonObject(event['data'])['qualityRebuilding'] == true,
            ),
            true,
          );
        }
        evidence.addAll({
          'after': after.map(receipt).toList(),
          'screenBefore': screenBefore,
          'screenAfter': screenAfter,
          'lifecycleEvidence': 'Stable session/task IDs, no terminal session events, unchanged observed screen state; no wake-command counter is exposed.',
          'regressionReferences': [
            'app/test/media/device_quality_coordinator_test.dart: reports actual partial failures and continues remaining windows',
            'app/test/media/video_output_coordinator_test.dart: close beats a late one-use replacement relay',
            'app/rust/core/tests/quality_reconfiguration_android.rs: explicit_close_during_rebuild_does_not_resurrect_window',
          ],
        });
        await capture('device-quality-two-outputs-after', after);
        await request('session.resume', {'sessionId': idOf(phone)});
        expect(
          (await sessions()).singleWhere(
            (record) => idOf(record) == idOf(phone),
          )['status'],
          'streaming',
        );
        final saved = jsonObject(
          jsonObject(
            (await request('settings.get'))['deviceQuality'],
          )[deviceId],
        );
        expect(saved['qualityPreset'], 'balanced');
        // 仅关闭本测试原手机窗口，再打开全新窗口；两次打开都不直接传入逐窗口视频参数。
        await request('session.stop', {
          'sessionId': idOf(phone),
          'keepTask': true,
        });
        owned.remove(idOf(phone));
        display.value = after
            .where((record) => idOf(record) != idOf(phone))
            .toList();
        final future = await open();
        expect(idOf(future), isNot(idOf(phone)));
        assertQuality(future, 1280, 60, 8000000);
        expect(jsonObject(future['quality'])['preset'], 'balanced');
        evidence['future'] = receipt(future);
        await capture('device-quality-future-window', await ready(owned));
        expect(tester.takeException(), isNull);
      } finally {
        final cleanupErrors = <String>[];
        Future<void> clean(String name, Future<void> Function() action) async {
          try {
            await action();
          } catch (error) {
            cleanupErrors.add('$name: $error');
          }
        }

        overlay?.remove();
        overlay?.dispose();
        await tester.pump();
        await clean('event subscription', subscription.cancel);
        display.dispose();
        for (final id in owned) {
          await clean('session:$id', () async {
            await request('session.stop', {'sessionId': id, 'keepTask': true});
          });
        }
        if (deviceId != null) {
          await clean('session cleanup verification', () async {
            expect(
              (await sessions()).where(
                (record) => owned.contains(idOf(record)),
              ),
              isEmpty,
            );
          });
          if (qualityChanged) {
            await clean('device quality', () async {
              final latest = await request('settings.get');
              final overrides = jsonObject(latest['deviceQuality']);
              final originals = jsonObject(originalSettings['deviceQuality']);
              if (originals.containsKey(deviceId)) {
                overrides[deviceId!] = originals[deviceId];
              } else {
                overrides.remove(deviceId);
              }
              await controller.updateSetting('deviceQuality', overrides);
            });
          }
          if (created || !initiallyConnected) {
            await clean('device connection', () async {
              expect(
                await sessions(),
                isEmpty,
                reason:
                    'Never disconnect or forget another owner’s new session.',
              );
              await request(created ? 'devices.forget' : 'devices.disconnect', {
                'deviceId': deviceId,
              });
            });
          }
        }
        await clean('focus', () => controller.focusDevice(originalFocus));
        evidence['cleanupErrors'] = cleanupErrors;
        expect(cleanupErrors, isEmpty);
      }
      binding.reportData!['deviceQualityComplete'] = true;
      binding.reportData!['mediaAcceptanceComplete'] = true;
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
