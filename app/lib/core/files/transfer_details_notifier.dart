import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/application_session_provider.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';

import 'file_transfer_query.dart';
import 'file_transfer_snapshot.dart';

part 'transfer_details_notifier.g.dart';

@riverpod
class TransferDetailsNotifier extends _$TransferDetailsNotifier {
  late FileTransferQuery<FileTransferSnapshot> _query;

  @override
  FileTransferQueryState<FileTransferSnapshot> build(String id) {
    final session = ref.watch(applicationSessionProvider);
    final source = session.dependencies.fileTransfers;
    final query = _query = FileTransferQuery(
      read: () async {
        final result = await source.readTransfer(id);
        if (result.id != id) {
          throw const RequestFailure('invalid_response', '传输回执不属于当前任务。');
        }
        return result;
      },
      current: () => state,
      update: (next) => state = next,
      events: session.events,
    );
    ref.onDispose(query.close);
    return const FileTransferQueryState();
  }

  Future<void> refresh() => _query.refresh();
}
