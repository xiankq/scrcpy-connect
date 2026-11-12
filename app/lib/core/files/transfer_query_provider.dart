import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/queries/coalesced_query.dart';

import 'file_capabilities_provider.dart';
import 'file_changes_provider.dart';
import 'models/file_transfer_snapshot.dart';

part 'transfer_query_provider.g.dart';

Duration? _noRetry(int retryCount, Object error) => null;

CoalescedQuery<T> _observeChanges<T>(Ref ref, Future<T> Function() read) {
  final query = CoalescedQuery(
    read,
    invalidations: ref
        .watch(fileChangesProvider)
        .where((event) => event.kind != FileChangeKind.directory),
  );
  ref.onDispose(() => unawaited(query.close()));
  return query;
}

// 查询 Future 可随事件失效，执行所有者持续到最后订阅释放，合并在途刷新。
final _historyReadProvider = Provider.autoDispose((ref) {
  final transfers = ref.watch(fileTransfersProvider);
  return _observeChanges(ref, transfers.readTransfers);
});

final _detailsReadProvider = Provider.autoDispose.family((ref, String id) {
  final transfers = ref.watch(fileTransfersProvider);
  return _observeChanges(ref, () async {
    final result = await transfers.readTransfer(id);
    if (result.id != id) {
      throw const RequestFailure('invalid_response', '传输回执不属于当前任务。');
    }
    return result;
  });
});

final _historyRevisionProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(_historyReadProvider).changes,
);

final _detailsRevisionProvider = StreamProvider.autoDispose.family(
  (ref, String id) => ref.watch(_detailsReadProvider(id)).changes,
);

@Riverpod(retry: _noRetry)
Future<FileTransferCollection> transferHistory(Ref ref) {
  final query = ref.watch(_historyReadProvider);
  ref.watch(_historyRevisionProvider);
  return query.read();
}

@Riverpod(retry: _noRetry)
Future<FileTransferSnapshot> transferDetails(Ref ref, String id) {
  final query = ref.watch(_detailsReadProvider(id));
  ref.watch(_detailsRevisionProvider(id));
  return query.read();
}
