import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/transfers/details/export/transfers_details_export_page.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets(
    'conflict events, late reads and page exit remain bound to the saved original',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      final delayedRead = Completer<Json>();
      final source = ValueNotifier<String>('a');
      final cancelled = <String>[];
      final controller = createTestController((command, params) async {
        if (command == 'delivery.get') {
          final owner = params['localPath'] == '/cache/a'
              ? 'owner-a'
              : 'owner-b';
          return {
            'record': {'operationId': owner, 'status': 'pending'},
          };
        }
        if (command == 'documents.conflict.get') {
          return params['operationId'] == 'owner-a'
              ? delayedRead.future
              : {
                  'pending': {
                    'operationId': 'owner-b',
                    'conflictId': 'b-conflict',
                    'name': 'B 的同名文件夹',
                  },
                };
        }
        if (command == 'documents.cancel') {
          cancelled.add(params['operationId'] as String);
        }
        return {};
      }, events: events.stream);
      void conflict(String owner, String id, String name) => events.add({
        'type': 'documents.conflict.changed',
        'data': {
          'operationId': owner,
          'pending': {'operationId': owner, 'conflictId': id, 'name': name},
        },
      });
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: ValueListenableBuilder<String>(
              valueListenable: source,
              builder: (_, id, _) => DocumentExportPage(
                controller: controller,
                transferId: 'device-$id-task',
                localPath: '/cache/$id',
                name: '原件 $id',
                kind: 'directory',
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        conflict('owner-b', 'foreign', '不属于本页');
        await tester.pump();
        expect(find.text('存在同名项目'), findsNothing);
        conflict('owner-a', 'a-live', 'A 的同名文件夹');
        await tester.pump();
        expect(find.text('A 的同名文件夹'), findsOneWidget);
        events.add({
          'type': 'documents.conflict.changed',
          'data': {'operationId': 'owner-a', 'pending': null},
        });
        await tester.pump();
        delayedRead.complete({
          'pending': {
            'operationId': 'owner-a',
            'conflictId': 'a-stale',
            'name': '迟到的旧冲突',
          },
        });
        await tester.pump();
        expect(find.text('迟到的旧冲突'), findsNothing);
        expect(find.text('存在同名项目'), findsNothing);
        source.value = 'b';
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(cancelled, ['owner-a']);
        expect(find.text('B 的同名文件夹'), findsOneWidget);
        conflict('owner-a', 'late-a', '离页后的 A 冲突');
        await tester.pump();
        expect(find.text('离页后的 A 冲突'), findsNothing);
        expect(find.text('B 的同名文件夹'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        expect(cancelled, ['owner-a', 'owner-b']);
        conflict('owner-b', 'after-dispose', '离页后');
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        source.dispose();
        controller.dispose();
        await events.close();
      }
    },
  );

  testWidgets(
    'restored export reads its own pending conflict and resolves in the shared page',
    (tester) async {
      Json? read, resolved;
      final controller = createTestController((command, params) async {
        if (command == 'delivery.get') {
          return {
            'record': {'operationId': 'restored-owner', 'status': 'pending'},
          };
        }
        if (command == 'documents.conflict.get') {
          read = params;
          return {
            'pending': {
              'operationId': 'restored-owner',
              'conflictId': 'name-collision',
              'name': '旅行照片',
              'replacementSupported': false,
            },
          };
        }
        if (command == 'documents.conflict.resolve') {
          resolved = params;
          return {'resolved': true};
        }
        return {};
      });
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: DocumentExportPage(
              controller: controller,
              transferId: 'device-a-transfer',
              localPath: '/cache/tree',
              name: '旅行照片',
              kind: 'directory',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('存在同名项目'), findsOneWidget);
        expect(read, {'operationId': 'restored-owner'});
        expect(find.text('此位置暂不支持替换同名内容；已有文件会保留。'), findsOneWidget);
        final apply = find.widgetWithText(CheckboxListTile, '应用于本次保存的后续同名项目');
        await tester.ensureVisible(apply);
        await tester.tap(apply);
        await tester.pump();
        final keepBoth = find.widgetWithText(FilledButton, '保留两份');
        await tester.ensureVisible(keepBoth);
        await tester.tap(keepBoth);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(resolved, {
          'operationId': 'restored-owner',
          'conflictId': 'name-collision',
          'choice': 'keepBoth',
          'applyToRemaining': true,
        });
        expect(find.text('存在同名项目'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
}
