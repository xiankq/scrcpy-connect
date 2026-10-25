import 'package:scrcpy_connect/services/files/received_directory.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/settings/media_cache/settings_media_cache_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/preview/devices_workspace_gallery_preview_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/services/connection/connection_validation.dart';

import '../../tool/src/driver_cleanup.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.reportData = {'mediaCacheComplete': false};
  Json checkpoint = {};
  var acknowledged = false;
  String? hostError;
  developer.registerExtension('ext.connect.mediaCache', (_, args) async {
    if (args['token'] == checkpoint['token']) {
      if (args['action'] == 'verified') acknowledged = true;
      if (args['error'] != null) hostError = args['error'];
    }
    return developer.ServiceExtensionResponse.result(jsonEncode(checkpoint));
  });
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  testWidgets(
    'real remote image and prepared original remain protected through the cache page',
    (tester) async {
      await app.main();
      await waitFor(
        tester,
        () =>
            find.byType(ConnectApp).evaluate().isNotEmpty &&
            find.byType(Scaffold).evaluate().isNotEmpty,
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      await waitFor(
        tester,
        () =>
            !controller.snapshot().loading &&
            !controller.snapshot().reconciliationPending,
      );
      Future<Json> request(String command, [Json params = const {}]) async {
        try {
          return await controller
              .request(command, params)
              .timeout(const Duration(seconds: 45));
        } catch (error) {
          binding.reportData!.putIfAbsent(
            'firstRequestFailure',
            () => {'command': command, 'error': '$error'},
          );
          rethrow;
        }
      }

      final before = objects((await request('devices.list'))['devices']);
      final tag = 'connect-cache-${DateTime.now().microsecondsSinceEpoch}';
      final remote = '/sdcard/Download/$tag.png';
      final local = await (await getTemporaryDirectory()).createTemp(
        'cache-e2e-',
      );
      Directory? received;
      String? deviceId;
      String? transferLease;
      String? previewLease;
      var published = false;
      var created = false;
      var connectedBefore = false;
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      Future<Json> waitTransfer(String id) async {
        Json task = {};
        await waitFor(tester, () async {
          task = await request('transfers.get', {'transferId': id});
          if (['failed', 'cancelled', 'conflict'].contains(task['status'])) {
            fail('$task');
          }
          return task['status'] == 'completed';
        }, reason: 'Real ADB transfer must publish an actual file.');
        return task;
      }

      Future<void> verify(
        String phase,
        Map<String, String> present,
        List<String> absent,
        List<int> bytes,
      ) async {
        acknowledged = false;
        checkpoint = {
          'stage': phase,
          'token': '$tag-$phase',
          'present': present,
          'absent': absent,
          'remote': remote,
          'expectedBytes': base64Encode(bytes),
        };
        await waitFor(
          tester,
          () => acknowledged || hostError != null,
          reason: 'Independent host filesystem verification must complete.',
        );
        expect(hostError, isNull);
        expect(acknowledged, true);
      }

      Future<void> clearInPage() async {
        await waitFor(
          tester,
          () =>
              ModalRoute.of(tester.element(find.byType(MediaCachePage)))
                  ?.animation
                  ?.status ==
              AnimationStatus.completed,
          reason: 'Wait for the actual cache page transition before input.',
        );
        await tester.scrollUntilVisible(find.text('清理可回收暂存'), 250);
        await waitFor(
          tester,
          () => find.text('清理可回收暂存').hitTestable().evaluate().isNotEmpty,
        );
        await tester.tap(find.text('清理可回收暂存').hitTestable());
        await waitFor(
          tester,
          () => find.text('清理暂存').hitTestable().evaluate().isNotEmpty,
        );
        await tester.tap(find.text('清理暂存'));
        await waitFor(
          tester,
          () =>
              find.textContaining('已回收 ').evaluate().isNotEmpty ||
              find.textContaining('本次没有可回收').evaluate().isNotEmpty,
        );
      }

      await withDriverCleanup(
        () async {
          deviceId = responseDeviceId(
            await request('devices.add', {
              'address': address,
              'port': port,
              'transport': 'tcp',
              'attemptId': tag,
            }),
          );
          expect(deviceId, isNotNull);
          created = !before.any((device) => device['id'] == deviceId);
          connectedBefore = before.any(
            (device) =>
                device['id'] == deviceId && device['status'] == 'connected',
          );
          await request('devices.connect', {'deviceId': deviceId});
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(
            const Rect.fromLTWH(0, 0, 320, 320),
            Paint()..color = const Color(0xff7754c8),
          );
          canvas.drawCircle(
            const Offset(160, 160),
            100,
            Paint()..color = const Color(0xffe5be65),
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(320, 320);
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final bytes = png.buffer.asUint8List(
            png.offsetInBytes,
            png.lengthInBytes,
          );
          final source = await File('${local.path}/original.png')
              .writeAsBytes(bytes, flush: true);
          image.dispose();
          picture.dispose();
          final pushed = await request('files.push', {
            'deviceId': deviceId,
            'conflict': 'ask',
            'items': [
              {'source': source.path, 'destination': remote},
            ],
          });
          published = true;
          await waitTransfer(value(pushed, 'transferId'));
          final preview = await request('media.preview', {
            'deviceId': deviceId,
            'path': remote,
          });
          previewLease = value(preview, 'cacheLeaseId');
          final previewPath = value(preview, 'localPath');
          final destinationDirectory = await receivedDirectory();
          received = destinationDirectory;
          final pull = await request('files.pull', {
            'deviceId': deviceId,
            'path': remote,
            'destination': '${destinationDirectory.path}/$tag.png',
            'conflict': 'ask',
            'destinationScope': 'privateCache',
          });
          final transferId = value(pull, 'transferId');
          transferLease = value(
            await request('media.cache.acquire', {'transferId': transferId}),
            'leaseId',
          );
          final task = await waitTransfer(transferId);
          final originalPath = value(task, 'localPath');
          router.go(
            MediaPreviewRoute(deviceId: deviceId!, path: remote).location,
          );
          await waitFor(
            tester,
            () =>
                find.byType(MediaPreviewPage).evaluate().isNotEmpty &&
                find
                    .byType(RawImage)
                    .evaluate()
                    .any((e) => (e.widget as RawImage).image != null),
            reason: 'Real preview must decode its remote image.',
          );
          await binding.convertFlutterSurfaceToImage();
          await tester.pump(const Duration(milliseconds: 300));
          await binding.takeScreenshot('cache-real-preview');
          // 页面已拥有预览，仅释放诊断请求的租约。
          await request('media.cache.release', {'leaseId': previewLease});
          previewLease = null;
          // 令第二张公共缩略图可回收，以验证界面删除。
          final thumbnail = await request('media.thumbnail', {
            'deviceId': deviceId,
            'path': remote,
          });
          final thumbnailPath = value(thumbnail, 'localPath');
          await request('media.cache.release', {
            'leaseId': thumbnail['cacheLeaseId'],
          });
          unawaited(
            const MediaCacheRoute().push<void>(
              tester.element(find.byType(MediaPreviewPage)),
            ),
          );
          await waitFor(
            tester,
            () =>
                find.byType(MediaCachePage).evaluate().isNotEmpty &&
                find.text('受保护').evaluate().isNotEmpty,
          );
          await clearInPage();
          await verify(
            'protected',
            {'preview': previewPath, 'original': originalPath},
            [thumbnailPath],
            bytes,
          );
          await tester.pump(const Duration(milliseconds: 300));
          await binding.takeScreenshot('cache-protected-after-clear');
          binding.reportData!['actualProtectedClear'] = true;
          router.go(const DevicesRoute().location);
          await tester.pump(const Duration(milliseconds: 500));
          await request('media.cache.release', {'leaseId': transferLease});
          transferLease = null;
          const MediaCacheRoute().go(
            tester.element(find.byType(Scaffold).first),
          );
          await waitFor(
            tester,
            () =>
                find.byType(MediaCachePage).evaluate().isNotEmpty &&
                find.text('受保护').evaluate().isNotEmpty,
          );
          await clearInPage();
          await verify('evicted', {}, [
            previewPath,
            originalPath,
            thumbnailPath,
          ], bytes);
          final evicted = await request('transfers.get', {
            'transferId': transferId,
          });
          expect(evicted['cacheEvicted'], true);
          expect(evicted['canExport'], false);
          expect(evicted['localPath'], isNull);
          binding.reportData!['actualReleasedEviction'] = true;
          await binding.takeScreenshot('cache-released-after-clear');
          expect(tester.takeException(), isNull);
        },
        () => {
          'preview route': () async {
            checkpoint = {'stage': 'cleanup'};
            router.go(const DevicesRoute().location);
            await tester.pump(const Duration(milliseconds: 500));
          },
          for (final lease in [transferLease, previewLease].whereType<String>())
            'cache lease $lease': () async {
              await request('media.cache.release', {'leaseId': lease});
            },
          if (published && deviceId != null)
            'remote fixture': () async {
              await request('files.delete', {
                'deviceId': deviceId,
                'paths': [remote],
              });
            },
          'local fixture': () async {
            await local.delete(recursive: true);
          },
          'received fixture': () async {
            final owned = received;
            if (owned != null && await owned.exists()) {
              await owned.delete(recursive: true);
            }
          },
          'device connection': () async {
            if (created && deviceId != null) {
              await request('devices.forget', {'deviceId': deviceId});
            } else if (deviceId != null && !connectedBefore) {
              await request('devices.disconnect', {'deviceId': deviceId});
            }
          },
        },
      );
      binding.reportData!['fixtureRemoved'] = true;
      binding.reportData!['mediaCacheComplete'] = true;
      checkpoint = {'stage': 'done'};
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> waitFor(
  WidgetTester tester,
  FutureOr<bool> Function() ready, {
  String reason = 'The actual page must settle.',
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(deadline)) {
    if (await ready()) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail(reason);
}
