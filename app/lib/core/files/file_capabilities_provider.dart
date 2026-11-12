import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'file_directories.dart';
import 'file_mutations.dart';
import 'file_search.dart';
import 'incoming_shares.dart';
import 'system_documents.dart';

import 'package:scrcpy_connect/core/errors/request_failure.dart' show Json;

import 'file_transfers.dart';

/// 每个功能入口可独立替换；运行时仍负责共享执行资源的关闭。
final fileDirectoriesProvider = Provider<FileDirectories>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.directories)),
);
final fileMutationsProvider = Provider<FileMutations>(
  (ref) =>
      ref.watch(appDependenciesProvider.select((app) => app.fileMutations)),
);
final fileTransfersProvider = Provider<FileTransfers>(
  (ref) =>
      ref.watch(appDependenciesProvider.select((app) => app.fileTransfers)),
);
final fileSearchSourceProvider = Provider<FileSearch>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.fileSearch)),
);
final incomingSharesProvider = Provider<IncomingShares>(
  (ref) =>
      ref.watch(appDependenciesProvider.select((app) => app.incomingShares)),
);

final systemDocumentsProvider = Provider<SystemDocuments>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.documents)),
);
final documentSelectionResponderProvider =
    Provider<bool Function(String, Json)?>(
      (ref) => ref.watch(
        appDependenciesProvider.select((app) => app.completeDocumentSelection),
      ),
    );
final transferCacheLeaseProvider = Provider<Future<String> Function(String)>(
  (ref) => ref.watch(
    appDependenciesProvider.select((app) => app.acquireTransferCacheLease),
  ),
);
