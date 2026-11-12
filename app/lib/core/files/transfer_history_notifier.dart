import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/application_session_provider.dart';

import 'file_transfer_query.dart';
import 'file_transfer_snapshot.dart';

part 'transfer_history_notifier.g.dart';

@riverpod
class TransferHistoryNotifier extends _$TransferHistoryNotifier {
  late FileTransferQuery<FileTransferCollection> _query;

  @override
  FileTransferQueryState<FileTransferCollection> build() {
    final session = ref.watch(applicationSessionProvider);
    final query = _query = FileTransferQuery(
      read: session.dependencies.fileTransfers.readTransfers,
      current: () => state,
      update: (next) => state = next,
      events: session.events,
    );
    ref.onDispose(query.close);
    return const FileTransferQueryState();
  }

  Future<void> refresh() => _query.refresh();
}
