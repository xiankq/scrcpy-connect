import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/search/devices_workspace_files_search_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/details/devices_workspace_files_details_page.dart';

import 'support/test_controller.dart';
import 'support/router_test_app.dart';

import 'dart:async';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';

AppStore _fileController(ApplicationRequest request) =>
    createTestController(request)
      ..devices = [
        {'id': 'phone', 'status': 'connected'},
      ];

Widget _filesPage(AppStore controller, {String initialPath = '/sdcard'}) =>
    RouterTestApp(
      controller: controller,
      theme: ConnectTokens.theme(Brightness.light),
      home: FilesPage(
        controller: controller,
        device: const {'id': 'phone', 'name': '我的手机'},
        initialPath: initialPath,
      ),
    );

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
      final controller = _fileController((command, [params = const {}]) async {
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
      await tester.pumpWidget(_filesPage(controller));
      await tester.pumpAndSettle();
      await _openDirectorySearch(tester);
      expect(find.text('我的手机'), findsNothing);
      expect(find.text('文件类型'), findsNothing);
      await tester.enterText(find.byType(TextField), '报告');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pump();
      expect(reads, 1);
      await tester.tap(find.text('停止搜索'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.textContaining('已停止 · 保留 0 项'), findsOneWidget);
      oldRead.complete(snapshot('running'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('已停止 · 保留 0 项'), findsOneWidget);
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
    final controller = _fileController((command, [params = const {}]) async {
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
    await tester.pumpWidget(_filesPage(controller));
    await tester.pumpAndSettle();
    await _openDirectorySearch(tester);
    await tester.enterText(find.byType(TextField), '旧查询');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pump();
    controller.focusedDeviceId = 'different-phone';
    await tester.tap(
      find.byTooltip(
        MaterialLocalizations.of(tester.element(find.byType(FileSearchPage)))
            .backButtonTooltip,
      ),
    );
    await tester.pumpAndSettle();
    lateStart.complete({
      'searchId': 'late-own-search',
      'deviceId': 'phone',
      'path': '/sdcard',
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
  testWidgets('changing the draft scope keeps the submitted result', (
    tester,
  ) async {
    final starts = <Json>[];
    final cancellations = <Json>[];
    final controller = _fileController((command, [params = const {}]) async {
      switch (command) {
        case 'files.list':
          return {'entries': <Json>[]};
        case 'device.info':
          return {'id': 'phone', 'name': '我的手机'};
        case 'files.search.start':
          starts.add(params);
          return {
            'searchId': 'search-${starts.length}',
            'deviceId': 'phone',
            'path': params['path'],
            'status': 'running',
          };
        case 'files.search.get':
          return {
            'searchId': 'search-${starts.length}',
            'deviceId': 'phone',
            'path': starts.last['path'],
            'query': starts.last['query'],
            'filter': starts.last['filter'],
            'status': 'completed',
            'complete': true,
            'visitedDirectories': 2,
            'visitedEntries': 4,
            'issues': <Json>[],
            'entries': [
              {
                'name': '报告.pdf',
                'path': '${starts.last['path']}/报告.pdf',
                'size': 1200,
                'isDirectory': false,
                'canOpen': true,
                'canManage': true,
              },
            ],
          };
        case 'files.search.cancel':
          cancellations.add(params);
          return {'status': 'cancelled'};
        default:
          return {};
      }
    });
    await tester.pumpWidget(
      _filesPage(controller, initialPath: '/sdcard/Download'),
    );
    await tester.pumpAndSettle();
    await _openDirectorySearch(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('file-search-type-field'))),
      isA<Size>().having(
        (size) => size.height,
        'readable height',
        greaterThanOrEqualTo(56),
      ),
    );
    await tester.enterText(find.byType(TextField), '报告');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pumpAndSettle();
    expect(starts.single['path'], '/sdcard/Download');
    expect(find.text('报告.pdf'), findsOneWidget);

    await tester.tap(find.text('手机内部存储'));
    await tester.pumpAndSettle();
    expect(cancellations, isEmpty);
    expect(starts, hasLength(1));
    expect(find.text('报告.pdf'), findsOneWidget);
    expect(find.textContaining('当前目录及子目录 · 已检查 2 个文件夹 / 4 项'), findsOneWidget);
    expect(find.textContaining('手机内部存储 · 已检查'), findsNothing);
    expect(find.text('条件已修改。以下仍为“报告”的结果，点击搜索更新。'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pumpAndSettle();
    expect(starts.map((params) => params['path']), [
      '/sdcard/Download',
      '/sdcard',
    ]);
    expect(cancellations, isEmpty);
    expect(find.textContaining('手机内部存储 · 已检查 2 个文件夹 / 4 项'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('searches nested names in the chosen device and directory', (
    tester,
  ) async {
    final starts = <Json>[];
    final controller = _fileController((command, [params = const {}]) async {
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
            'path': params['path'],
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
      _filesPage(controller, initialPath: '/sdcard/Download'),
    );
    await tester.pumpAndSettle();
    await _openDirectorySearch(tester);
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
    expect(find.textContaining('找到 2 项'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

Future<void> _openDirectorySearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('搜索文件'));
  await tester.pumpAndSettle();
  expect(find.text('文件搜索'), findsOneWidget);
}
