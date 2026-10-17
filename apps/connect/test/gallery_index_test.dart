import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/gallery/gallery_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

const _device = <String, dynamic>{'id': 'phone-a', 'name': '我的手机'};

Json _receipt({
  String id = 'scan-a',
  String status = 'completed',
  List<Json> items = const [],
  int? next,
  int offset = 0,
  int? total,
}) => {
  'scanId': id,
  'deviceId': 'phone-a',
  'status': status,
  'complete': status == 'completed',
  'items': items,
  'total': total ?? items.length,
  'offset': offset,
  'nextOffset': next,
  'visitedDirectories': 5,
  'visitedEntries': 12,
  'scope': {
    'roots': ['/sdcard'],
    'excluded': ['应用私有目录、其他用户和存储卷'],
  },
  'issues': [
    if (status == 'partial')
      {
        'path': '/sdcard/Locked',
        'code': 'permission_denied',
        'reason': '无权读取此目录',
      },
  ],
  'issueCount': status == 'partial' ? 1 : 0,
};

Future<AppController> _mount(
  WidgetTester tester,
  BridgeRequest request, {
  bool settle = true,
}) async {
  final controller = createTestController(request);
  await tester.pumpWidget(
    RouterTestApp(
      controller: controller,
      theme: ConnectTokens.theme(Brightness.light),
      home: GalleryPage(controller: controller, device: _device),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  return controller;
}

Future<void> _dispose(WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
}

void main() {
  testWidgets('partial empty scan cannot claim the phone album is empty', (
    tester,
  ) async {
    final controller = await _mount(tester, (
      command, [
      params = const {},
    ]) async {
      return command == 'media.list' ? _receipt(status: 'partial') : {};
    });
    try {
      expect(find.text('相册中没有可显示的内容'), findsNothing);
      expect(find.text('已检查范围内没有可显示的内容'), findsOneWidget);
      expect(find.textContaining('部分目录未能检查'), findsOneWidget);
      expect(find.text('相册范围与未读项目'), findsOneWidget);
      await tester.tap(find.text('相册范围与未读项目'));
      await tester.pumpAndSettle();
      expect(find.textContaining('/sdcard/Locked'), findsOneWidget);
      expect(find.textContaining('无权读取此目录'), findsOneWidget);
      expect(find.textContaining('应用私有目录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, controller);
    }
  });

  testWidgets('loading more keeps the same device snapshot and earlier items', (
    tester,
  ) async {
    final calls = <Json>[];
    Json file(String name) => {
      'name': name,
      'path': '/sdcard/Download/$name',
      'mime': 'image/jpeg',
    };
    final controller = await _mount(tester, (
      command, [
      params = const {},
    ]) async {
      if (command != 'media.list') return {};
      calls.add(Map.of(params));
      return params['offset'] == 1
          ? _receipt(offset: 1, items: [file('second.jpg')], total: 2)
          : _receipt(items: [file('first.jpg')], next: 1, total: 2);
    });
    try {
      await tester.ensureVisible(find.text('加载更多'));
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(calls.last, {
        'deviceId': 'phone-a',
        'scanId': 'scan-a',
        'offset': 1,
        'limit': 100,
      });
      expect(find.text('first.jpg'), findsOneWidget);
      expect(find.text('second.jpg'), findsOneWidget);
      expect(find.textContaining('已显示 2 / 2 项'), findsOneWidget);
      expect(find.text('加载更多'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, controller);
    }
  });
  testWidgets('a replacement scan rejects an old in-flight page', (
    tester,
  ) async {
    final latePage = Completer<Json>();
    final cancellations = <String>[];
    var starts = 0;
    Json file(String name) => {
      'name': name,
      'path': '/sdcard/$name',
      'mime': 'image/jpeg',
    };
    final controller = await _mount(tester, (
      command, [
      params = const {},
    ]) async {
      if (command == 'media.scan.cancel') {
        cancellations.add(value(params, 'scanId'));
        return {};
      }
      if (command != 'media.list') return {};
      if (params['scanId'] != null) return latePage.future;
      starts++;
      return starts == 1
          ? _receipt(items: [file('old.jpg')], next: 1, total: 2)
          : _receipt(id: 'new-scan', items: [file('new.jpg')]);
    });
    try {
      await tester.ensureVisible(find.text('加载更多'));
      await tester.tap(find.text('加载更多'));
      await tester.pump();
      await tester.tap(find.byTooltip('重新检查相册'));
      await tester.pumpAndSettle();
      latePage.complete(
        _receipt(offset: 1, items: [file('late.jpg')], total: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('new.jpg'), findsOneWidget);
      expect(find.text('old.jpg'), findsNothing);
      expect(find.text('late.jpg'), findsNothing);
      expect(cancellations, contains('scan-a'));
      expect(tester.takeException(), isNull);
    } finally {
      if (!latePage.isCompleted) latePage.complete(_receipt());
      await _dispose(tester, controller);
    }
  });

  testWidgets('leaving before scan admission retires the exact late scan', (
    tester,
  ) async {
    final admission = Completer<Json>();
    final cancellations = <Json>[];
    final controller = await _mount(tester, (
      command, [
      params = const {},
    ]) async {
      if (command == 'media.list') return admission.future;
      if (command == 'media.scan.cancel') cancellations.add(Map.of(params));
      return {};
    }, settle: false);
    try {
      expect(find.text('正在检查手机中的照片与视频'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      admission.complete(_receipt(status: 'scanning'));
      await tester.pump();
      await tester.pump();
      expect(cancellations, [
        {'deviceId': 'phone-a', 'scanId': 'scan-a'},
      ]);
      expect(tester.takeException(), isNull);
    } finally {
      if (!admission.isCompleted) admission.complete(_receipt());
      await _dispose(tester, controller);
    }
  });

  testWidgets('a response from another device cannot populate the album', (
    tester,
  ) async {
    final controller = await _mount(tester, (
      command, [
      params = const {},
    ]) async {
      if (command != 'media.list') return {};
      return {
        ..._receipt(
          items: [
            {
              'name': 'other.jpg',
              'path': '/sdcard/other.jpg',
              'mime': 'image/jpeg',
            },
          ],
        ),
        'deviceId': 'phone-b',
      };
    });
    try {
      expect(find.text('other.jpg'), findsNothing);
      expect(find.textContaining('归属或范围无法核验'), findsOneWidget);
      expect(find.text('相册检查未完成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, controller);
    }
  });
  testWidgets('changing device clears the old album selection', (tester) async {
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command != 'media.list') return {};
      return {
        ..._receipt(
          id: 'scan-${params['deviceId']}',
          items: [
            {
              'name': 'same.jpg',
              'path': '/sdcard/same.jpg',
              'mime': 'image/jpeg',
            },
          ],
        ),
        'deviceId': params['deviceId'],
      };
    });
    Future<void> show(String id) async {
      await tester.pumpWidget(
        TestProviderScope(
          controller: controller,
          child: MaterialApp(
            theme: ConnectTokens.theme(Brightness.light),
            home: GalleryPage(
              controller: controller,
              device: {'id': id, 'name': id},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    try {
      await show('phone-a');
      await tester.tap(find.byTooltip('选择照片'));
      await tester.pump();
      await tester.tap(find.text('same.jpg'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      await show('phone-b');
      expect(find.text('已选择 1 项'), findsNothing);
      expect(find.text('保存原文件'), findsNothing);
      expect(find.byTooltip('选择照片'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, controller);
    }
  });
  testWidgets('a full page can append results after scrolling to its end', (
    tester,
  ) async {
    Json file(int i) => {
      'name': 'image-$i.jpg',
      'path': '/sdcard/image-$i.jpg',
      'mime': 'image/jpeg',
    };
    final calls = <Json>[];
    final controller = await _mount(tester, (
      command, [
      params = const {},
    ]) async {
      if (command != 'media.list') return {};
      calls.add(Map.of(params));
      return params['offset'] == 100
          ? _receipt(
              offset: 100,
              items: [for (var i = 100; i < 105; i++) file(i)],
              total: 105,
            )
          : _receipt(
              items: [for (var i = 0; i < 100; i++) file(i)],
              next: 100,
              total: 105,
            );
    });
    try {
      await tester.scrollUntilVisible(
        find.text('加载更多'),
        500,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 60,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(calls.last['offset'], 100);
      await tester.scrollUntilVisible(
        find.textContaining('已显示'),
        -800,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 60,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已显示 105 / 105 项'), findsOneWidget);
      expect(find.text('加载更多'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, controller);
    }
  });
}
