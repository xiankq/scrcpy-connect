import 'package:flutter/services.dart';
import 'package:scrcpy_connect/services/file_selection_requests.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/widgets/documents/document_operation.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/transfers/details/export/transfers_details_export_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/import/devices_workspace_files_import_page.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DocumentOperationController _documentOperation(ApplicationRequest request) =>
    DocumentOperationController(
      request: request,
      execute: (command, params) => request(command.wire, params),
      events: const Stream<Json>.empty(),
    );

Widget _exportPage(
  AppStore controller, {
  required String localPath,
  String? transferId,
}) => RouterTestApp(
  controller: controller,
  theme: ConnectTokens.theme(Brightness.light),
  home: DocumentExportPage(
    controller: controller,
    localPath: localPath,
    name: p.basename(localPath),
    kind: 'file',
    transferId: transferId,
  ),
);

Json _unknownSave(String operationId) => {
  'operationId': operationId,
  'status': 'result_unknown',
  'result': {'status': 'result_unknown', 'partialDestinationPossible': true},
};

void main() {
  for (final leaveWhileChoosing in [false, true]) {
    testWidgets('文档视图匹配选择任务并处理迟到回执 leave=$leaveWhileChoosing', (tester) async {
      const channel = MethodChannel('dev.scrcpyconnect/platform');
      final chosen = Completer<Json>();
      final events = StreamController<Json>.broadcast(sync: true);
      var pickerCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expectSync(call.method, 'documents.platform.picker');
            pickerCalls++;
            return chosen.future;
          });
      final selections = FileSelectionRequests(
        (plan) =>
            events.add({'type': 'documents.selection.requested', 'data': plan}),
      );
      final operation = DocumentOperationController(
        events: events.stream,
        completeSelection: selections.complete,
        execute: (command, params) async {
          if (command == ApplicationCommand.documentsCancel) {
            selections.cancel(params['operationId'] as String);
          }
          return {'cancelled': true};
        },
        request: (command, [params = const {}]) async => selections.request({
          'operationId': params['operationId'],
          'mode': 'importFiles',
        }),
      );
      final work = operation.run('documents.importFiles', {});
      await tester.pump();
      expect(
        pickerCalls,
        1,
        reason:
            'error=${operation.error} busy=${operation.busy} id=${operation.operationId}',
      );
      events.add({
        'type': 'documents.selection.requested',
        'data': {'operationId': 'another-page', 'mode': 'importFiles'},
      });
      await tester.pump();
      expect(pickerCalls, 1);
      if (leaveWhileChoosing) operation.dispose();
      chosen.complete({'status': 'selected', 'documents': <Json>[]});
      await tester.pump();
      await work;
      if (!leaveWhileChoosing) {
        expect(operation.result?['status'], 'selected');
        operation.dispose();
      }
      expect(selections.complete('another-page', {}), isFalse);
      await events.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }

  for (final phase in [
    'initial admission',
    'source release',
    'failed source release',
  ]) {
    final hasPrevious = phase != 'initial admission';
    final releaseFails = phase == 'failed source release';
    testWidgets('page exit during $phase never starts a later picker', (
      tester,
    ) async {
      var imports = 0;
      final releasing = Completer<Json>();
      final operation = _documentOperation((
        command, [
        params = const {},
      ]) async {
        if (command == 'documents.importDirectory') {
          imports++;
          return {'status': 'imported', 'managedSourceId': 'document:first'};
        }
        if (command == 'documents.cancel' &&
            params['managedSourceId'] is String) {
          return releasing.future;
        }
        return {};
      });
      if (hasPrevious) await operation.run('documents.importDirectory', {});
      final selecting = operation.run('documents.importDirectory', {});
      if (hasPrevious) await tester.pump();
      operation.dispose();
      if (releaseFails) {
        releasing.completeError(
          const RequestFailure('release_failed', '来源归还尚未确认'),
        );
      } else {
        releasing.complete({});
      }
      await selecting;
      expect(imports, hasPrevious ? 1 : 0);
      if (releaseFails) {
        expect(operation.result?['managedSourceId'], 'document:first');
        expect(operation.error, contains('来源归还尚未确认'));
      }
    });
  }
  testWidgets('a failed late-result release retains its managed identity', (
    tester,
  ) async {
    final imported = Completer<Json>();
    final operation = _documentOperation((command, [params = const {}]) async {
      if (command == 'documents.importDirectory') return imported.future;
      if (command == 'documents.cancel' &&
          params['managedSourceId'] is String) {
        throw const RequestFailure('release_failed', '迟到来源归还尚未确认');
      }
      return {};
    });
    final selecting = operation.run('documents.importDirectory', {});
    await tester.pump();
    operation.dispose();
    imported.complete({
      'status': 'imported',
      'managedSourceId': 'document:late',
    });
    await selecting;
    expect(operation.result?['managedSourceId'], 'document:late');
    expect(operation.error, contains('迟到来源归还尚未确认'));
  });

  testWidgets(
    'a managed import result arriving after page disposal is returned',
    (tester) async {
      final reply = Completer<Json>();
      final released = <String>[];
      final operation = _documentOperation((
        command, [
        params = const {},
      ]) async {
        if (command == 'documents.importDirectory') return reply.future;
        if (command == 'documents.cancel' &&
            params['managedSourceId'] is String) {
          released.add(params['managedSourceId'] as String);
        }
        return {};
      });
      final importing = operation.run('documents.importDirectory', {});
      await tester.pump();
      operation.dispose();
      reply.complete({
        'managedSourceId': 'document:late',
        'status': 'imported',
      });
      await importing;
      expect(released, ['document:late']);
    },
  );
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
                : _unknownSave('actual-prior-save'),
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
          _exportPage(controller, localPath: '/cache/a', transferId: 'task'),
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
          _exportPage(
            controller,
            localPath: '/cache/original.png',
            transferId: 'source-task',
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
        _exportPage(controller, localPath: '/cache/original'),
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
                : _unknownSave('previous-system-write'),
          };
        }
        if (command == 'documents.export') {
          writes++;
          throw StateError('reply lost after provider write');
        }
        return {};
      });
      Widget page() => _exportPage(
        controller,
        localPath: '/private/cache/original.png',
        transferId: 'original-task',
      );
      try {
        await tester.pumpWidget(page());
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
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
        expect(writes, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
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
            'managedSourceId': 'document:source',
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
        'shareId': 'document:source',
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
        _exportPage(controller, localPath: '/private/cache/file'),
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
