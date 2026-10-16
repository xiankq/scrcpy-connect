import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/document_export/document_export_page.dart';
import 'package:scrcpy_connect/pages/document_import/document_import_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'partial directory import requires review before sending its cached subset as one batch',
    (tester) async {
      Json? pushed;
      var submitted = false;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'documents.importDirectory') {
          return {
            'status': 'partial',
            'localPath': '/private/cache/Docs',
            'name': 'Docs',
            'files': 1,
            'directories': 1,
            'bytes': 4,
            'skipped': 1,
            'errors': [
              {'path': 'locked.txt', 'message': '无法读取'},
            ],
          };
        }
        if (command == 'files.push') pushed = params;
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: DocumentImportPage(
            controller: controller,
            device: const {'id': 'phone'},
            destination: '/sdcard',
            onSubmitted: () => submitted = true,
          ),
        ),
      );
      await tester.tap(find.text('选择系统文件夹'));
      await tester.pumpAndSettle();
      expect(pushed, isNull);
      expect(find.text('部分内容已取回，请先核对'), findsOneWidget);
      final send = find.widgetWithText(FilledButton, '发送已核对的内容');
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认发送'));
      await tester.pumpAndSettle();
      expect(pushed, {
        'deviceId': 'phone',
        'items': [
          {'source': '/private/cache/Docs', 'destination': '/sdcard/Docs'},
        ],
        'conflict': 'ask',
      });
      expect(submitted, isTrue);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'a partial system save retains cache and reports provider errors without claiming completion',
    (tester) async {
      Json? exported;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'documents.export') {
          exported = params;
          return {
            'status': 'partial',
            'name': 'Documents',
            'files': 1,
            'directories': 1,
            'bytes': 4,
            'errors': [
              {
                'path': 'second.txt',
                'code': 'write_failed',
                'message': '系统位置写入失败',
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
          home: DocumentExportPage(
            controller: controller,
            localPath: '/private/cache/Documents',
            name: 'Documents',
            kind: 'directory',
          ),
        ),
      );
      await tester.tap(find.text('选择系统位置并保存'));
      await tester.pumpAndSettle();
      expect(exported?['localPath'], '/private/cache/Documents');
      expect(exported?['operationId'], isNotEmpty);
      expect(exported?['conflict'], 'ask');
      expect(find.text('部分内容已保存，请核对'), findsOneWidget);
      expect(find.text('已保存到系统位置'), findsNothing);
      expect(find.textContaining('second.txt'), findsOneWidget);
      expect(find.textContaining('本机暂存仍保留'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'leaving a pending document save cancels only its operation and ignores a late result',
    (tester) async {
      final pending = Completer<Json>();
      Json? exported;
      Json? cancelled;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'documents.export') {
          exported = params;
          return pending.future;
        }
        if (command == 'documents.cancel') cancelled = params;
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: DocumentExportPage(
            controller: controller,
            localPath: '/private/cache/file',
            name: 'file',
            kind: 'file',
          ),
        ),
      );
      await tester.tap(find.text('选择系统位置并保存'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(cancelled?['operationId'], exported?['operationId']);
      pending.complete({'status': 'saved', 'name': 'late'});
      await tester.pump();
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );
}
