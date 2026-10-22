import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';
import 'support/page_back.dart';
import 'support/test_controller.dart';

int _modified(int month, int day) =>
    DateTime.utc(2026, month, day).millisecondsSinceEpoch ~/ 1000;

void main() {
  testWidgets(
    'file page uses one continuous grid and opens the independent search page',
    (tester) async {
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'files.list') {
          return {
            'entries': <Json>[
              {
                'name': 'Download',
                'path': '/sdcard/Download',
                'isDirectory': true,
                'modified': _modified(1, 1),
              },
              {
                'name': '报告.pdf',
                'path': '/sdcard/报告.pdf',
                'mime': 'application/pdf',
                'size': 1200,
                'modified': _modified(1, 2),
              },
              {
                'name': '照片.jpg',
                'path': '/sdcard/照片.jpg',
                'mime': 'image/jpeg',
                'size': 2400,
                'canOpen': false,
                'canManage': false,
                'reason': '文件路径暂时无法核对',
              },
              {
                'name': '坏缩略图.jpg',
                'path': '/sdcard/坏缩略图.jpg',
                'mime': 'image/jpeg',
                'size': 2048,
                'modified': _modified(1, 3),
                'canOpen': true,
              },
            ],
          };
        }
        if (command == 'media.thumbnail') {
          throw const RequestFailure('thumbnail_failed', '缩略图生成失败');
        }
        if (command == 'device.info') {
          return {'id': 'phone', 'name': '我的手机'};
        }
        return {};
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

      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        ConnectTokens.theme(Brightness.light).colorScheme.surface,
      );
      expect(find.text('内部存储'), findsOneWidget);
      expect(find.text('我的手机'), findsNothing);
      expect(find.text('文件夹'), findsNothing);
      expect(find.text('文件'), findsNothing);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('报告.pdf'), findsOneWidget);
      expect(find.text('照片.jpg'), findsOneWidget);
      expect(find.text('坏缩略图.jpg'), findsOneWidget);
      expect(find.text('01/02'), findsOneWidget);
      expect(find.text('1.17 KB'), findsOneWidget);
      expect(find.byTooltip('重试缩略图'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('/sdcard/报告.pdf'))).height,
        isNot(
          equals(
            tester
                .getSize(find.byKey(const ValueKey('/sdcard/Download')))
                .height,
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text('Download')).textAlign,
        TextAlign.center,
      );
      expect(
        tester.widget<Text>(find.text('报告.pdf')).textAlign,
        TextAlign.center,
      );
      expect(find.byKey(const ValueKey(('file-grid-row', 0))), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byTooltip('搜索文件'));
      await tester.pumpAndSettle();
      expect(find.text('文件搜索'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('file-type-documents')));
      await tester.pumpAndSettle();
      expect(find.text('Download'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
      await tester.pumpAndSettle();
      expect(find.text('报告.pdf'), findsOneWidget);
      expect(find.text('照片.jpg'), findsNothing);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 520));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file-type-documents')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
      await tester.pumpAndSettle();
      expect(find.text('照片.jpg'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('file page keeps four columns at the phone reference width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command == 'files.list') {
        return {
          'entries': <Json>[
            {
              'name': 'Download',
              'path': '/sdcard/Download',
              'isDirectory': true,
            },
            {
              'name': '报告.pdf',
              'path': '/sdcard/报告.pdf',
              'mime': 'application/pdf',
              'size': 1200,
            },
          ],
        };
      }
      if (command == 'device.info') {
        return {'id': 'phone', 'name': '我的手机'};
      }
      return {};
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

    final row = tester.widget<Row>(
      find.byKey(const ValueKey(('file-grid-row', 0))),
    );
    expect(row.children.whereType<Expanded>(), hasLength(4));
    expect(find.byTooltip('刷新目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('view menu switches folders and files from grid to list', (
    tester,
  ) async {
    Future<Json> request(String command, [Json params = const {}]) async {
      if (command == 'files.list') {
        return {
          'entries': <Json>[
            {
              'name': 'Download',
              'path': '/sdcard/Download',
              'isDirectory': true,
              'modified': _modified(1, 1),
            },
            {
              'name': '报告.pdf',
              'path': '/sdcard/报告.pdf',
              'mime': 'application/pdf',
              'size': 1200,
              'modified': _modified(1, 2),
            },
            {
              'name': '笔记.txt',
              'path': '/sdcard/笔记.txt',
              'mime': 'text/plain',
              'size': 3600,
              'modified': _modified(1, 3),
            },
          ],
        };
      }
      if (command == 'device.info') {
        return {'id': 'phone', 'name': '我的手机'};
      }
      return {};
    }

    var controller = createTestController(request);
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
    expect(find.byKey(const ValueKey(('file-grid-row', 0))), findsOneWidget);

    await tester.tap(find.byTooltip('视图与排序'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassMenu), findsOneWidget);
    expect(find.byType(GlassMenuItem), findsWidgets);
    // The production backend may use Material anchors internally for focus
    // and dismissal; the contract is that the visible menu is the glass one.
    expect(find.byType(GlassMenuDivider), findsWidgets);
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(('file-grid-row', 0))), findsNothing);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('报告.pdf'), findsOneWidget);
    expect(find.textContaining('01/03 · 3.52 KB'), findsOneWidget);

    await tester.tap(find.byTooltip('视图与排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件大小'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('视图与排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('降序'));
    await tester.pumpAndSettle();
    expect(controller.settings['fileViewMode'], 'list');
    expect(controller.settings['fileSortKey'], 'size');
    expect(controller.settings['fileSortAscending'], isFalse);
    expect(
      tester.getTopLeft(find.text('笔记.txt')).dy,
      lessThan(tester.getTopLeft(find.text('报告.pdf')).dy),
    );

    final persisted = <String, dynamic>{...controller.settings};
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    controller = createTestController(request);
    controller.settings = persisted;
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
    expect(find.byKey(const ValueKey(('file-grid-row', 0))), findsNothing);
    expect(find.text('Download'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('笔记.txt')).dy,
      lessThan(tester.getTopLeft(find.text('报告.pdf')).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('header and system back leave a directory before the page', (
    tester,
  ) async {
    final requestedPaths = <String>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command == 'files.list') {
        requestedPaths.add('${params['path']}');
        return {
          'entries': <Json>[
            if (params['path'] == '/sdcard')
              {
                'name': 'Download',
                'path': '/sdcard/Download',
                'isDirectory': true,
              }
            else
              {
                'name': 'inside.txt',
                'path': '${params['path']}/inside.txt',
                'mime': 'text/plain',
              },
          ],
        };
      }
      if (command == 'device.info') {
        return {'id': 'phone', 'name': '我的手机'};
      }
      return {};
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

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('inside.txt'), findsOneWidget);

    await tester.tap(pageBackButton(tester));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('inside.txt'), findsNothing);

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FilesPage), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('inside.txt'), findsNothing);
    expect(requestedPaths, containsAll(['/sdcard', '/sdcard/Download']));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('root back exits the file route for header and system back', (
    tester,
  ) async {
    const device = {'id': 'phone', 'name': '我的手机'};
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command == 'files.list') {
        return {
          'entries': <Json>[
            if (params['path'] == '/sdcard')
              {
                'name': 'Download',
                'path': '/sdcard/Download',
                'isDirectory': true,
              }
            else
              {
                'name': 'inside.txt',
                'path': '/sdcard/Download/inside.txt',
                'mime': 'text/plain',
              },
          ],
        };
      }
      return {};
    });
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

    await tester.tap(find.text('打开文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.tap(pageBackButton(tester));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsOneWidget);
    await tester.tap(pageBackButton(tester));
    await tester.pumpAndSettle();
    expect(find.text('打开文件'), findsOneWidget);
    expect(find.byType(FilesPage), findsNothing);

    await tester.tap(find.text('打开文件'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('打开文件'), findsOneWidget);
    expect(find.byType(FilesPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('device source grows for a long name at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 620);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    const deviceName = '一台名称很长需要换行展示的测试手机设备';
    const device = {'id': 'phone', 'name': deviceName};
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command == 'files.list') {
        return {
          'entries': <Json>[
            {
              'name': '说明.txt',
              'path': '/sdcard/Download/说明.txt',
              'mime': 'text/plain',
              'size': 1200,
              'modified': _modified(1, 2),
            },
          ],
        };
      }
      return {};
    });
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
    expect(find.text(deviceName), findsOneWidget);
    expect(find.text('说明.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
