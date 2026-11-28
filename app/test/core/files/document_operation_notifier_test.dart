import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/document_operation_notifier.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/models/document_event.dart';
import 'package:scrcpy_connect/core/files/models/document_selection.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';

import '../../support/fixed_state.dart';

const _source = DocumentSource(
  sourceId: 'transfer:original',
  localPath: '/cache/original.bin',
  kind: .file,
);

void main() {
  late _Documents documents;
  late StreamController<RuntimeEvent> events;
  late ProviderContainer container;
  late List<({String id, DocumentSelectionResult result})> replies;

  setUp(() {
    documents = _Documents();
    events = StreamController<RuntimeEvent>.broadcast(sync: true);
    replies = [];
    container = ProviderContainer(
      overrides: [
        systemDocumentsProvider.overrideWithValue(documents),
        runtimeEventsProvider.overrideWithValue(events.stream),
        documentSelectionResponderProvider.overrideWithValue((id, result) {
          replies.add((id: id, result: result));
          return true;
        }),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await events.close();
  });

  test('同表单只提交一次，重选先归还旧来源，离页归还最后来源', () async {
    final scope = Object();
    final provider = documentOperationProvider(scope: scope);
    final subscription = container.listen(provider, (_, _) {});
    final actions = container.read(provider.notifier);
    final first = actions.importDirectory();
    await flushProviders(container);
    await actions.importDirectory();
    expect(documents.imports, hasLength(1));
    documents.imports.single.result.complete(_imported('first'));
    await first;
    final second = actions.importDirectory();
    await flushProviders(container);
    expect(documents.released, ['first']);
    expect(documents.imports, hasLength(2));
    documents.imports.last.result.complete(_imported('second'));
    await second;
    expect(container.read(provider).result?.managedSourceId, 'second');
    subscription.close();
    await flushProviders(container);
    expect(documents.released, ['first', 'second']);
  });

  test('旧来源归还失败时保留结果并阻止重选，重试成功后才开始读取', () async {
    final scope = Object();
    final provider = documentOperationProvider(scope: scope);
    container.listen(provider, (_, _) {});
    final actions = container.read(provider.notifier);
    final first = actions.importDirectory();
    await flushProviders(container);
    documents.imports.single.result.complete(_imported('retained'));
    await first;
    documents.releaseFailure = StateError('release failed');
    await actions.importDirectory();
    expect(documents.imports, hasLength(1));
    expect(container.read(provider).result?.managedSourceId, 'retained');
    expect(container.read(provider).error, contains('上次选择的文件仍在使用'));
    expect(container.read(provider).busy, isFalse);
    documents.releaseFailure = null;
    final retry = actions.importDirectory();
    await flushProviders(container);
    expect(documents.released, ['retained', 'retained']);
    expect(documents.imports, hasLength(2));
    documents.imports.last.result.complete(
      const DocumentOutcome(status: .cancelled),
    );
    await retry;
    expect(container.read(provider).error, isNull);
  });

  test('能力换源取消原操作，旧选择和迟到来源只交给原所有者', () async {
    final scope = Object();
    final provider = documentOperationProvider(scope: scope);
    container.listen(provider, (_, _) {});
    final actions = container.read(provider.notifier);
    final original = actions.importDirectory();
    final originalScope = actions.captureScope();
    await flushProviders(container);
    final id = documents.imports.single.id;
    final selection = DocumentSelectionRequest(
      operationId: id,
      mode: .importDirectory,
    );
    final reply = actions.claimSelection(selection)!;
    expect(actions.claimSelection(selection), isNull);
    final previous = documents;
    documents = _Documents();
    container.updateOverrides([
      systemDocumentsProvider.overrideWithValue(documents),
      runtimeEventsProvider.overrideWithValue(events.stream),
      documentSelectionResponderProvider.overrideWithValue((id, result) {
        fail('旧选择不得交给新响应者');
      }),
    ]);
    await flushProviders(container);
    expect(originalScope(), isFalse);
    expect(previous.cancelled, [id]);
    final next = container.read(provider.notifier).importDirectory();
    await flushProviders(container);
    reply(
      DocumentLocationsSelected([
        const SelectedDocument(handle: 'old', uri: 'content://old'),
      ]),
    );
    expect(replies.single.id, id);
    expect(replies.single.result, isA<DocumentSelectionCancelled>());
    previous.imports.single.result.complete(_imported('late'));
    await original;
    expect(previous.released, ['late']);
    expect(documents.released, isEmpty);
    expect(container.read(provider).busy, isTrue);
    documents.imports.single.result.complete(_imported('current'));
    await next;
    expect(container.read(provider).result?.managedSourceId, 'current');
  });

  test('取消先撤销系统选择准入，迟到位置不能继续本次操作', () async {
    final scope = Object();
    final provider = documentOperationProvider(scope: scope);
    container.listen(provider, (_, _) {});
    final actions = container.read(provider.notifier);
    final importing = actions.importDirectory();
    await flushProviders(container);
    final id = documents.imports.single.id;
    final reply = actions.claimSelection(
      DocumentSelectionRequest(operationId: id, mode: .importDirectory),
    )!;
    await actions.cancel();
    reply(const DocumentDestinationSelected('/must-not-write'));
    expect(documents.cancelled, [id]);
    expect(replies.single.result, isA<DocumentSelectionCancelled>());
    documents.imports.single.result.complete(
      const DocumentOutcome(status: .cancelled),
    );
    await importing;
    expect(container.read(provider).busy, isFalse);
    expect(container.read(provider).cancelling, isFalse);
  });

  test('保存先回读账本，较早读取不能覆盖新记录；核对与额外副本引用原记录', () async {
    final scope = Object();
    final provider = documentOperationProvider(
      scope: scope,
      exportSource: _source,
    );
    container.listen(provider, (_, _) {});
    final actions = container.read(provider.notifier);
    await flushProviders(container);
    await actions.export('blocked');
    expect(documents.exports, isEmpty);
    events.add(const DocumentDeliveryChanged(_source).toApplicationEvent());
    await flushProviders(container);
    documents.reads.last.complete(
      const FileDeliveryRecord(
        operationId: 'current',
        name: 'original.bin',
        status: .resultUnknown,
      ),
    );
    await flushProviders(container);
    documents.reads.first.complete(
      const FileDeliveryRecord(
        operationId: 'stale',
        name: 'original.bin',
        status: .pending,
      ),
    );
    await flushProviders(container);
    expect(container.read(provider).recordOperationId, 'current');
    expect(container.read(provider).refreshing, isFalse);
    final saving = actions.export('original.bin', reviewed: true);
    await flushProviders(container);
    expect(documents.exports.single.plan.reviewedOperationId, 'current');
    documents.exports.single.result.complete(
      const DocumentOutcome(status: .saved),
    );
    await saving;
    final additional = actions.export('copy.bin', additionalCopy: true);
    await flushProviders(container);
    expect(
      documents.exports.last.plan.additionalCopyOfOperationId,
      documents.exports.first.plan.operationId,
    );
    documents.exports.last.result.complete(
      const DocumentOutcome(status: .cancelled),
    );
    await additional;
  });

  test('恢复的待保存操作离页也交回取消', () async {
    final scope = Object();
    final provider = documentOperationProvider(
      scope: scope,
      exportSource: _source,
    );
    final subscription = container.listen(provider, (_, _) {});
    await flushProviders(container);
    documents.reads.single.complete(
      const FileDeliveryRecord(
        operationId: 'pending',
        name: 'original.bin',
        status: .pending,
      ),
    );
    await flushProviders(container);
    subscription.close();
    await flushProviders(container);
    expect(documents.cancelled, ['pending']);
  });
}

DocumentOutcome _imported(String source) => DocumentOutcome(
  status: .imported,
  managedSourceId: source,
  localPath: '/cache/$source',
);

final class _Documents implements SystemDocuments {
  final imports = <({String id, Completer<DocumentOutcome> result})>[];
  final exports =
      <({DocumentExportPlan plan, Completer<DocumentOutcome> result})>[];
  final reads = <Completer<FileDeliveryRecord?>>[];
  final released = <String>[];
  final cancelled = <String>[];
  Object? releaseFailure;

  @override
  Future<DocumentOutcome> importDocuments(
    String operationId,
    DocumentImportKind kind,
  ) {
    final result = Completer<DocumentOutcome>();
    imports.add((id: operationId, result: result));
    return result.future;
  }

  @override
  Future<DocumentOutcome> exportDocument(DocumentExportPlan plan) {
    final result = Completer<DocumentOutcome>();
    exports.add((plan: plan, result: result));
    return result.future;
  }

  @override
  Future<FileDeliveryRecord?> readDelivery(DocumentSource source) {
    final result = Completer<FileDeliveryRecord?>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<void> releaseDocumentSource(String source) async {
    released.add(source);
    if (releaseFailure case final failure?) throw failure;
  }

  @override
  Future<void> cancelDocument(String id) async => cancelled.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
