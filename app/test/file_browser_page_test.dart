import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';

import 'support/router_test_app.dart';
import 'support/page_back.dart';
import 'support/test_controller.dart';

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('root back exits the file route for header and system back', (
    tester,
  ) async {
    const device = {'id': 'phone', 'name': '我的手机', 'status': 'connected'};
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command == 'files.list') {
        final root = params['path'] == '/sdcard';
        return {
          'entries': <Json>[
            {
              'name': root ? 'Download' : 'inside.txt',
              'path': '/sdcard/Download${root ? '' : '/inside.txt'}',
              if (root) 'isDirectory': true,
              if (!root) 'mime': 'text/plain',
            },
          ],
        };
      }
      return {};
    });
    controller.devices = [device];
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        theme: ConnectTokens.theme(Brightness.light),
        devices: const [device],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => FilesRoute(deviceId: 'phone').push<void>(context),
            child: const Text('打开文件'),
          ),
        ),
      ),
    );

    await _tap(tester, find.text('打开文件'));
    await _tap(tester, find.text('Download'));
    await _tap(tester, pageBackButton(tester));
    expect(find.text('Download'), findsOneWidget);
    await _tap(tester, pageBackButton(tester));
    expect(find.text('打开文件'), findsOneWidget);
    expect(find.byType(FilesPage), findsNothing);

    await _tap(tester, find.text('打开文件'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('打开文件'), findsOneWidget);
    expect(find.byType(FilesPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'selection keeps geometry, includes loaded offscreen items and exits before navigating',
    (tester) async {
      const device = {'id': 'phone', 'name': '来源手机', 'status': 'connected'};
      final calls = <(String, Json)>[];
      var disconnected = false;
      var missing = false;
      var truncated = false;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'files.list') {
          if (disconnected) {
            throw const RequestFailure('not_connected', '设备已断开');
          }
          return {
            'entries': <Json>[
              {
                'name': 'Folder',
                'path': '/sdcard/Download/Folder',
                'isDirectory': true,
              },
              for (var index = 0; index < 12; index++)
                if (!missing || index != 0)
                  {
                    'name': 'file-$index.txt',
                    'path': '/sdcard/Download/file-$index.txt',
                    'size': 1,
                  },
              {
                'name': 'unavailable.txt',
                'path': '/sdcard/Download/unavailable.txt',
                'canManage': false,
                'canOpen': false,
              },
            ],
            'total': 30,
            'hasMore': !truncated,
            'truncated': truncated,
          };
        }
        return {};
      });
      controller.settings = {'fileViewMode': 'list'};
      controller.devices = [device];
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: FilesPage(
            controller: controller,
            device: device,
            initialPath: '/sdcard/Download',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getRect(find.text('file-0.txt'));
      await _tap(tester, find.byTooltip('更多文件操作'));
      await _tap(tester, find.text('选择'));
      expect(find.text('已选择 0 项'), findsOneWidget);
      await _tap(tester, find.byTooltip('退出选择'));
      await tester.longPress(find.text('file-0.txt'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      expect(tester.getRect(find.text('file-0.txt')), before);
      expect(find.byTooltip('搜索文件'), findsNothing);
      await tester.longPress(find.text('file-0.txt'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      await _tap(tester, find.byTooltip('全选'));
      expect(find.text('已选择 13 项'), findsOneWidget);
      await _tap(tester, find.text('Folder'));
      expect(find.text('已选择 12 项'), findsOneWidget);
      expect(calls.where((call) => call.$1 == 'files.list').length, 1);
      await _tap(tester, find.byTooltip('全选'));
      await _tap(tester, find.byTooltip('取消全选'));
      expect(find.text('已选择 0 项'), findsOneWidget);
      expect(find.text('取回原文件'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('已选择 0 项'), findsNothing);
      expect(find.text('文件管理'), findsOneWidget);
      expect(tester.getRect(find.text('file-0.txt')), before);
      expect(calls.where((call) => call.$1 == 'files.list').length, 1);
      final rightClick = await tester.startGesture(
        tester.getCenter(find.text('file-0.txt')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await rightClick.up();
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      VoidCallback? action(String label) => tester
          .widget<TextButton>(find.widgetWithText(TextButton, label))
          .onPressed;
      final retrieve = action('取回原文件')!;
      disconnected = true;
      controller.devices = [
        {...device, 'status': 'disconnected'},
      ];
      await tester.pumpAndSettle();
      expect(find.text('file-0.txt'), findsOneWidget);
      expect(find.text('已选择 1 项'), findsOneWidget);
      expect(action('删除'), isNull);
      retrieve();
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.$1 == 'files.pull'), isEmpty);
      disconnected = false;
      controller.devices = [device];
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      expect(action('删除'), isNotNull);
      missing = true;
      for (final cutOff in [false, true]) {
        truncated = cutOff;
        controller.devices = [
          {...device, 'status': 'disconnected'},
        ];
        await tester.pumpAndSettle();
        controller.devices = [device];
        await tester.pumpAndSettle();
        expect(find.text('已选择 1 项'), findsOneWidget);
        expect(action('取回原文件'), isNull);
        expect(action('删除'), isNull);
        expect(find.textContaining('已保留选择并暂停批量操作'), findsOneWidget);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        calls.where((call) => call.$1 == 'files.list').last.$2['path'],
        '/sdcard',
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
