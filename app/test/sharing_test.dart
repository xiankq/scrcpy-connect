import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:scrcpy_connect/router/app_router.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/incoming_share/incoming_share_page.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'an open share waits for import and then presents its ready files',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = StreamController<Json>();
      final controller =
          createTestController(
              (command, [params = const {}]) async => {},
              events: events.stream,
            )
            ..devices = [
              {'id': 'phone', 'name': '接收手机', 'status': 'connected'},
            ]
            ..pendingShares = [
              {'shareId': 'import', 'status': 'importing', 'text': '与文件一起发送'},
            ];
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: IncomingSharePage(
            controller: controller,
            share: controller.pendingShares.single,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('接收手机'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认提交'))
            .onPressed,
        isNull,
      );
      events.add({
        'type': 'share.received',
        'data': {
          'shareId': 'import',
          'status': 'ready',
          'text': '与文件一起发送',
          'files': [
            {
              'name': '新文件.txt',
              'localPath': '/cache/incoming/file',
              'size': 12,
            },
          ],
        },
      });
      await tester.pump();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('新文件.txt'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认提交'))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        controller.dispose();
        await events.close();
      });
    },
  );
  test(
    'a pending import receives its ready files without snapshot regression',
    () async {
      final events = StreamController<Json>();
      final controller = createTestController(
        (command, [params = const {}]) async => command == 'sharing.pending'
            ? {
                'shares': [
                  {
                    'shareId': 'import',
                    'status': 'importing',
                    'files': <Object?>[],
                  },
                ],
              }
            : {},
        events: events.stream,
      );
      await controller.loadPendingShares();
      events.add({
        'type': 'share.received',
        'data': {
          'shareId': 'import',
          'status': 'ready',
          'files': [
            {'name': '文件.txt', 'localPath': '/cache/incoming/file'},
          ],
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.pendingShares.single['status'], 'ready');
      expect(objects(controller.pendingShares.single['files']), hasLength(1));
      await controller.loadPendingShares();
      expect(controller.pendingShares.single['status'], 'ready');
      expect(objects(controller.pendingShares.single['files']), hasLength(1));
      controller.dispose();
      await events.close();
    },
  );
  testWidgets(
    'a shared draft stays pending when the phone has not confirmed clipboard application',
    (tester) async {
      final requests = <String>[];
      final controller =
          createTestController((command, [params = const {}]) async {
              requests.add(command);
              return {'applied': false, 'reason': '尚未确认手机剪贴板写入，分享文字仍保留。'};
            })
            ..devices = [
              {'id': 'phone', 'name': '接收手机', 'status': 'connected'},
            ];
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: IncomingSharePage(
            controller: controller,
            share: const {'shareId': 'pending', 'text': '保留我的草稿'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('接收手机'));
      await tester.pump();
      await tester.ensureVisible(find.text('确认提交'));
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(find.text('尚未确认手机剪贴板写入，分享文字仍保留。'), findsOneWidget);
      expect(find.text('保留我的草稿'), findsOneWidget);
      expect(requests.where((c) => c == 'clipboard.set'), hasLength(1));
      expect(requests.where((c) => c == 'sharing.consume'), isEmpty);
      expect(find.byType(IncomingSharePage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  test('pending and live shares deduplicate by identity, including consumed events', () async {
    final events = StreamController<Json>();
    final share = {'shareId': 'share-1', 'text': 'shared text'};
    final controller = createTestController(
      (command, [params = const {}]) async => command == 'sharing.pending'
          ? {
              'shares': [share],
            }
          : {},
      events: events.stream,
    );
    await controller.loadPendingShares();
    events.add({'type': 'share.received', 'data': share});
    await Future<void>.delayed(Duration.zero);
    expect(controller.pendingShares, hasLength(1));
    await controller.consumeShare('share-1');
    events.add({'type': 'share.received', 'data': share});
    await Future<void>.delayed(Duration.zero);
    expect(controller.pendingShares, isEmpty);
    controller.dispose();
    await events.close();
  });

  test('后台消费只结束对应分享，旧查询和迟到事件不能复活或阻塞全局状态', () async {
    final events = StreamController<Json>();
    final stale = Completer<Json>();
    var reads = 0;
    const first = {'shareId': 'share-1', 'status': 'ready'};
    const second = {'shareId': 'share-2', 'status': 'ready'};
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command == 'sharing.pending') {
        if (++reads == 2) return stale.future;
        return {
          'shares': [first, second],
        };
      }
      throw StateError('消费事实不能触发全局状态恢复或设备操作');
    }, events: events.stream);
    await controller.loadPendingShares();
    final oldQuery = controller.loadPendingShares();
    events.add({
      'type': 'share.consumed',
      'data': {'shareId': 'share-1'},
    });
    await Future<void>.delayed(Duration.zero);
    stale.complete({
      'shares': [first, second],
    });
    await oldQuery;
    events.add({'type': 'share.received', 'data': first});
    await Future<void>.delayed(Duration.zero);
    expect(controller.pendingShares, [second]);
    expect(controller.snapshot().reconciliationPending, isFalse);
    controller.dispose();
    await events.close();
  });

  testWidgets(
    'incoming share requires a target and retries acknowledgment without resubmitting files',
    (tester) async {
      final requests = <(String, Json)>[];
      var acknowledgments = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        requests.add((command, params));
        if (command == 'sharing.consume' && acknowledgments++ == 0) {
          throw StateError('acknowledgment unavailable');
        }
        if (command == 'clipboard.set') return {'applied': true};
        return {};
      });
      controller.devices = [
        {'id': 'target', 'name': '接收手机', 'status': 'connected'},
      ];
      const share = {
        'shareId': 'share-2',
        'text': 'draft only',
        'files': [
          {'localPath': '/tmp/shared.pdf', 'name': 'shared.pdf', 'size': 300},
        ],
      };
      controller.queueTestShare(share);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    IncomingShareRoute(shareId: value(share, 'shareId'))
                        .push<void>(context),
                child: const Text('打开分享'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开分享'));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      final listScroll = find
          .descendant(
            of: find.byType(IncomingSharePage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('确认提交'),
        250,
        scrollable: listScroll,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认提交'))
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('接收手机'),
        -250,
        scrollable: listScroll,
      );
      await tester.tap(find.text('接收手机'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('确认提交'),
        250,
        scrollable: listScroll,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('确认提交')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.$1 == 'files.push').single.$2, {
        'shareId': 'share-2',
        'deviceId': 'target',
        'items': [
          {
            'source': '/tmp/shared.pdf',
            'destination': '/sdcard/Download/shared.pdf',
          },
        ],
        'conflict': 'ask',
      });
      expect(requests.where((r) => r.$1 == 'clipboard.set').single.$2, {
        'deviceId': 'target',
        'text': 'draft only',
      });
      expect(requests.where((r) => r.$1 == 'session.text'), isEmpty);
      await tester.scrollUntilVisible(
        find.text('继续完成'),
        250,
        scrollable: listScroll,
      );
      await tester.tap(find.text('继续完成'));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.$1 == 'files.push'), hasLength(1));
      expect(requests.where((r) => r.$1 == 'clipboard.set'), hasLength(1));
      expect(acknowledgments, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
