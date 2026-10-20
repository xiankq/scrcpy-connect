import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/connection/usb/connection_usb_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/import/devices_workspace_files_import_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/search/devices_workspace_files_search_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/export/transfers_details_export_page.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  for (final importing in [true, false]) {
    testWidgets(
      'document ${importing ? 'import' : 'export'} builds failures only near the viewport',
      (tester) async {
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          if (command ==
              (importing ? 'documents.importDirectory' : 'documents.export')) {
            return {
              'status': 'partial',
              'localPath': '/cache/Docs',
              'name': 'Docs',
              'files': 1,
              'directories': 1,
              'bytes': 4,
              'skipped': 1000,
              'errors': List.generate(
                1000,
                (i) => {'path': 'failure-$i', 'message': '无法读取'},
              ),
            };
          }
          return {};
        });
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            theme: ConnectTokens.theme(Brightness.light),
            home: importing
                ? DocumentImportPage(
                    controller: controller,
                    device: const {'id': 'phone'},
                    destination: '/sdcard',
                    onSubmitted: () {},
                  )
                : DocumentExportPage(
                    controller: controller,
                    localPath: '/cache/Docs',
                    name: 'Docs',
                    kind: 'directory',
                  ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(importing ? '选择系统文件夹' : '选择系统位置并保存'),
          200,
        );
        await tester.tap(find.text(importing ? '选择系统文件夹' : '选择系统位置并保存'));
        await tester.pumpAndSettle();
        expect(find.textContaining('failure-999'), findsNothing);
        expect(find.textContaining('failure-').evaluate().length, lessThan(30));
        await tester.scrollUntilVisible(
          find.text('failure-999：无法读取'),
          2500,
          maxScrolls: 100,
        );
        expect(find.text('failure-999：无法读取'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  for (final embedded in [false, true]) {
    testWidgets('USB $embedded keeps device rows in one vertical viewport', (
      tester,
    ) async {
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'devices.usb') {
          return {
            'devices': List.generate(1000, (i) => {'serial': 'serial-$i'}),
          };
        }
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: embedded
              ? ConnectionFormPage(
                  controller: controller,
                  initialMode: AddDeviceMode.usb,
                )
              : UsbGuidePage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      final vertical = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      expect(vertical, findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('检查连接'),
        200,
        scrollable: vertical,
      );
      await tester.tap(find.text('检查连接'));
      await tester.pumpAndSettle();
      expect(find.text('serial-999'), findsNothing);
      expect(find.textContaining('serial-').evaluate().length, lessThan(30));
      await tester.scrollUntilVisible(
        find.text('serial-999'),
        2500,
        maxScrolls: 100,
        scrollable: vertical,
      );
      expect(find.text('serial-999'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('search scope issues expand as lazy main-scroll rows', (
    tester,
  ) async {
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command == 'files.search.start' || command == 'files.search.get') {
        return {
          'searchId': 'search',
          'deviceId': 'phone',
          'path': '/sdcard',
          'query': '报告',
          'filter': 'all',
          'status': 'partial',
          'complete': false,
          'entries': <Object>[],
          'issues': List.generate(
            128,
            (i) => {'path': 'issue-$i', 'reason': '无权限'},
          ),
        };
      }
      return {};
    });
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        theme: ConnectTokens.theme(Brightness.light),
        home: FileSearchPage(
          controller: controller,
          device: const {'id': 'phone'},
          initialQuery: '报告',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pumpAndSettle();
    expect(find.text('issue-127\n无权限'), findsNothing);
    expect(find.textContaining('issue-').evaluate().length, lessThan(30));
    await tester.scrollUntilVisible(
      find.text('搜索范围与跳过项'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('搜索范围与跳过项'));
    await tester.pumpAndSettle();
    expect(find.text('issue-0\n无权限'), findsNothing);
    await tester.tap(find.text('搜索范围与跳过项'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('issue-127\n无权限'),
      1500,
      maxScrolls: 30,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('issue-127\n无权限'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
