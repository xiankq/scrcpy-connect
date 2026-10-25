import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/router/app_router.dart';

import 'support/test_controller.dart';

void main() {
  testWidgets(
    'one download stays on its save task until verified bytes are ready',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      Json transfer = {
        'id': 'receive-a',
        'deviceId': 'phone-a',
        'name': '原图.png',
        'kind': 'file',
        'direction': 'pull',
        'destinationScope': 'privateCache',
        'status': 'running',
        'canCancel': true,
        'totalBytes': 20,
        'completedBytes': 10,
      };
      final submissions = <Json>[];
      final controller =
          createTestController((command, [params = const {}]) async {
              if (command == 'transfers.get') return transfer;
              if (command == 'documents.export') {
                submissions.add(params);
                return {'status': 'saved', 'bytes': 20, 'name': '原图.png'};
              }
              return {};
            }, events: events.stream)
            ..devices = [
              {'id': 'phone-a', 'name': '手机 A'},
              {'id': 'phone-b', 'name': '手机 B'},
            ];
      final router = createAppRouter(
        initialLocation: '/transfers/receive-a/receive',
      );
      await tester.pumpWidget(
        TestProviderScope(
          controller: controller,
          child: MaterialApp.router(
            routerConfig: router,
            theme: ConnectTokens.theme(Brightness.light),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('正在准备原文件'), findsOneWidget);
      expect(find.text('选择系统位置并保存'), findsNothing);
      expect(find.text('手机 A'), findsWidgets);
      expect(find.text('本机暂存'), findsWidgets);
      expect(submissions, isEmpty);
      controller.focusedDeviceId = 'phone-b';
      transfer = {
        ...transfer,
        'status': 'completed',
        'canCancel': false,
        'canExport': true,
        'localPath': '/private/outgoing/receive-a/原图.png',
      };
      events.add({
        'type': 'transfers.changed',
        'deviceId': 'phone-a',
        'transferId': transfer['id'],
      });
      await tester.pumpAndSettle();
      final save = find.text('选择系统位置并保存');
      expect(save, findsOneWidget);
      expect(find.text('系统副本'), findsOneWidget);
      expect(find.text('接收应用'), findsNothing);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('已保存到系统位置'), findsOneWidget);
      expect(
        submissions.single['localPath'],
        '/private/outgoing/receive-a/原图.png',
      );
      expect(controller.snapshot().focusedDeviceId, 'phone-b');
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      controller.dispose();
      await events.close();
    },
  );
}
