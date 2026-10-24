import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/transfers/details/export/transfers_details_export_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/import/devices_workspace_files_import_page.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a rejected admission restores the actual prior operation before review',
    (tester) async {
      var submissions = 0;
      Json? retry;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'delivery.get') {
          return {
            'record': submissions == 0
                ? null
                : {
                    'operationId': 'actual-prior-save',
                    'status': 'result_unknown',
                    'result': {
                      'status': 'result_unknown',
                      'partialDestinationPossible': true,
                    },
                  },
          };
        }
        if (command == 'documents.export') {
          submissions++;
          retry = params;
          throw const RequestFailure('delivery_review_required', '请核对之前的系统保存');
        }
        return {};
      });
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: DocumentExportPage(
              controller: controller,
              transferId: 'task',
              localPath: '/cache/a',
              name: 'a',
              kind: 'file',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('选择系统位置并保存'));
        await tester.pumpAndSettle();
        expect(submissions, 1);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        final retryButton = find.widgetWithText(FilledButton, '重新选择系统位置');
        await tester.ensureVisible(retryButton);
        await tester.tap(retryButton);
        await tester.pumpAndSettle();
        expect(retry?['reviewedOperationId'], 'actual-prior-save');
        expect(submissions, 2);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
  testWidgets(
    'a saved original reopens with its receipt and additional copying requires explicit confirmation',
    (tester) async {
      Json? submitted;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'delivery.get') {
          return {
            'record': {
              'operationId': 'saved-copy',
              'status': 'saved',
              'result': {'status': 'saved', 'name': 'original.png'},
            },
          };
        }
        if (command == 'documents.export') {
          submitted = params;
          return {'status': 'saved'};
        }
        return {};
      });
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: DocumentExportPage(
              controller: controller,
              transferId: 'source-task',
              localPath: '/cache/original.png',
              name: 'original.png',
              kind: 'file',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('已保存到系统位置'), findsOneWidget);
        expect(find.text('选择系统位置并保存'), findsNothing);
        expect(submitted, isNull);
        await tester.ensureVisible(find.text('再保存一份'));
        await tester.tap(find.text('再保存一份'));
        await tester.pumpAndSettle();
        expect(submitted, isNull);
        await tester.tap(find.text('选择新位置'));
        await tester.pumpAndSettle();
        expect(submitted?['additionalCopyOfOperationId'], 'saved-copy');
        expect(submitted?['sourceId'], 'transfer:source-task');
        expect(submitted?['localPath'], '/cache/original.png');
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
  testWidgets('failed journal verification never enables a system write', (
    tester,
  ) async {
    var writes = 0;
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command == 'delivery.get') throw StateError('journal unavailable');
      if (command == 'documents.export') writes++;
      return {};
    });
    try {
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: DocumentExportPage(
            controller: controller,
            localPath: '/cache/original',
            name: 'original',
            kind: 'file',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('尚未核验上次系统保存结果'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '选择系统位置并保存'),
            )
            .onPressed,
        isNull,
      );
      expect(writes, 0);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });
  testWidgets(
    'unknown system save still requires review after leaving and reopening its source',
    (tester) async {
      var writes = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'delivery.get') {
          return {
            'record': writes == 0
                ? null
                : {
                    'operationId': 'previous-system-write',
                    'status': 'result_unknown',
                    'result': {
                      'status': 'result_unknown',
                      'partialDestinationPossible': true,
                    },
                  },
          };
        }
        if (command == 'documents.export') {
          writes++;
          throw StateError('reply lost after provider write');
        }
        return {};
      });
      Widget page() => RouterTestApp(
        controller: controller,
        home: DocumentExportPage(
          controller: controller,
          transferId: 'original-task',
          localPath: '/private/cache/original.png',
          name: 'original.png',
          kind: 'file',
        ),
      );
      try {
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        await tester.tap(find.text('选择系统位置并保存'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(find.text('系统保存结果待核对'), findsOneWidget);
        final retry = find.widgetWithText(FilledButton, '重新选择系统位置');
        expect(tester.widget<FilledButton>(retry).onPressed, isNull);
        expect(writes, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
  testWidgets('a preflight failure reports no save and allows explicit retry', (
    tester,
  ) async {
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command == 'documents.export') {
        return {
          'status': 'failed',
          'files': 0,
          'directories': 0,
          'bytes': 0,
          'partialDestinationPossible': false,
          'errors': [
            {'message': '原文件已变化'},
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
          localPath: '/private/cache/file',
          name: 'file',
          kind: 'file',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择系统位置并保存'));
    await tester.pumpAndSettle();
    expect(find.text('本次保存未开始'), findsOneWidget);
    expect(find.text('部分内容已保存，请核对'), findsNothing);
    expect(find.text('系统保存结果待核对'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '重新选择系统位置'))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'a lost export reply requires review before another system write',
    (tester) async {
      var writes = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'documents.export') {
          writes++;
          throw StateError('reply lost after provider write');
        }
        if (command == 'delivery.get') {
          return {
            'record': writes == 0
                ? null
                : {
                    'operationId': 'lost-reply',
                    'status': 'result_unknown',
                    'result': {
                      'status': 'result_unknown',
                      'partialDestinationPossible': true,
                    },
                  },
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
            localPath: '/private/cache/original.png',
            name: 'original.png',
            kind: 'file',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择系统位置并保存'));
      await tester.pumpAndSettle();
      expect(find.text('系统保存结果待核对'), findsOneWidget);
      expect(find.text('已保存到系统位置'), findsNothing);
      final retry = find.widgetWithText(FilledButton, '重新选择系统位置');
      expect(tester.widget<FilledButton>(retry).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
      expect(writes, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
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
      await tester.tap(find.text('选择文件夹'));
      await tester.pumpAndSettle();
      expect(pushed, isNull);
      expect(find.text('部分内容已取回，请先核对'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('发送已核对的内容'), 240);
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
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择系统位置并保存'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(exported, isNotNull);
      expect(cancelled?['operationId'], exported?['operationId']);
      pending.complete({'status': 'saved', 'name': 'late'});
      await tester.pump();
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );
}
