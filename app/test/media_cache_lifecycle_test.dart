import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/app_store.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/preview/devices_workspace_gallery_preview_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/receive/transfers_details_receive_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/index/transfers_details_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/media_thumbnail.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

const _task = {
  'id': 'prepare-share',
  'deviceId': 'phone',
  'direction': 'pull',
  'destinationScope': 'privateCache',
  'name': 'original.jpg',
  'kind': 'file',
  'status': 'running',
};

Future<void> _mount(WidgetTester tester, AppStore controller, Widget page) =>
    tester.pumpWidget(RouterTestApp(controller: controller, home: page));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final receive in [true, false]) {
    testWidgets(
      'a ${receive ? 'receive' : 'details'} status page releases its preparation lease after interruption',
      (tester) async {
        var status = 'running';
        final released = <String>[];
        final events = StreamController<Json>.broadcast(sync: true);
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          if (command == 'transfers.get') return {..._task, 'status': status};
          if (command == 'media.cache.acquire') {
            return {'leaseId': 'preparation-lease'};
          }
          if (command == 'media.cache.release') {
            released.add(params['leaseId'] as String);
          }
          return {};
        }, events: events.stream);
        await _mount(
          tester,
          controller,
          receive
              ? ReceiveContentPage(controller: controller, task: _task)
              : TransferDetailsPage(controller: controller, task: _task),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(released, isEmpty);
        status = 'interrupted';
        events.add({'type': 'transfers.changed', 'transferId': _task['id']});
        await tester.pumpAndSettle();
        expect(
          released,
          ['preparation-lease'],
          reason: 'A status-only page must not block explicit restart with its own lease.',
        );
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      },
    );
  }

  for (final sharingFails in [false, true]) {
    testWidgets(
      'preparing and sharing continues once after verified completion, sharingFails=$sharingFails',
      (tester) async {
        const channel = MethodChannel('dev.fluttercommunity.plus/share');
        final shares = <MethodCall>[];
        var shareResponse = Completer<String>();
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          shares.add(call);
          return shareResponse.future;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final events = StreamController<Json>.broadcast(sync: true);
        final retained = Completer<Json>();
        final commands = <String>[];
        var status = 'running';
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          commands.add(command);
          if (command == 'transfers.get') {
            return {
              ..._task,
              'status': status,
              'canExport': status == 'completed',
              'localPath': '/private/original.jpg',
            };
          }
          if (command == 'media.cache.acquire') {
            return {'leaseId': 'share-read-lease'};
          }
          if (command == 'media.cache.retain') return retained.future;
          return {};
        }, events: events.stream);
        await _mount(
          tester,
          controller,
          ReceiveContentPage(controller: controller, task: _task, share: true),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(shares, isEmpty);
        expect(
          commands.where((command) => command == 'media.cache.retain'),
          isEmpty,
        );
        status = 'completed';
        events.add({'type': 'transfers.changed', 'transferId': _task['id']});
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          commands.where((command) => command == 'media.cache.retain').length,
          1,
        );
        expect(
          shares,
          isEmpty,
          reason: 'The share sheet must wait for retained original protection.',
        );
        retained.complete({'retained': true});
        await tester.pumpAndSettle();
        expect(shares, hasLength(1));
        expect((shares.single.arguments as Map)['paths'], [
          '/private/original.jpg',
        ]);
        expect((shares.single.arguments as Map)['originWidth'], greaterThan(0));
        events.add({'type': 'transfers.changed', 'transferId': _task['id']});
        await tester.pumpAndSettle();
        expect(
          shares,
          hasLength(1),
          reason: 'A repeated receipt must not open system sharing twice.',
        );
        expect(find.byType(CheckboxListTile), findsNothing);
        if (sharingFails) {
          shareResponse.completeError(PlatformException(code: 'unavailable'));
        } else {
          shareResponse.complete('com.example.receiver');
        }
        await tester.pumpAndSettle();
        expect(
          find.textContaining(sharingFails ? '系统分享未确认完成' : '已交给系统选择的应用'),
          findsOneWidget,
        );
        if (sharingFails) {
          final retry = find.widgetWithText(FilledButton, '重新打开系统分享');
          expect(tester.widget<FilledButton>(retry).onPressed, isNull);
          await _tap(tester, find.byType(CheckboxListTile));
          shareResponse = Completer<String>();
          await _tap(tester, retry);
          expect(shares, hasLength(2));
          final checkbox = find.byType(CheckboxListTile);
          expect(tester.widget<CheckboxListTile>(checkbox).onChanged, isNull);
          await _tap(tester, checkbox);
          shareResponse.complete('com.example.receiver');
          await tester.pumpAndSettle();
          expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
          expect(tester.widget<FilledButton>(retry).onPressed, isNull);
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      },
    );
  }
  for (final thumbnail in [true, false]) {
    testWidgets(
      'a late ${thumbnail ? 'thumbnail' : 'preview'} releases only its returned cache lease',
      (tester) async {
        final response = Completer<Json>();
        var blocked = false, cleared = false;
        final released = <Json>[];
        var originalRequests = 0;
        final command = thumbnail ? 'media.thumbnail' : 'media.preview';
        final controller = createTestController((
          name, [
          params = const {},
        ]) async {
          if (name == command) {
            originalRequests++;
            if (blocked) {
              throw const RequestFailure(
                'cache_budget_exceeded',
                '需要 20，当前可用 10',
              );
            }
            return response.future;
          }
          if (name == 'media.cache.status') {
            return {'reclaimableBytes': cleared ? 0 : 4};
          }
          if (name == 'media.cache.clear') {
            cleared = true;
            return {'deletedBytes': 4};
          }
          if (name == 'media.cache.release') released.add(Map.of(params));
          return {};
        });
        const device = {'id': 'a', 'name': '手机 A'};
        if (!thumbnail) {
          await _mount(
            tester,
            controller,
            MediaPreviewPage(
              controller: controller,
              device: device,
              file: const {
                'path': '/clip.mp4',
                'name': 'clip.mp4',
                'mime': 'video/mp4',
              },
            ),
          );
          await tester.pump();
          expect(
            originalRequests,
            0,
            reason: 'Video information must not retrieve the original.',
          );
          expect(find.text('保存视频后打开'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        }
        const file = {'path': '/a.jpg', 'name': 'a.jpg', 'mime': 'image/jpeg'};
        await _mount(
          tester,
          controller,
          thumbnail
              ? SizedBox(
                  width: 100,
                  height: 100,
                  child: MediaThumbnail(
                    controller: controller,
                    device: device,
                    file: file,
                  ),
                )
              : MediaPreviewPage(
                  controller: controller,
                  device: device,
                  file: file,
                ),
        );
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        response.complete({
          'localPath': '/a.jpg',
          'cacheLeaseId': 'owned-late-lease',
        });
        await tester.pump();
        await tester.pump();
        expect(released, [
          {'leaseId': 'owned-late-lease'},
        ]);
        if (!thumbnail) {
          blocked = true;
          await _mount(
            tester,
            controller,
            MediaPreviewPage(
              controller: controller,
              device: device,
              file: file,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('需要 20，当前可用 10'), findsOneWidget);
          await _tap(tester, find.text('清理可回收暂存'));
          await _tap(tester, find.text('清理暂存'));
          expect(cleared, isTrue);
          expect(find.textContaining('实际回收 4 字节'), findsOneWidget);
          expect(find.text('清理可回收暂存'), findsNothing);
          await tester.pumpWidget(const SizedBox());
        }
        controller.dispose();
      },
    );
  }
}
