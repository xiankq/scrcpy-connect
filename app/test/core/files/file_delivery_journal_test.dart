import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_delivery.dart';
import 'package:scrcpy_connect/core/files/file_delivery_journal.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('delivery-records-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test('重开 pending 为未知并继续保护原件，明确核对后才允许新操作', () async {
    final journal = await FileDeliveryJournal.open(root);
    await journal.begin(_plan('first'));
    expect(await journal.protectedPaths, [_source.localPath]);
    final reopened = await FileDeliveryJournal.open(root);
    final record = (await reopened.read(_source))!;
    expect(record.status, DocumentOutcomeStatus.resultUnknown);
    expect(record.result!.partialDestinationPossible, isTrue);
    expect(await reopened.protectedPaths, [_source.localPath]);
    await expectLater(
      reopened.begin(_plan('second')),
      _failure('delivery_review_required'),
    );
    await reopened.begin(
      FileDeliveryPlan(
        operationId: 'second',
        source: _source,
        name: '原件',
        reviewedOperationId: 'first',
      ),
    );
    await expectLater(
      reopened.finish(_plan('first'), const DocumentOutcome(status: .saved)),
      _failure('delivery_operation_mismatch'),
    );
    await reopened.finish(
      _plan('second'),
      const DocumentOutcome(status: .saved),
    );
    expect(await reopened.protectedPaths, isEmpty);
    expect(
      (await (await FileDeliveryJournal.open(root)).read(_source))!.status,
      DocumentOutcomeStatus.saved,
    );
  });

  test('终态重复回执幂等，未知结果与有界错误在重开后保留', () async {
    final journal = await FileDeliveryJournal.open(root);
    final plan = _plan('first');
    await journal.begin(plan);
    final errors = List.generate(
      102,
      (_) => DocumentIssue(message: '字' * 2000),
    );
    final outcome = DocumentOutcome(
      status: .resultUnknown,
      errors: errors,
      partialDestinationPossible: false,
      cacheRetained: true,
    );
    final first = await journal.finish(plan, outcome);
    expect(first.result!.partialDestinationPossible, isTrue);
    expect(first.result!.errors, hasLength(100));
    expect(
      utf8.encode(first.result!.errors.first.message).length,
      lessThanOrEqualTo(4096),
    );
    expect((await journal.finish(plan, outcome)).result, first.result);
    await expectLater(
      journal.finish(plan, const DocumentOutcome(status: .saved)),
      _failure('delivery_result_conflict'),
    );
    final reopened = await FileDeliveryJournal.open(root);
    expect((await reopened.read(_source))!.result, first.result);
    expect(await reopened.protectedPaths, [_source.localPath]);
  });

  test('兼容既有 v1 无错误列表回执，损坏记录拒绝打开并保留文件', () async {
    final key = jsonEncode([_source.sourceId, _source.localPath, 'file']);
    final raw = {
      'version': 1,
      'operations': ['first'],
      'records': {
        key: {
          'operationId': 'first',
          ..._source.toJson(),
          'name': '原件',
          'status': 'saved',
          'result': {'status': 'saved'},
          'updatedAt': 1,
        },
      },
    };
    final file = File('${root.path}/deliveries.json');
    await file.writeAsString(jsonEncode(raw));
    final journal = await FileDeliveryJournal.open(root);
    expect((await journal.read(_source))!.status, DocumentOutcomeStatus.saved);
    expect(await journal.protectedPaths, isEmpty);
    await journal.begin(
      FileDeliveryPlan(
        operationId: 'second',
        source: _source,
        name: '副本',
        additionalCopyOfOperationId: 'first',
      ),
    );
    // 损坏不能当成新账本、也不能删除旧日志。
    await file.writeAsString('{broken');
    await expectLater(
      FileDeliveryJournal.open(root),
      _failure('delivery_storage_invalid'),
    );
    expect(await file.readAsString(), '{broken');
  });
}

const _source = DocumentSource(
  sourceId: 'local',
  localPath: '/cached/file',
  kind: .file,
);
FileDeliveryPlan _plan(String operation) =>
    FileDeliveryPlan(operationId: operation, source: _source, name: '原件');
Matcher _failure(String code) =>
    throwsA(isA<RequestFailure>().having((e) => e.code, '失败原因', code));
