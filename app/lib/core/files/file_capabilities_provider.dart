import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'file_directories.dart';
import 'file_mutations.dart';
import 'file_search.dart';
import 'incoming_shares.dart';
import 'system_documents.dart';

import 'models/document_selection.dart';

import 'file_transfers.dart';

/// 每个功能入口可独立替换；运行时仍负责共享执行资源的关闭。
final fileDirectoriesProvider = Provider<FileDirectories>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final fileMutationsProvider = Provider<FileMutations>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final fileTransfersProvider = Provider<FileTransfers>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final fileSearchSourceProvider = Provider<FileSearch>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final incomingSharesProvider = Provider<IncomingShares>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);

final systemDocumentsProvider = Provider<SystemDocuments>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final documentSelectionResponderProvider =
    Provider<bool Function(String, DocumentSelectionResult)?>(
      (ref) => throw StateError('此能力须由启动装配提供。'),
    );
final transferCacheLeaseProvider = Provider<Future<String> Function(String)>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
