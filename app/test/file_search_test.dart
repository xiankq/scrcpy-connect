import 'package:scrcpy_connect/pages/file_details/file_details_page.dart';

import 'support/test_controller.dart';
import 'support/router_test_app.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/files/files_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

void main() {
  testWidgets(
    'a late running snapshot cannot revive a confirmed stopped search',
    (tester) async {
      final oldRead = Completer<Json>();
      var reads = 0;
      Json snapshot(String status) => {
        'searchId': 'own-search',
        'deviceId': 'phone',
        'path': '/sdcard',
        'query': '报告',
        'filter': 'all',
        'status': status,
        'complete': false,
        'entries': <Json>[],
        'issues': <Json>[],
      };
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        switch (command) {
          case 'files.list':
            return {'entries': <Json>[]};
          case 'device.info':
            return {'id': 'phone', 'name': '我的手机'};
          case 'files.search.start':
            return snapshot('running');
          case 'files.search.get':
            return ++reads == 1 ? oldRead.future : snapshot('cancelled');
          case 'files.search.cancel':
            return snapshot('cancelled');
          default:
            return {};
        }
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: FilesPage(
            controller: controller,
            device: const {'id': 'phone', 'name': '我的手机'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('搜索子文件夹'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '报告');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pump();
      expect(reads, 1);
      await tester.tap(find.text('停止搜索'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.textContaining('已停止搜索'), findsOneWidget);
      oldRead.complete(snapshot('running'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('已停止搜索'), findsOneWidget);
      expect(find.text('停止搜索'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('leaving before search creation cancels only its late identity', (
    tester,
  ) async {
    final lateStart = Completer<Json>();
    final cancellations = <Json>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      switch (command) {
        case 'files.list':
          return {'entries': <Json>[]};
        case 'device.info':
          return {'id': 'phone', 'name': '我的手机'};
        case 'files.search.start':
          return lateStart.future;
        case 'files.search.cancel':
          cancellations.add(params);
          return {'status': 'cancelled'};
        default:
          return {};
      }
    });
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        theme: ConnectTokens.theme(Brightness.light),
        home: FilesPage(
          controller: controller,
          device: const {'id': 'phone', 'name': '我的手机'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索子文件夹'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '旧查询');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pump();
    controller.focusedDeviceId = 'different-phone';
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    lateStart.complete({
      'searchId': 'late-own-search',
      'deviceId': 'phone',
      'status': 'running',
    });
    await tester.pump();
    await tester.pump();
    expect(cancellations, [
      {'deviceId': 'phone', 'searchId': 'late-own-search'},
    ]);
    expect(find.byType(FilesPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('searches nested names in the chosen device and directory', (
    tester,
  ) async {
    final starts = <Json>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      switch (command) {
        case 'files.list':
          return {
            'entries': [
              if (params['path'] == '/sdcard/Download/工作' ||
                  params['path'] == '/sdcard/Download/生活')
                {
                  'name': '报告.pdf',
                  'path': '${params['path']}/报告.pdf',
                  'size': 1200,
                  'isDirectory': false,
                  'canOpen': true,
                },
            ],
          };
        case 'device.info':
          return {'id': 'phone', 'name': '我的手机'};
        case 'files.search.start':
          starts.add(params);
          return {
            'searchId': 'search-one',
            'deviceId': 'phone',
            'status': 'running',
          };
        case 'files.search.get':
          return {
            'searchId': 'search-one',
            'deviceId': 'phone',
            'path': '/sdcard/Download',
            'query': '报告',
            'filter': 'all',
            'status': 'completed',
            'complete': true,
            'visitedDirectories': 3,
            'visitedEntries': 8,
            'issues': <Json>[],
            'entries': [
              {
                'name': '报告.pdf',
                'path': '/sdcard/Download/工作/报告.pdf',
                'size': 1200,
                'isDirectory': false,
                'canOpen': true,
                'canManage': true,
              },
              {
                'name': '报告.pdf',
                'path': '/sdcard/Download/生活/报告.pdf',
                'size': 2300,
                'isDirectory': false,
                'canOpen': true,
                'canManage': true,
              },
            ],
          };
        default:
          return {};
      }
    });
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        theme: ConnectTokens.theme(Brightness.light),
        home: FilesPage(
          controller: controller,
          device: const {'id': 'phone', 'name': '我的手机'},
          initialPath: '/sdcard/Download',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索子文件夹'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '报告');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pumpAndSettle();
    expect(starts.single, {
      'deviceId': 'phone',
      'path': '/sdcard/Download',
      'query': '报告',
      'filter': 'all',
    });
    expect(find.text('报告.pdf'), findsNWidgets(2));
    for (final directory in ['工作', '生活']) {
      final path = '/sdcard/Download/$directory/报告.pdf';
      expect(find.byTooltip(path), findsOneWidget);
      await tester.tap(find.byTooltip(path));
      await tester.pumpAndSettle();
      expect(find.byType(FileDetailsPage), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == path,
        ),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('已完成搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
