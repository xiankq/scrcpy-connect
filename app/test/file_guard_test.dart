import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/devices/workspace/files/details/devices_workspace_files_details_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';

import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'unrepresentable file paths cannot open, select or mutate a valid replacement-character name',
    (tester) async {
      final deletes = <Json>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'files.delete') deletes.add(params);
        return command == 'files.list'
            ? {
                'entries': [
                  {
                    'name': 'broken�.txt',
                    'path': null,
                    'canOpen': false,
                    'canManage': false,
                    'reason': '此文件名无法转换为有效文字，暂时无法操作。',
                  },
                  {
                    'name': 'literal�.txt',
                    'path': '/sdcard/literal�.txt',
                    'canOpen': true,
                    'canManage': true,
                  },
                ],
              }
            : {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: FilesPage(
            controller: controller,
            device: const {'id': 'phone', 'name': '手机'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('此文件名无法转换为有效文字，暂时无法操作。'), findsOneWidget);
      await tester.tap(find.text('broken�.txt'));
      await tester.longPress(find.text('broken�.txt'));
      await tester.pumpAndSettle();
      expect(find.byType(FileDetailsPage), findsNothing);
      expect(find.byTooltip('删除所选'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('literal�.txt')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('/sdcard/literal�.txt'), findsOneWidget);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      final literalName = find.text('literal�.txt');
      await tester.longPressAt(
        tester.getCenter(literalName) - const Offset(0, 80),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('broken�.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('broken�.txt'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      await tester.tap(find.byTooltip('删除所选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(deletes.single['paths'], ['/sdcard/literal�.txt']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
