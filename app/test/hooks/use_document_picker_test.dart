import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/document_operation_notifier.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/models/document_event.dart';
import 'package:scrcpy_connect/core/files/models/document_selection.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:scrcpy_connect/hooks/use_document_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.scrcpyconnect/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final leaveBeforeReply in [false, true]) {
    testWidgets('系统选择回执只交还原任务，离页=$leaveBeforeReply', (tester) async {
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
      final scope = Object();
      final provider = documentOperationProvider(scope: scope);
      final container = ProviderContainer(
        overrides: [
          systemDocumentsProvider.overrideWithValue(documents),
          runtimeEventsProvider.overrideWithValue(events.stream),
          documentSelectionResponderProvider.overrideWithValue((id, result) {
            receipts.add((operationId: id, result: result));
            return true;
          }),
        ],
      );
      addTearDown(() async {
        container.dispose();
        if (!documents.result.isCompleted) {
          documents.result.complete(const DocumentOutcome(status: .cancelled));
        }
        await events.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _PickerView(scope: scope),
        ),
      );
      final actions = container.read(provider.notifier);
      final importing = actions.importDirectory();
      await tester.pump();
      final id = container.read(provider).operationId!;
      expect(documents.operations, [id]);
      expect(documents.kinds, [DocumentImportKind.directory]);
      events.add(
        DocumentSelectionRequested(
          DocumentSelectionRequest(
            operationId: id,
            ownerLeaseId: 'original-owner',
            mode: .importDirectory,
          ),
        ).toApplicationEvent(),
      );
      await tester.pump();
      final call = await requested.future;
      expect(call.method, 'documents.platform.picker');
      expect(call.arguments, {
        'operationId': id,
        'ownerLeaseId': 'original-owner',
        'mode': 'importDirectory',
      });
      if (leaveBeforeReply) {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const SizedBox.shrink(),
          ),
        );
        await tester.pump();
        expect(documents.cancelled, [id]);
      }
      platform.complete({
        'status': 'selected',
        'documents': [
          {'handle': 'original-document', 'uri': 'content://provider/document'},
        ],
      });
      await tester.pump();
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
      await tester.pump();
      await importing;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

class _PickerView extends HookConsumerWidget {
  const _PickerView({required this.scope});
  final Object scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = documentOperationProvider(scope: scope);
    ref.watch(provider);
    useDocumentPicker(ref, ref.read(provider.notifier));
    return const SizedBox.shrink();
  }
}

final class _Documents implements SystemDocuments {
  final operations = <String>[];
  final kinds = <DocumentImportKind>[];
  final cancelled = <String>[];
  final result = Completer<DocumentOutcome>();

  @override
  Future<DocumentOutcome> importDocuments(
    String operationId,
    DocumentImportKind kind,
  ) {
    kinds.add(kind);
    operations.add(operationId);
    return result.future;
  }

  @override
  Future<void> cancelDocument(String operationId) async =>
      cancelled.add(operationId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
