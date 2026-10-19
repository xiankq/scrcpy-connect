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
import 'package:scrcpy_connect/pages/devices/workspace/gallery/index/devices_workspace_gallery_index_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/media_thumbnail.dart';

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.reportData = {'galleryIndexComplete': false};
  Json hostFixture = {};
  var hostChecked = false;
  String? hostError;
  var stage = 'starting';
  developer.registerExtension('ext.connect.galleryIndex', (_, args) async {
    if (stage == 'verify-fixture' && args['token'] == hostFixture['token']) {
      if (args['action'] == 'verified') hostChecked = true;
      if (args['error'] != null) {
        hostError = 'Independent original verification failed.';
      }
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'stage': stage,
        if (stage == 'verify-fixture') ...hostFixture,
      }),
    );
  });
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  testWidgets(
    'actual shared-storage gallery, stable pages and explicit refresh',
    (tester) async {
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
      await app.main();
      await waitFor(
        tester,
        () =>
            find.byType(ConnectApp).evaluate().isNotEmpty &&
            find.byType(Scaffold).evaluate().isNotEmpty,
        reason: 'Production app must initialize.',
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      await waitFor(
        tester,
        () =>
            !controller.snapshot().loading &&
            !controller.snapshot().reconciliationPending,
        reason: 'Production bootstrap must settle.',
      );
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 45));
      final before = objects((await request('devices.list'))['devices']);
      final tag = 'connect-gallery-${DateTime.now().microsecondsSinceEpoch}';
      final roots = [
        '/sdcard/$tag',
        '/sdcard/Download/$tag',
        '/sdcard/Android/media/$tag',
      ];
      final loose = '/sdcard/$tag.png';
      final expected = <String>[
        loose,
        '${roots[0]}/custom.png',
        '${roots[2]}/app-media.png',
        for (var i = 0; i < 102; i++)
          '${roots[1]}/download-${i.toString().padLeft(3, '0')}.png',
      ];
      final local = await (await getTemporaryDirectory()).createTemp(
        'gallery-index-',
      );
      String? deviceId;
      var created = false;
      var connectedBefore = false;
      final createdRoots = <String>[];
      final scanIds = <String>[];
      var loosePublished = false;
      Future<Json> scan({int limit = 100}) async {
        final first = await request('media.list', {
          'deviceId': deviceId,
          'limit': limit,
        });
        final id = value(first, 'scanId');
        expect(id, isNotEmpty);
        scanIds.add(id);
        Json next = first;
        await _waitForAsync(
          tester,
          () async {
            next = await request('media.list', {
              'deviceId': deviceId,
              'scanId': id,
              'limit': limit,
            });
            return next['status'] != 'scanning';
          },
          timeout: const Duration(seconds: 40),
          reason: 'A bounded actual media scan must reach a terminal result.',
        );
        return next;
      }

      Future<void> waitTransfers(Json pushed) async {
        final ids = strings(pushed['transferIds']).toSet();
        expect(ids, isNotEmpty);
        await _waitForAsync(
          tester,
          () async {
            final tasks = objects(
              (await request('transfers.list'))['transfers'],
            ).where((task) => ids.contains(task['id'])).toList();
            expect(
              tasks.any(
                (task) => [
                  'failed',
                  'conflict',
                  'cancelled',
                  'interrupted',
                ].contains(task['status']),
              ),
              false,
            );
            return tasks.length == ids.length &&
                tasks.every((task) => task['status'] == 'completed');
          },
          timeout: const Duration(seconds: 60),
          reason: 'All actual original uploads must complete.',
        );
      }

      try {
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
        for (final root in roots) {
          await request('files.mkdir', {'deviceId': deviceId, 'path': root});
          createdRoots.add(root);
        }
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 256, 256),
          Paint()..color = const Color(0xffc46d56),
        );
        canvas.drawCircle(
          const Offset(128, 128),
          84,
          Paint()..color = const Color(0xffe5be65),
        );
        canvas.drawRect(
          const Rect.fromLTWH(68, 102, 120, 52),
          Paint()..color = const Color(0xff745db1),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(256, 256);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final source = await File('${local.path}/original.png').writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          flush: true,
        );
        image.dispose();
        picture.dispose();
        final pushed = await request('files.push', {
          'deviceId': deviceId,
          'conflict': 'ask',
          'items': [
            for (final path in expected)
              {'source': source.path, 'destination': path},
          ],
        });
        loosePublished = true;
        await waitTransfers(pushed);
        final first = await scan(limit: 40);
        expect(['completed', 'partial'], contains(first['status']));
        expect(first['scope'], isA<Map<Object?, Object?>>());
        final all = <Json>[...objects(first['items'])];
        Json page = first;
        while (page['nextOffset'] != null) {
          page = await request('media.list', {
            'deviceId': deviceId,
            'scanId': first['scanId'],
            'offset': page['nextOffset'],
            'limit': 40,
          });
          all.addAll(objects(page['items']));
        }
        final paths = all.map((file) => value(file, 'path')).toList();
        expect(paths.toSet().length, paths.length);
        expect(paths, containsAll(expected));
        expect(all.length, first['total']);
        for (var i = 1; i < all.length; i++) {
          final a = all[i - 1];
          final b = all[i];
          final modifiedA = a['modified'] as num;
          final modifiedB = b['modified'] as num;
          expect(
            modifiedA > modifiedB ||
                (modifiedA == modifiedB &&
                    value(a, 'path').compareTo(value(b, 'path')) < 0),
            true,
          );
        }
        binding.reportData!.addAll({
          'actualDynamicRoots': true,
          'actualStablePages': true,
          'fixturePaths': expected,
          'fixtureRoots': roots,
          'looseFixture': loose,
          'fixtureSize': await source.length(),
          'initialTotal': first['total'],
        });
        final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
        router.go(GalleryRoute(deviceId: deviceId!).location);
        final gallery = find.byType(GalleryPage);
        Future<int> waitForVisibleThumbnails() async {
          var count = 0;
          await waitFor(
            tester,
            () {
              final viewport =
                  Offset.zero &
                  (tester.view.physicalSize / tester.view.devicePixelRatio);
              final cells = find
                  .descendant(
                    of: gallery,
                    matching: find.byType(MediaThumbnail),
                  )
                  .evaluate()
                  .where((element) {
                    final area = tester
                        .getRect(find.byWidget(element.widget))
                        .intersect(viewport);
                    return area.width > 32 && area.height > 32;
                  })
                  .toList();
              count = cells.length;
              return count >= 6 &&
                  cells.every(
                    (element) => find
                        .descendant(
                          of: find.byWidget(element.widget),
                          matching: find.byType(RawImage),
                        )
                        .evaluate()
                        .any(
                          (image) => (image.widget as RawImage).image != null,
                        ),
                  );
            },
            timeout: const Duration(seconds: 60),
            reason: 'Every visible gallery cell must decode its actual remote thumbnail.',
          );
          return count;
        }

        await waitFor(
          tester,
          () =>
              gallery.evaluate().isNotEmpty &&
              find
                  .textContaining('已显示 100 / ${first['total']} 项')
                  .evaluate()
                  .isNotEmpty,
          timeout: const Duration(seconds: 45),
          reason: 'The actual gallery must present its first frozen page.',
        );
        binding.reportData!['firstVisibleThumbnails'] =
            await waitForVisibleThumbnails();
        binding.reportData!['actualVisibleThumbnailsDecoded'] = true;
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 300));
        hostFixture = {
          'token': tag,
          'fixturePaths': expected,
          'fixtureBytes': base64Encode(await source.readAsBytes()),
        };
        stage = 'verify-fixture';
        await waitFor(
          tester,
          () => hostChecked || hostError != null,
          timeout: const Duration(seconds: 45),
          reason: 'Host must independently verify the actual originals before cleanup.',
        );
        expect(hostError, isNull);
        expect(hostChecked, true);
        stage = 'verified';
        binding.reportData!['hostFixtureAcknowledged'] = true;
        await binding.takeScreenshot('gallery-shared-first-page');
        final more = find.widgetWithText(OutlinedButton, '加载更多');
        await tester.scrollUntilVisible(
          more,
          500,
          scrollable: find
              .descendant(of: gallery, matching: find.byType(Scrollable))
              .last,
          maxScrolls: 60,
        );
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(more);
        await waitFor(
          tester,
          () => more.evaluate().isEmpty,
          reason: 'The second actual page must finish loading.',
        );
        binding.reportData!['scrolledVisibleThumbnails'] =
            await waitForVisibleThumbnails();
        binding.reportData!['actualScrolledThumbnailsDecoded'] = true;
        await tester.pump(const Duration(milliseconds: 1200));
        await binding.takeScreenshot('gallery-scrolled-thumbnails');
        await tester.scrollUntilVisible(
          find.text('相册范围与未读项目'),
          -800,
          scrollable: find
              .descendant(of: gallery, matching: find.byType(Scrollable))
              .last,
          maxScrolls: 60,
        );
        final initialTotal = first['total'] as int;
        final loaded = initialTotal < 200 ? initialTotal : 200;
        await waitFor(
          tester,
          () => find
              .textContaining('已显示 $loaded / $initialTotal 项')
              .evaluate()
              .isNotEmpty,
          reason:
              'Load more must append the second page of the same actual scan.',
        );
        binding.reportData!['actualGalleryLoadMore'] = true;
        await tester.scrollUntilVisible(
          find.text('相册范围与未读项目'),
          -800,
          scrollable: find
              .descendant(of: gallery, matching: find.byType(Scrollable))
              .last,
          maxScrolls: 60,
        );
        await tester.tap(find.text('相册范围与未读项目'));
        await tester.pump(const Duration(milliseconds: 1200));
        expect(find.textContaining('文件修改时间不等于拍摄时间'), findsOneWidget);
        await binding.takeScreenshot('gallery-explicit-scope');
        await tester.tap(find.text('关闭范围'));
        await tester.pump(const Duration(milliseconds: 400));
        binding.reportData!['actualScopeVisible'] = true;
        final added = '${roots[0]}/after-refresh.png';
        await waitTransfers(
          await request('files.push', {
            'deviceId': deviceId,
            'conflict': 'ask',
            'items': [
              {'source': source.path, 'destination': added},
            ],
          }),
        );
        final oldAgain = await request('media.list', {
          'deviceId': deviceId,
          'scanId': first['scanId'],
          'limit': 40,
        });
        expect(oldAgain['total'], initialTotal);
        expect(
          objects(oldAgain['items']).any((file) => file['path'] == added),
          false,
        );
        await tester.tap(find.byTooltip('重新检查相册'));
        await waitFor(
          tester,
          () => find
              .textContaining('已显示 100 / ${initialTotal + 1} 项')
              .evaluate()
              .isNotEmpty,
          timeout: const Duration(seconds: 45),
          reason: 'Only an explicit refreshed scan must include the added original.',
        );
        final refreshed = await scan(limit: 200);
        expect(refreshed['total'], initialTotal + 1);
        expect(
          objects(refreshed['items']).any((file) => file['path'] == added),
          true,
        );
        binding.reportData!['actualRefreshSnapshotIsolation'] = true;
        expect(find.byType(MediaThumbnail), findsWidgets);
        expect(tester.takeException(), isNull);
      } finally {
        stage = 'cleanup';
        try {
          if (deviceId != null) {
            for (final id in scanIds) {
              await request('media.scan.cancel', {
                'deviceId': deviceId,
                'scanId': id,
              });
            }
            routerToDevices(tester);
            await tester.pump(const Duration(milliseconds: 400));
            final paths = [...createdRoots, if (loosePublished) loose];
            if (paths.isNotEmpty) {
              await request('files.delete', {
                'deviceId': deviceId,
                'paths': paths,
              });
            }
            for (final root in createdRoots) {
              final parent = root.substring(0, root.lastIndexOf('/'));
              final listed = await request('files.list', {
                'deviceId': deviceId,
                'path': parent,
              });
              expect(
                objects(listed['entries'])
                    .any((entry) => entry['path'] == root),
                false,
              );
            }
            final rootListing = await request('files.list', {
              'deviceId': deviceId,
              'path': '/sdcard',
            });
            expect(
              objects(rootListing['entries'])
                  .any((entry) => entry['path'] == loose),
              false,
            );
            binding.reportData!['fixtureRemoved'] = true;
          }
        } finally {
          await local.delete(recursive: true);
          if (deviceId != null && created) {
            await request('devices.forget', {'deviceId': deviceId});
          } else if (deviceId != null && !connectedBefore) {
            await request('devices.disconnect', {'deviceId': deviceId});
          }
        }
      }
      binding.reportData!['galleryIndexComplete'] = true;
      stage = 'done';
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}

void routerToDevices(WidgetTester tester) {
  final context = find.byType(Scaffold).evaluate().first;
  const DevicesRoute().go(context);
}

Future<void> _waitForAsync(
  WidgetTester tester,
  Future<bool> Function() ready, {
  required Duration timeout,
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await ready()) return;
    await tester.pump(const Duration(milliseconds: 150));
  }
  fail(reason);
}
