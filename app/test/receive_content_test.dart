import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/router/app_router.dart';

import 'support/test_controller.dart';

void main() {
  testWidgets(
    'one download keeps its source and automatically shares only verified bytes',
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
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final shares = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        shares.add(call);
        return 'com.example.receiver';
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final controller =
          createTestController((command, [params = const {}]) async {
              if (command == 'transfers.get') return transfer;
              return {};
            }, events: events.stream)
            ..devices = [
              {'id': 'phone-a', 'name': '手机 A'},
              {'id': 'phone-b', 'name': '手机 B'},
            ];
      final router = createAppRouter(
        initialLocation: '/transfers/receive-a/receive?share=true',
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
      expect(shares, isEmpty);
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
      expect(find.text('正在准备原文件'), findsNothing);
      expect(find.text('接收应用'), findsWidgets);
      expect(find.text('手机 A'), findsWidgets);
      expect(shares, hasLength(1));
      expect(shares.single.arguments['paths'], [
        '/private/outgoing/receive-a/原图.png',
      ]);
      expect(controller.snapshot().focusedDeviceId, 'phone-b');
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      controller.dispose();
      await events.close();
    },
  );
}
