import 'package:path/path.dart' as p;

import 'package:scrcpy_connect/files/catalog/file_catalog.dart';
import 'package:scrcpy_connect/files/catalog/file_paths.dart';
import 'package:scrcpy_connect/files/execution/file_executor.dart';
import 'package:scrcpy_connect/files/mutations/file_mutation_coordinator.dart';
import 'package:scrcpy_connect/files/transfers/transfer_coordinator.dart';

/// 将应用命令字段映射到实际文件所有者，不持有任务、连接或清理资源。
final class FileCommands {
  FileCommands({
    required this.catalog,
    required this.mutations,
    required this.transfers,
  });

  final FileCatalog catalog;
  final FileMutationCoordinator mutations;
  final TransferCoordinator transfers;

  Future<Map<String, Object?>?> invoke(
    String command,
    Map<String, Object?> params,
  ) async {
    String device() => switch (params['deviceId']) {
      final String value => value,
      null => '',
      _ => throw const FileFailure('invalid_argument', '设备标识必须为字符串。'),
    };
    switch (command) {
      case 'media.cache.acquire':
        return {
          'leaseId': await transfers.acquireCacheLease(
            params['transferId']! as String,
          ),
        };
      case 'files.list':
        return catalog.browse(
          device(),
          params['path'] as String? ?? '/sdcard',
          filter: params['filter'] as String? ?? 'all',
          sort: params['sort'] as String? ?? 'name',
          descending: params['descending'] == true,
          offset: params['offset'] as int? ?? 0,
          limit: params['limit'] as int? ?? 10000,
        );
      case 'files.search.start':
        return catalog.startSearch(
          device(),
          params['path']! as String,
          query: params['query']! as String,
          filter: params['filter'] as String? ?? 'all',
        );
      case 'files.search.get':
        return catalog.scan(
          device(),
          params['searchId']! as String,
          offset: params['offset'] as int? ?? 0,
          limit: params['limit'] as int? ?? 500,
        );
      case 'files.search.cancel':
        return catalog.cancelScan(device(), params['searchId']! as String);
      case 'media.list':
        final id = params['scanId'] as String?;
        if (id == null || params['refresh'] == true) {
          return catalog.startSearch(
            device(),
            '/sdcard',
            query: '',
            gallery: true,
          );
        }
        return catalog.scan(
          device(),
          id,
          offset: params['offset'] as int? ?? 0,
          limit: params['limit'] as int? ?? 100,
        );
      case 'media.scan.cancel':
        return catalog.cancelScan(device(), params['scanId']! as String);
      case 'files.push':
      case 'files.pull':
        final selections = (params['items'] as List? ?? [params]).map((item) {
          final selection = Map<String, Object?>.from(item as Map);
          selection['source'] ??= selection['path'];
          return selection;
        }).toList();
        final policy =
            params['conflict'] as String? ??
            params['policy'] as String? ??
            'ask';
        final scope = params['destinationScope'] as String? ?? 'localPath';
        final share = params['shareId'] as String?;
        if (command == 'files.push' && share != null) {
          return transfers.submitShare(
            device(),
            selections,
            shareId: share,
            publicationRequest: params,
            policy: policy,
            destinationScope: scope,
          );
        }
        return transfers.startTransfer(
          device(),
          command == 'files.push',
          selections,
          policy: policy,
          destinationScope: scope,
          shareId: share,
        );
      case 'sharing.reconcile':
        if (transfers.publication != null && params['transfers'] == null) {
          return transfers.reconcileShares();
        }
        return null;
      case 'transfers.list':
        return transfers.transfers();
      case 'transfers.get':
        return transfers.transfer(params['transferId']! as String);
      case 'transfers.cancel':
        if (params['batchId'] is String) {
          return transfers.cancelBatch(params['batchId']! as String);
        }
        return transfers.cancelTransfer(params['transferId']! as String);
      case 'transfers.resolve':
      case 'transfers.resume':
        final id = params['transferId']! as String;
        return transfers.resolveTransfer(
          id,
          params['policy'] as String? ??
              params['conflict'] as String? ??
              (transfers.transfer(id)['policy'] as String? ?? 'ask'),
          restart: params['restart'] == true,
          applyToAll: params['applyToAll'] == true,
        );
      case 'transfers.remove':
        return transfers.removeTransfer(
          (params['batchId'] ?? params['transferId'])! as String,
          batch: params['batchId'] is String,
        );
      case 'files.mkdir':
        await mutations.createDirectory(device(), params['path']! as String);
        return {'ok': true};
      case 'files.rename':
        final path = params['path']! as String;
        await mutations.rename(
          device(),
          path,
          destination:
              params['destination'] as String? ??
              params['newPath'] as String? ??
              (params['name'] is String
                  ? p.posix.join(
                      p.posix.dirname(path),
                      FilePaths.name(params['name']! as String),
                    )
                  : ''),
        );
        return {'ok': true};
      case 'files.delete':
        await mutations.delete(
          device(),
          (params['paths']! as List).cast<String>(),
        );
        return {'ok': true};
      default:
        return null;
    }
  }
}
