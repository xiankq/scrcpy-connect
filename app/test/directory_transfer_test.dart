import 'package:scrcpy_connect/models/application_request.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';

import 'support/router_test_app.dart';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'folder selection is previewed before its exact destination root is sent',
    (tester) async {
      Json? pushed;
      Json? imported;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'files.list') return {'entries': <Json>[]};
        if (command == 'documents.importDirectory') {
          imported = params;
          return {
            'status': 'imported',
            'name': 'Documents',
            'localPath': '/tmp/imported/Documents',
            'files': 2,
            'directories': 1,
            'bytes': 1280,
            'errors': <Json>[],
          };
        }
        if (command == 'files.push') pushed = params;
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: FilesPage(
            controller: controller,
            device: const {'id': 'phone'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('发送到手机'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送本机文件夹'));
      await tester.pumpAndSettle();
      expect(find.text('发送到手机'), findsOneWidget);
      expect(find.text('准备发送一个文件夹'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '选择文件夹'));
      await tester.pumpAndSettle();
      expect(imported, {'operationId': isA<String>()});
      expect(find.text('Documents'), findsWidgets);
      expect(find.text('2 个文件 · 1 个文件夹 · 1.3 KB'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('发送此文件夹'), 240);
      await tester.tap(find.widgetWithText(FilledButton, '发送此文件夹'));
      await tester.pumpAndSettle();
      expect(find.text('发送此文件夹？'), findsOneWidget);
      await tester.tap(find.text('确认发送'));
      await tester.pumpAndSettle();
      expect(pushed, {
        'deviceId': 'phone',
        'items': [
          {
            'source': '/tmp/imported/Documents',
            'destination': '/sdcard/Documents',
          },
        ],
        'conflict': 'ask',
      });
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
