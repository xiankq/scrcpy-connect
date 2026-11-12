import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_delivery.dart';
import 'package:scrcpy_connect/core/files/system_document_backend.dart';
import 'package:scrcpy_connect/core/files/system_document_service.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:scrcpy_connect/core/files/models/document_selection.dart';

void main() {
  test('查询、取消、迟到选择与空关闭都不创建执行端', () async {
    final service = SystemDocumentService(
      deliveries: _Records(),
      createBackend: (_) => throw StateError('未使用功能不应创建执行端'),
      allowImport: true,
      isDisposed: () => false,
      onChanged: (_) {},
    );
    expect(await service.readDelivery(_source), isNull);
    expect(await service.readDocumentConflict('unused'), isNull);
    expect(
      await service.resolveDocumentConflict('unused', 'conflict', .cancel),
      isFalse,
    );
    expect(
      service.completeSelection('unused', const DocumentSelectionCancelled()),
      isFalse,
    );
    await service.cancelDocument('unused');
    await service.close();
    await service.close();
    expect(
      () => service.importDocuments('late', .files),
      throwsA(isA<RequestFailure>()),
    );
  });

  test('关闭等待系统执行结束及交付回执持久化', () async {
    final backend = _Backend();
    final records = _Records()..persist = Completer<void>();
    var creations = 0;
    final service = SystemDocumentService(
      deliveries: records,
      createBackend: (_) {
        creations++;
        return backend;
      },
      allowImport: true,
      isDisposed: () => false,
      onChanged: (_) {},
    );
    final saving = service.exportDocument(_plan);
    await backend.started.future;
    var closed = false;
    final closing = service.close().then((_) => closed = true);
    await records.finishing.future;
    expect(backend.disposals, 1);
    expect(closed, isFalse);
    records.persist!.complete();
    await closing;
    expect((await saving).status, DocumentOutcomeStatus.cancelled);
    await service.close();
    expect(creations, 1);
    expect(backend.disposals, 1);
  });

  test('准入记录尚未完成时关闭，取消导出且不创建执行端', () async {
    final records = _Records()..admit = Completer<void>();
    final service = SystemDocumentService(
      deliveries: records,
      createBackend: (_) => throw StateError('关闭后不应再创建执行端'),
      allowImport: true,
      isDisposed: () => false,
      onChanged: (_) {},
    );
    final saving = service.exportDocument(_plan);
    var closed = false;
    final closing = service.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    records.admit!.complete();
    expect((await saving).status, DocumentOutcomeStatus.cancelled);
    await closing;
  });

  test('清理失败保留原执行端，关闭重试不重新装配', () async {
    final backend = _Backend()..failClose = true;
    var creations = 0;
    final service = SystemDocumentService(
      deliveries: _Records(),
      createBackend: (_) {
        creations++;
        return backend;
      },
      allowImport: true,
      isDisposed: () => false,
      onChanged: (_) {},
    );
    await service.importDocuments('import', .files);
    await expectLater(service.close(), throwsStateError);
    await service.close();
    expect(backend.disposals, 2);
    expect(creations, 1);
  });
}

const _source = DocumentSource(
  sourceId: 'source',
  localPath: '/cached/file',
  kind: .file,
);
const _plan = DocumentExportPlan(
  operationId: 'export',
  source: _source,
  name: 'file',
);
const _cancelled = DocumentOutcome(status: .cancelled, cacheRetained: true);

class _Records implements FileDeliveryRecords {
  Completer<void>? admit, persist;
  final finishing = Completer<void>();
  @override
  Future<void> begin(FileDeliveryPlan plan) async => await admit?.future;
  @override
  Future<FileDeliveryRecord?> read(DocumentSource source) async => null;
  @override
  Future<FileDeliveryRecord> finish(
    FileDeliveryPlan plan,
    DocumentOutcome result,
  ) async {
    finishing.complete();
    await persist?.future;
    return FileDeliveryRecord(
      operationId: plan.operationId,
      name: plan.name,
      status: result.status,
      result: result,
    );
  }
}

class _Backend implements SystemDocumentBackend {
  int disposals = 0;
  bool failClose = false;
  final started = Completer<void>();
  final result = Completer<DocumentOutcome>();
  @override
  Future<DocumentOutcome> exportDocument(DocumentExportPlan plan) {
    started.complete();
    return result.future;
  }

  @override
  Future<DocumentOutcome> importDocuments(
    String operationId,
    DocumentImportKind kind,
  ) async => _cancelled;
  @override
  Future<void> dispose() async {
    disposals++;
    if (failClose) {
      failClose = false;
      throw StateError('cleanup unconfirmed');
    }
    if (!result.isCompleted) result.complete(_cancelled);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
