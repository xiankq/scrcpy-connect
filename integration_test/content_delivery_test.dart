import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/file_details/file_details_page.dart';
import 'package:scrcpy_connect/pages/gallery/gallery_page.dart';
import 'package:scrcpy_connect/pages/media_preview/media_preview_page.dart';
import 'package:scrcpy_connect/pages/receive_content/receive_content_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/media_thumbnail.dart';
import 'package:video_player/video_player.dart';

import 'product_flow_test.dart' show waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  const kind = String.fromEnvironment(
    'CONNECT_E2E_CONTENT_KIND',
    defaultValue: 'text',
  );
  var stage = 'waiting-fixture';
  String? runId;
  String? hostError;
  List<int>? fixtureBytes;
  final acknowledgements = <String>{};
  binding.reportData = {'contentDeliveryComplete': false};
  developer.registerExtension('ext.connect.contentDelivery', (_, args) async {
    if (args['action'] == 'fixture' && runId == null) {
      final candidate = args['runId'];
      if (candidate != null &&
          RegExp(r'^[a-f0-9]{32}$').hasMatch(candidate) &&
          args['contentKind'] == kind &&
          args['fixtureBytes'] != null) {
        final bytes = base64Decode(args['fixtureBytes']!);
        if (bytes.isEmpty || bytes.length >= 2 * 1024 * 1024) {
          throw StateError(
            'Independent fixture is outside the receiver bound.',
          );
        }
        fixtureBytes = bytes;
        runId = candidate;
      }
    }
    if (runId != null && args['runId'] == runId) {
      if (args['error'] != null) {
        hostError = 'Independent Android check failed.';
      }
      if (args['action'] case final String action) acknowledgements.add(action);
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'stage': stage, 'runId': runId}),
    );
  });
  testWidgets('remote originals reach system storage and an external app', (
    tester,
  ) async {
    expect(address, isNotEmpty);
    expect(port, inInclusiveRange(1, 65535));
    expect(['text', 'image', 'video'], contains(kind));
    await app.main();
    await waitFor(
      tester,
      () => find.byType(Scaffold).evaluate().isNotEmpty,
      reason: 'Production app must initialize.',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConnectApp)),
    );
    final controller = container.read(appControllerProvider.notifier);
    await waitFor(
      tester,
      () =>
          !controller.snapshot().loading &&
          !controller.snapshot().reconciliationPending,
      reason: 'Production bootstrap must settle.',
    );
    Future<Json> request(String command, [Json params = const {}]) => controller
        .request(command, params)
        .timeout(const Duration(seconds: 45));
    Future<void> checkpoint(
      String next,
      String action, {
      bool cleanup = false,
    }) async {
      stage = next;
      final deadline = DateTime.now().add(const Duration(seconds: 75));
      // A system picker can suspend Flutter frame scheduling.
      while (!acknowledgements.contains(action) &&
          (cleanup || hostError == null) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        acknowledgements.contains(action),
        isTrue,
        reason: 'Independent host must acknowledge $next: $hostError',
      );
      if (!cleanup && hostError != null) throw StateError(hostError!);
    }

    await waitFor(
      tester,
      () => runId != null,
      reason: 'Host must prepare this isolated original.',
    );
    final extension = switch (kind) {
      'image' => 'jpg',
      'video' => 'mp4',
      _ => 'txt',
    };
    final root = switch (kind) {
      'image' => 'Pictures',
      'video' => 'Movies',
      _ => 'Download',
    };
    final name = 'connect-delivery-$runId.$extension';
    final path = '/sdcard/$root/$name';
    final expected = fixtureBytes!;
    binding.reportData!['fixtureRunId'] = runId;
    binding.reportData!['contentKind'] = kind;
    final initialDevices = objects((await request('devices.list'))['devices']);
    String? deviceId;
    var created = false;
    var connectedBefore = false;
    try {
      deviceId = responseDeviceId(
        await request('devices.add', {
          'address': address,
          'port': port,
          'transport': 'tcp',
          'attemptId': 'content-delivery-$runId',
        }),
      );
      created = !initialDevices.any((device) => device['id'] == deviceId);
      connectedBefore = initialDevices.any(
        (device) => device['id'] == deviceId && device['status'] == 'connected',
      );
      await request('devices.connect', {'deviceId': deviceId});
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      if (kind == 'text') {
        router.go(FileDetailsRoute(deviceId: deviceId!, path: path).location);
        await waitFor(
          tester,
          () => find.byType(FileDetailsPage).evaluate().isNotEmpty,
          reason: 'Actual route must re-read remote file metadata.',
        );
        await tester.tap(find.text('取回原文件'));
      } else {
        router.go(GalleryRoute(deviceId: deviceId!).location);
        final thumbnail = find.byWidgetPredicate(
          (widget) => widget is MediaThumbnail && widget.file['path'] == path,
        );
        await waitFor(
          tester,
          () =>
              find.byType(GalleryPage).evaluate().isNotEmpty &&
              thumbnail.evaluate().isNotEmpty,
          reason: 'Actual gallery must list this remote original.',
        );
        await tester.ensureVisible(thumbnail);
        bool hasDecodedImage(Finder scope) => find
            .descendant(of: scope, matching: find.byType(RawImage))
            .evaluate()
            .any((element) {
              final render = element.renderObject;
              return render is RenderImage &&
                  render.image != null &&
                  render.image!.width > 0 &&
                  render.image!.height > 0;
            });
        await waitFor(
          tester,
          () => hasDecodedImage(thumbnail),
          reason: 'Actual target thumbnail must decode visible pixels.',
        );
        binding.reportData!['galleryThumbnailLoaded'] = true;
        await tester.tap(thumbnail);
        await waitFor(
          tester,
          () => find.byType(MediaPreviewPage).evaluate().isNotEmpty,
          reason: 'Tapping the actual grid must open the same original.',
        );
        final preview = find.byType(MediaPreviewPage);
        if (kind == 'image') {
          await waitFor(
            tester,
            () => hasDecodedImage(preview),
            reason: 'The real full image must decode visible pixels.',
          );
        } else {
          await waitFor(
            tester,
            () =>
                find.byType(VideoPlayer).evaluate().isNotEmpty &&
                find.byTooltip('播放').evaluate().isNotEmpty,
            reason: 'Actual MP4 preview must initialize and offer play.',
          );
          final player = tester
              .widget<VideoPlayer>(find.byType(VideoPlayer))
              .controller;
          expect(
            player.value.duration,
            greaterThanOrEqualTo(const Duration(seconds: 5)),
          );
          await tester.tap(find.byTooltip('播放'));
          await waitFor(
            tester,
            () =>
                player.value.position > const Duration(milliseconds: 300) &&
                find.byTooltip('暂停').evaluate().isNotEmpty,
            reason: 'The real preview clock must advance after Play.',
          );
          await tester.tap(find.byTooltip('暂停'));
          await waitFor(
            tester,
            () => !player.value.isPlaying,
            reason: 'Pause must stop actual playback.',
          );
          final progress = find.byType(VideoProgressIndicator);
          final rect = tester.getRect(progress);
          await tester.tapAt(
            Offset(rect.left + rect.width * .6, rect.center.dy),
          );
          await waitFor(
            tester,
            () => player.value.position > const Duration(seconds: 2),
            reason: 'User scrubbing must seek the real video.',
          );
          await tester.tap(find.byTooltip('静音'));
          await waitFor(
            tester,
            () =>
                player.value.volume == 0 &&
                find.byTooltip('打开声音').evaluate().isNotEmpty,
            reason: 'Mute must change the actual preview player.',
          );
          binding.reportData!['videoPlaybackControls'] = true;
        }
        binding.reportData!['actualMediaPreview'] = true;
        await tester.pump(const Duration(milliseconds: 300));
        await checkpoint('media-preview-page', 'media-preview-captured');
        await tester.tap(find.byTooltip('保存原文件'));
      }
      await waitFor(
        tester,
        () => find.byType(ReceiveContentPage).evaluate().isNotEmpty,
        reason: 'A queued original must open its exact task.',
      );
      final task = tester
          .widget<ReceiveContentPage>(find.byType(ReceiveContentPage))
          .task;
      final transferId = value(task, 'id', value(task, 'transferId'));
      final downloadDeadline = DateTime.now().add(const Duration(seconds: 30));
      Json transfer = {};
      while (DateTime.now().isBefore(downloadDeadline)) {
        transfer = await request('transfers.get', {'transferId': transferId});
        if (transfer['canExport'] == true) break;
        if ([
          'failed',
          'cancelled',
          'interrupted',
          'conflict',
        ].contains(transfer['status'])) {
          throw StateError(
            'Original pull did not publish: ${transfer['status']} ${transfer['error']}',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        transfer['canExport'],
        true,
        reason: 'A complete original must publish safely.',
      );
      await waitFor(
        tester,
        () =>
            find.byType(ReceiveContentPage).evaluate().isNotEmpty &&
            find
                .widgetWithText(FilledButton, '选择系统位置并保存')
                .evaluate()
                .any(
                  (element) =>
                      (element.widget as FilledButton).onPressed != null,
                ),
        reason: 'Real queued pull must finish in its own save page.',
      );
      binding.reportData!['actualSavePage'] = true;
      final cache = File(value(transfer, 'localPath'));
      expect(await cache.readAsBytes(), expected);
      await tester.ensureVisible(find.text('选择系统位置并保存'));
      await tester.tap(find.text('选择系统位置并保存'));
      await checkpoint('cancel-picker', 'picker-cancelled');
      await waitFor(
        tester,
        () => find.text('本次系统保存已取消').evaluate().isNotEmpty,
        reason: 'Cancelling the system picker must not report saved.',
      );
      expect(await cache.readAsBytes(), expected);
      expect(find.text('已保存到系统位置'), findsNothing);
      binding.reportData!['pickerCancellationPreservedCache'] = true;
      await tester.ensureVisible(find.text('重新选择系统位置'));
      await tester.tap(find.text('重新选择系统位置'));
      await checkpoint('save-picker', 'saved');
      await waitFor(
        tester,
        () => find.text('已保存到系统位置').evaluate().isNotEmpty,
        reason: 'Real provider copy and close must confirm saved.',
      );
      expect(await cache.readAsBytes(), expected);
      binding.reportData!['exportedBytes'] = expected.length;
      await tester.pump(const Duration(milliseconds: 300));
      await checkpoint('saved-product-page', 'saved-product-captured');
      binding.reportData!['savedProductPageCaptured'] = true;
      router.pop();
      await waitFor(
        tester,
        () =>
            find.byType(ReceiveContentPage).evaluate().isEmpty &&
            find
                .byType(kind == 'text' ? FileDetailsPage : MediaPreviewPage)
                .evaluate()
                .isNotEmpty,
        reason: 'Return to the same original.',
      );
      ReceiveContentRoute(taskId: transferId)
          .push<void>(tester.element(find.byType(Scaffold).first));
      await waitFor(tester, () {
        final page = find.byType(ReceiveContentPage);
        if (page.evaluate().length != 1) return false;
        final route = ModalRoute.of(tester.element(page));
        return route?.isCurrent == true &&
            route?.animation?.status == AnimationStatus.completed &&
            find.text('已保存到系统位置').hitTestable().evaluate().isNotEmpty;
      }, reason: 'Reopening the same source must restore its durable receipt.');
      expect(find.text('选择系统位置并保存'), findsNothing);
      final restored = jsonObject(
        (await request('delivery.get', {
          'sourceId': 'transfer:$transferId',
          'localPath': cache.path,
          'kind': 'file',
        }))['record'],
      );
      expect(restored['status'], 'saved');
      expect(value(restored, 'operationId'), isNotEmpty);
      binding.reportData!['systemSaveReceiptRestored'] = true;
      await tester.pump(const Duration(milliseconds: 300));
      await checkpoint('restored-save-product-page', 'restored-save-captured');
      router.pop();
      await waitFor(
        tester,
        () =>
            find.byType(ReceiveContentPage).evaluate().isEmpty &&
            find
                .byType(kind == 'text' ? FileDetailsPage : MediaPreviewPage)
                .evaluate()
                .isNotEmpty,
        reason: 'Receipt review must return to its original content.',
      );
      final shareOriginal = kind == 'text'
          ? find.text('交给系统分享')
          : find.byTooltip('系统分享');
      await tester.ensureVisible(shareOriginal);
      await waitFor(
        tester,
        () {
          final route = ModalRoute.of(tester.element(shareOriginal));
          return route?.animation?.status == AnimationStatus.completed &&
              route?.secondaryAnimation?.status == AnimationStatus.dismissed &&
              shareOriginal.hitTestable().evaluate().isNotEmpty;
        },
        reason: 'The original page must be reachable after the receipt page closes.',
      );
      await tester.tap(shareOriginal.hitTestable());
      await waitFor(
        tester,
        () =>
            find.byType(ReceiveContentPage).evaluate().isNotEmpty &&
            find.text('原文件已准备好').evaluate().isNotEmpty,
        reason: 'A separate real pull must prepare the original for share.',
      );
      binding.reportData!['actualSharePage'] = true;
      await tester.pump(const Duration(milliseconds: 300));
      await checkpoint('share-product-page', 'share-product-captured');
      binding.reportData!['shareProductPageCaptured'] = true;
      final shareButton = find.widgetWithText(FilledButton, '交给系统分享');
      await tester.ensureVisible(shareButton);
      await tester.tap(shareButton);
      await checkpoint('share-picker', 'shared');
      await waitFor(
        tester,
        () => find.text('已交给系统选择的应用，请在接收应用核对。').evaluate().isNotEmpty,
        reason:
            'The actual share result must keep its bounded handoff meaning.',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await checkpoint('shared-product-page', 'shared-product-captured');
      binding.reportData!['sharedProductPageCaptured'] = true;
      // Host reads the actual receiving app's bytes before returning us.
      expect(tester.takeException(), isNull);
    } finally {
      try {
        await checkpoint('awaiting-cleanup', 'cleanup', cleanup: true);
        binding.reportData!['fixtureCleanupAcknowledged'] = true;
      } finally {
        if (deviceId != null && created) {
          await request('devices.forget', {'deviceId': deviceId});
        } else if (deviceId != null && !connectedBefore) {
          await request('devices.disconnect', {'deviceId': deviceId});
        }
      }
    }
    stage = 'complete';
    binding.reportData!['contentDeliveryComplete'] = true;
  }, timeout: const Timeout(Duration(minutes: 7)));
}
