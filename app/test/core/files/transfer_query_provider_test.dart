import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_changes_provider.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/transfer_query_provider.dart';

void main() {
  late _Transfers transfers;
  late StreamController<FileChange> changes;
  late ProviderContainer container;
  setUp(() {
    transfers = _Transfers();
    changes = StreamController<FileChange>.broadcast(sync: true);
    container = ProviderContainer(
      overrides: [
        fileTransfersProvider.overrideWithValue(transfers),
        fileChangesProvider.overrideWithValue(changes.stream),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await changes.close();
  });

  test('传输变化撤销已核验结果，迟到的旧查询不能覆盖新查询', () async {
    container.listen(transferHistoryProvider, (_, _) {});
    await _flush(container);
    for (var index = 0; index < 20; index++) {
      changes.add(const FileChange(FileChangeKind.transfer));
      await _flush(container);
    }
    expect(transfers.history, hasLength(1));
    transfers.history[0].complete(
      const FileTransferCollection(
        transfers: [FileTransferSnapshot(id: 'old')],
      ),
    );
    await _flush(container);
    expect(transfers.history, hasLength(2));
    expect(container.read(transferHistoryProvider).isLoading, isTrue);
    transfers.history[1].complete(
      const FileTransferCollection(
        transfers: [FileTransferSnapshot(id: 'new')],
      ),
    );
    await _flush(container);
    expect(
      container.read(transferHistoryProvider).requireValue.transfers.single.id,
      'new',
    );
    changes.add(const FileChange(FileChangeKind.recovery));
    expect(container.read(transferHistoryProvider).isLoading, isTrue);
    await _flush(container);
    transfers.history[2].complete(const FileTransferCollection());
  });

  test('详情必须匹配请求身份，失败不自动重试任务', () async {
    final provider = transferDetailsProvider('wanted');
    container.listen(provider, (_, _) {});
    await _flush(container);
    transfers.details.single.complete(const FileTransferSnapshot(id: 'other'));
    await _flush(container);
    expect(
      container.read(provider).error,
      isA<RequestFailure>().having(
        (error) => error.code,
        'code',
        'invalid_response',
      ),
    );
    await _flush(container);
    expect(transfers.details, hasLength(1));
  });

  test('能力替换后旧来源的回执不能覆盖新来源', () async {
    container.listen(transferHistoryProvider, (_, _) {});
    await _flush(container);
    final replacement = _Transfers();
    container.updateOverrides([
      fileTransfersProvider.overrideWithValue(replacement),
      fileChangesProvider.overrideWithValue(changes.stream),
    ]);
    await _flush(container);
    replacement.history.single.complete(
      const FileTransferCollection(
        transfers: [FileTransferSnapshot(id: 'replacement')],
      ),
    );
    await _flush(container);
    transfers.history.single.complete(
      const FileTransferCollection(
        transfers: [FileTransferSnapshot(id: 'previous')],
      ),
    );
    await _flush(container);
    expect(
      container.read(transferHistoryProvider).requireValue.transfers.single.id,
      'replacement',
    );
  });

  test('目录事件不触发传输查询，释放页面后停止接收传输事件', () async {
    final listener = container.listen(transferHistoryProvider, (_, _) {});
    await _flush(container);
    transfers.history.single.complete(const FileTransferCollection());
    await _flush(container);
    changes.add(const FileChange(FileChangeKind.directory));
    await _flush(container);
    expect(transfers.history, hasLength(1));
    listener.close();
    await _flush(container);
    expect(changes.hasListener, isFalse);
    changes.add(const FileChange(FileChangeKind.transfer));
    await _flush(container);
    expect(transfers.history, hasLength(1));
  });
}

class _Transfers implements FileTransfers {
  final history = <Completer<FileTransferCollection>>[];
  final details = <Completer<FileTransferSnapshot>>[];
  @override
  Future<FileTransferCollection> readTransfers() {
    final result = Completer<FileTransferCollection>();
    history.add(result);
    return result.future;
  }

  @override
  Future<FileTransferSnapshot> readTransfer(String id) {
    final result = Completer<FileTransferSnapshot>();
    details.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
}
