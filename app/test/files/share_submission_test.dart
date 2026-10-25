import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/files/file_executor.dart';
import 'package:scrcpy_connect/stores/files/transfer_coordinator.dart';

import 'support/file_executor_fixture.dart'
    show FixtureExecutor, regular, until;

final class _Publication implements FilePublicationLeases {
  @override
  Future<Set<String>> get sourcePaths async => {};

  final gate = Completer<void>();
  final started = Completer<void>();
  final finishStarted = Completer<void>();
  Completer<void>? finishing;
  final unpublished = <bool>[];
  final plannedTransfers = <String?>[];
  int starts = 0;
  int finishes = 0;
  bool fail = false;

  @override
  Future<Map<String, Object?>?> begin(
    String share,
    Map<String, Object?> request, {
    String? transferId,
  }) async {
    starts++;
    plannedTransfers.add(transferId);
    if (!started.isCompleted) started.complete();
    await gate.future;
    if (fail) throw const FileFailure('share_fixture_failure', '提交前失败。');
    return null;
  }

  @override
  Future<void> finish(
    String share,
    Map<String, Object?>? receipt, {
    bool definitelyUnpublished = false,
  }) async {
    finishes++;
    unpublished.add(definitelyUnpublished);
    if (!finishStarted.isCompleted) finishStarted.complete();
    await finishing?.future;
  }

  @override
  Future<Map<String, Object?>> reconcile(
    Map<String, Object?> durableReferences, {
    Set<String>? coveredSources,
  }) async => {'reconciled': true};
}

void main() {
  late Directory root;
  late _Publication publication;
  late TransferCoordinator owner;
  late FixtureExecutor executor;
  const request = {
    'deviceId': 'device',
    'shareId': 'share',
    'items': [
      {'source': '/source', 'destination': '/sdcard/new'},
    ],
  };

  Future<Map<String, Object?>> submit() => owner.submitShare(
    'device',
    const [
      {'source': '/source', 'destination': '/sdcard/new'},
    ],
    shareId: 'share',
    publicationRequest: request,
  );

  Matcher fileFailure(String code) =>
      isA<FileFailure>().having((error) => error.code, 'code', code);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('share-submission-');
    publication = _Publication();
    executor = FixtureExecutor()..stamps['/source'] = regular;
    owner = await TransferCoordinator.open(
      executor: executor,
      publication: publication,
      dataDirectory: root,
    );
  });
  tearDown(() async {
    if (!publication.gate.isCompleted) publication.gate.complete();
    final finishing = publication.finishing;
    if (finishing != null && !finishing.isCompleted) finishing.complete();
    await owner.close();
    await root.delete(recursive: true);
  });

  test('重复发送等待同一次发布，成功回执能够结束', () async {
    final first = owner.submitShare(
      'device',
      const [
        {'source': '/source', 'destination': '/sdcard/new'},
      ],
      shareId: 'share',
      publicationRequest: request,
    );
    final duplicate = owner.submitShare(
      'device',
      const [
        {'source': '/source', 'destination': '/sdcard/new'},
      ],
      shareId: 'share',
      publicationRequest: request,
    );
    await Future<void>.delayed(Duration.zero);
    expect(publication.starts, 1);
    publication.gate.complete();
    final receipts = await Future.wait([first, duplicate])
        .timeout(const Duration(seconds: 3));
    expect(publication.plannedTransfers.single, isNotNull);
    expect(receipts.first['batchId'], publication.plannedTransfers.single);
    expect(receipts.last, receipts.first);
    expect(publication.finishes, 1);
  });

  test('提交前失败能返回并释放在途登记，明确重试重新准入', () async {
    publication.fail = true;
    publication.gate.complete();
    await expectLater(
      owner
          .submitShare(
            'device',
            const [
              {'source': '/source', 'destination': '/sdcard/new'},
            ],
            shareId: 'share',
            publicationRequest: request,
          )
          .timeout(const Duration(seconds: 3)),
      throwsA(isA<FileFailure>()),
    );
    publication.fail = false;
    final receipt = await owner
        .submitShare(
          'device',
          const [
            {'source': '/source', 'destination': '/sdcard/new'},
          ],
          shareId: 'share',
          publicationRequest: request,
        )
        .timeout(const Duration(seconds: 3));
    expect(receipt['batchId'], isNotNull);
    expect(publication.starts, 2);
    expect(publication.finishes, 1);
  });

  for (final closing in [false, true]) {
    test('${closing ? '全局关闭' : '设备停止'}等待迟到来源和发布收尾，旧请求不启动传输', () async {
      publication.finishing = Completer<void>();
      final pending = submit();
      final cancelled = expectLater(pending, throwsA(fileFailure('cancelled')));
      await publication.started.future;
      var stopped = false;
      final stopping = (closing ? owner.close() : owner.cancelDevice('device'))
          .then((_) => stopped = true);
      await Future<void>.delayed(Duration.zero);
      expect(stopped, isFalse);
      expect(
        submit,
        throwsA(fileFailure(closing ? 'closed' : 'transfer_active')),
      );
      publication.gate.complete();
      await publication.finishStarted.future;
      expect(stopped, isFalse);
      expect(executor.calls, isEmpty);
      expect(owner.transfers()['transfers'], isEmpty);
      expect(publication.unpublished, [true]);
      publication.finishing!.complete();
      await cancelled;
      await stopping;
      expect(stopped, isTrue);
      expect(executor.calls, isEmpty);
      if (!closing) {
        publication.finishing = null;
        final receipt = await submit();
        await until(
          () =>
              owner.transfer(receipt['transferId'] as String)['status'] ==
              'completed',
        );
        expect(owner.transfers()['transfers'], hasLength(1));
        expect(publication.starts, 2);
      }
    });
  }

  test('来源登记失败时停止等待原错误结算，不伪造未发布回执', () async {
    final pending = submit();
    final failed = expectLater(
      pending,
      throwsA(fileFailure('share_fixture_failure')),
    );
    await publication.started.future;
    var stopped = false;
    final stopping = owner.cancelDevice('device').then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    publication.fail = true;
    publication.gate.complete();
    await failed;
    await stopping;
    expect(publication.finishes, 0);
    expect(executor.calls, isEmpty);
  });

  test('已登记传输的来源回执仍须结算，停止不抹去实际批次', () async {
    publication.gate.complete();
    publication.finishing = Completer<void>();
    final pending = submit();
    await publication.finishStarted.future;
    var stopped = false;
    final stopping = owner.cancelDevice('device').then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    publication.finishing!.complete();
    final receipt = await pending;
    await stopping;
    expect(
      owner.transfer(receipt['transferId'] as String)['batchId'],
      receipt['batchId'],
    );
    expect(publication.unpublished, [false]);
    expect(owner.transfers()['transfers'], hasLength(1));
  });

  test('停止只等待所属设备的分享，不阻止其他设备明确创建传输', () async {
    final pending = submit();
    final cancelled = expectLater(pending, throwsA(fileFailure('cancelled')));
    await publication.started.future;
    final stopping = owner.cancelDevice('device');
    final other = await owner.startTransfer('other', true, const [
      {'source': '/source', 'destination': '/sdcard/other'},
    ]);
    await until(
      () =>
          owner.transfer(other['transferId'] as String)['status'] ==
          'completed',
    );
    publication.gate.complete();
    await cancelled;
    await stopping;
    expect(
      (owner.transfers()['transfers'] as List).single['deviceId'],
      'other',
    );
  });
}
