import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/files/models/document_event.dart';
import 'package:scrcpy_connect/core/files/models/document_selection.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:scrcpy_connect/widgets/documents/document_operation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.scrcpyconnect/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final leaveBeforeReply in [false, true]) {
    test('系统选择回执只交还原任务，离页=$leaveBeforeReply', () async {
      final platform = Completer<Map<String, Object?>>();
      final requested = Completer<MethodCall>();
      messenger.setMockMethodCallHandler(channel, (call) {
        requested.complete(call);
        return platform.future;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final events = StreamController<RuntimeEvent>.broadcast(sync: true);
      final documents = _Documents();
      final receipts =
          <({String operationId, DocumentSelectionResult result})>[];
      final controller = DocumentOperationController(
        documents: documents,
        events: events.stream,
        completeSelection: (id, result) {
          receipts.add((operationId: id, result: result));
          return true;
        },
      );
      addTearDown(() async {
        if (!controller.disposed) controller.dispose();
        if (!documents.result.isCompleted) {
          documents.result.complete(const DocumentOutcome(status: .cancelled));
        }
        await events.close();
      });
      final importing = controller.importDirectory();
      await Future<void>.delayed(Duration.zero);
      final id = controller.operationId!;
      expect(documents.operations, [id]);
      events.add(
        DocumentSelectionRequested(
          DocumentSelectionRequest(
            operationId: id,
            ownerLeaseId: 'original-owner',
            mode: .importDirectory,
          ),
        ).toApplicationEvent(),
      );
      final call = await requested.future;
      expect(call.method, 'documents.platform.picker');
      expect(call.arguments, {
        'operationId': id,
        'ownerLeaseId': 'original-owner',
        'mode': 'importDirectory',
      });
      if (leaveBeforeReply) {
        controller.dispose();
        expect(documents.cancelled, [id]);
      }
      platform.complete({
        'status': 'selected',
        'documents': [
          {'handle': 'original-document', 'uri': 'content://provider/document'},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      expect(receipts.single.operationId, id);
      if (leaveBeforeReply) {
        expect(receipts.single.result, isA<DocumentSelectionCancelled>());
      } else {
        final selected = receipts.single.result as DocumentLocationsSelected;
        expect(selected.documents.single.handle, 'original-document');
        expect(selected.documents.single.uri, 'content://provider/document');
        expect(() => selected.documents.clear(), throwsUnsupportedError);
      }
      documents.result.complete(const DocumentOutcome(status: .cancelled));
      await importing;
      expect(controller.error, isNull);
    });
  }
}

final class _Documents implements SystemDocuments {
  final operations = <String>[];
  final cancelled = <String>[];
  final result = Completer<DocumentOutcome>();

  @override
  Future<DocumentOutcome> importDocuments(
    String operationId,
    DocumentImportKind kind,
  ) {
    expect(kind, DocumentImportKind.directory);
    operations.add(operationId);
    return result.future;
  }

  @override
  Future<void> cancelDocument(String operationId) async =>
      cancelled.add(operationId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
