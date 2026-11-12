import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:scrcpy_connect/core/files/models/document_event.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/documents/document_conflict_panel.dart';

void main() {
  testWidgets('换源取消原保存操作，迟到的同名冲突决策不清除新来源提示', (tester) async {
    final previous = _Documents();
    final replacement = _Documents();
    final events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    final container = ProviderContainer(
      overrides: [
        systemDocumentsProvider.overrideWithValue(previous),
        runtimeEventsProvider.overrideWithValue(events.stream),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(events.close);
    await tester.pumpWidget(_page(container));
    previous.reads.single.complete(_conflict('previous'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留两份'));
    await tester.pump();
    expect(previous.decisions, hasLength(1));
    container.updateOverrides([
      systemDocumentsProvider.overrideWithValue(replacement),
      runtimeEventsProvider.overrideWithValue(events.stream),
    ]);
    await tester.pump();
    expect(previous.cancelled, ['operation']);
    replacement.reads.single.complete(_conflict('replacement'));
    await tester.pumpAndSettle();
    // Identical operation and conflict IDs deliberately exercise the owner generation.
    previous.decisions.single.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('replacement'), findsOneWidget);
    expect(find.text('previous'), findsNothing);
    expect(replacement.cancelled, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(replacement.cancelled, ['operation']);
    expect(events.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('权威冲突事件先于初次读取，旧读取不能恢复已解决的提示', (tester) async {
    final documents = _Documents();
    final events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    final container = ProviderContainer(
      overrides: [
        systemDocumentsProvider.overrideWithValue(documents),
        runtimeEventsProvider.overrideWithValue(events.stream),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(events.close);
    await tester.pumpWidget(_page(container));
    events.add(
      DocumentConflictChanged(
        'operation',
        _conflict('current'),
      ).toApplicationEvent(),
    );
    await tester.pumpAndSettle();
    expect(find.text('current'), findsOneWidget);
    events.add(
      const DocumentConflictChanged('operation', null).toApplicationEvent(),
    );
    documents.reads.single.complete(_conflict('retired'));
    await tester.pumpAndSettle();
    expect(find.text('current'), findsNothing);
    expect(find.text('retired'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(documents.cancelled, ['operation']);
    expect(tester.takeException(), isNull);
  });
}

Widget _page(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: ConnectTokens.theme(Brightness.light),
    home: const Scaffold(body: DocumentConflictPanel(operationId: 'operation')),
  ),
);

DocumentConflict _conflict(String name) => DocumentConflict(
  operationId: 'operation',
  conflictId: 'conflict',
  name: name,
);

class _Documents implements SystemDocuments {
  final reads = <Completer<DocumentConflict?>>[];
  final decisions = <Completer<bool>>[];
  final cancelled = <String>[];
  @override
  Future<DocumentConflict?> readDocumentConflict(String operationId) {
    final result = Completer<DocumentConflict?>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<bool> resolveDocumentConflict(
    String operationId,
    String conflictId,
    DocumentConflictDecision decision, {
    bool applyToRemaining = false,
  }) {
    final result = Completer<bool>();
    decisions.add(result);
    return result.future;
  }

  @override
  Future<void> cancelDocument(String operationId) async =>
      cancelled.add(operationId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
