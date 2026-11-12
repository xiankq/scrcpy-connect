import 'dart:async';
import 'dart:io';

import 'package:adb/adb.dart' show AdbServices;
import 'package:scrcpy/scrcpy.dart'
    show createNativeScrcpyLocalFiles, readNativeScrcpyLocalStorageFreeBytes;
import 'package:scrcpy_connect/core/content/content_cache.dart';
import 'package:scrcpy_connect/core/content/content_cache_gate.dart';
import 'package:scrcpy_connect/core/content/content_preview.dart';
import 'package:scrcpy_connect/core/content/thumbnail_job_service.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/adb_file_executor.dart';
import 'package:scrcpy_connect/core/files/file_catalog.dart';
import 'package:scrcpy_connect/core/files/file_delivery_journal.dart';
import 'package:scrcpy_connect/core/files/file_document_cache.dart';
import 'package:scrcpy_connect/core/files/file_document_scope.dart';
import 'package:scrcpy_connect/core/files/file_mutation_service.dart';
import 'package:scrcpy_connect/core/files/file_operations.dart';
import 'package:scrcpy_connect/core/files/file_publication_lease_pool.dart';
import 'package:scrcpy_connect/core/files/file_share_service.dart';
import 'package:scrcpy_connect/core/files/file_transfer_service.dart';
import 'package:scrcpy_connect/core/platform/app_platform.dart';
import 'package:scrcpy_connect/core/platform/native_host.dart';
import 'package:scrcpy_connect/utils/ordered_disposal.dart';

/// 文件、缓存、分享和远端缩略图任务的资源所有者。
/// 恢复持久任务是启动工作；目录、搜索、预览在第一次使用时创建。
final class FileResources {
  FileResources._({
    required this.transfers,
    required this.cache,
    required this.deliveries,
    required this.sharing,
    required this.documentSources,
    required this._executor,
    required this.isDisposed,
    required this.isStateUnverified,
    required this.diagnostics,
    required this.requireConnection,
    required this.request,
    required this.emit,
    required this.attachCatalogEvents,
  });

  final FileTransferService transfers;
  final ContentCache cache;
  final FileDeliveryJournal deliveries;
  final FileShareService? sharing;
  final FileDocumentCache? documentSources;
  final AdbFileExecutor _executor;
  final bool Function() isDisposed;
  final bool Function() isStateUnverified;
  final DiagnosticReporter diagnostics;
  final DeviceConnection Function(String) requireConnection;
  final ThumbnailJobRequest Function() request;
  final void Function(Map<String, dynamic>) emit;
  final void Function(Stream<Map<String, dynamic>>) attachCatalogEvents;
  bool _closed = false;
  FileCatalog? _catalog;
  FileMutationService? _mutations;
  ContentPreview? _content;
  ThumbnailJobService? _jobs;
  FileOperations? _operations;

  void _checkOpen() {
    if (_closed || isDisposed()) {
      throw const RequestFailure('disposed', '文件能力已关闭。');
    }
  }

  FileCatalog get _fileCatalog {
    _checkOpen();
    if (_catalog case final existing?) return existing;
    final catalog = FileCatalog(_executor);
    _catalog = catalog;
    attachCatalogEvents(catalog.events);
    return catalog;
  }

  ThumbnailJobService get jobs {
    _checkOpen();
    return _jobs ??= ThumbnailJobService(
      requireConnection: requireConnection,
      request: request(),
    );
  }

  ContentPreview get content {
    _checkOpen();
    return _content ??= ContentPreview(
      cache: cache,
      executor: _executor,
      jobs: jobs,
      isDisposed: () => _closed || isDisposed(),
      emit: emit,
    );
  }

  FileOperations get operations {
    _checkOpen();
    return _operations ??= FileOperations(
      search: () => _fileCatalog,
      gallery: () => _fileCatalog,
      directories: () => _fileCatalog,
      mutations: () => _mutations ??= FileMutationService(_executor),
      transfers: transfers,
      sharing: sharing,
      isDisposed: () => _closed || isDisposed(),
      isStateUnverified: isStateUnverified,
      diagnostics: diagnostics,
    );
  }

  static Future<FileResources> open({
    required NativeHost host,
    required AdbServices localFiles,
    required String dataDirectory,
    required DeviceRecordStorage records,
    required DeviceConnection Function(String) requireConnection,
    required ThumbnailJobRequest Function() request,
    required bool Function() isDisposed,
    required bool Function() isStateUnverified,
    required DiagnosticReporter diagnostics,
    required void Function(Map<String, dynamic>) emit,
    required void Function(Stream<Map<String, dynamic>>) attachCatalogEvents,
    required void Function(FileShareService?) onSharingOpened,
  }) async {
    // 读取或清理缓存前先排空旧 isolate 的文档复制，避免与恢复产生并发写入。
    await AppPlatform.recoverDocuments(
      localFiles: createNativeScrcpyLocalFiles,
    );
    final documentSources = Platform.isAndroid
        ? await FileDocumentCache.open(
            cacheDirectory: Directory(
              (await FileDocumentScope.fromEnvironment(
                await AppPlatform.requestPlatform(
                  'documents.platform.environment',
                  const {},
                ),
              )).cacheDirectory,
            ),
          )
        : null;
    final sharing = Platform.isAndroid
        ? await FileShareService.open(
            files: createNativeScrcpyLocalFiles,
            platform: AppPlatform.requestPlatform,
          )
        : null;
    onSharingOpened(sharing);
    final gate = ContentCacheGate();
    late final ContentCache cache;
    FileTransferService? cacheTransfers;
    FileResources? owner;
    final deliveries = await FileDeliveryJournal.open(
      Directory(dataDirectory),
      cacheGate: gate,
      validateSource: (path) => cache.validateDeliveryLocked(path),
    );
    cache = await ContentCache.open(
      root: Directory(dataDirectory),
      gate: gate,
      protectedPaths: () => deliveries.protectedPaths,
      freeBytes: _cacheStorageFreeBytes,
      isDisposed: () => owner?.isDisposed() ?? false,
      onChanged: () {
        final current = owner;
        if (current != null && !current.isDisposed()) {
          emit({'type': 'media.cache.changed'});
        }
      },
      protectionDetails: () async => [
        for (final source
            in cacheTransfers?.cacheSources ?? <CacheProtection>[])
          source.copyWith(
            sourceLabel:
                records.current.find(source.sourceLabel ?? '')?.name ??
                source.sourceLabel,
          ),
        ...await deliveries.protectedSources,
      ],
    );
    final fileExecutor = AdbFileExecutor(
      localFiles: localFiles,
      resolveConnection: (id) async => requireConnection(id),
      fileScopeId: host.fileScopeId,
      fileScopeKey: host.fileScopeKey,
    );
    final transfers = await FileTransferService.open(
      executor: fileExecutor,
      cache: cache,
      publication: documentSources == null
          ? sharing
          : FilePublicationLeasePool(
              sharing: sharing,
              documents: documentSources,
            ),
      dataDirectory: Directory(dataDirectory),
    );

    cacheTransfers = transfers;
    return owner = FileResources._(
      transfers: transfers,
      cache: cache,
      deliveries: deliveries,
      sharing: sharing,
      documentSources: documentSources,
      executor: fileExecutor,
      isDisposed: isDisposed,
      isStateUnverified: isStateUnverified,
      diagnostics: diagnostics,
      requireConnection: requireConnection,
      request: request,
      emit: emit,
      attachCatalogEvents: attachCatalogEvents,
    );
  }

  Future<void> cancelFiles(String deviceId) async {
    await Future.wait([
      if (_catalog case final catalog?) catalog.cancelDevice(deviceId),
      if (_mutations case final mutations?) mutations.cancelDevice(deviceId),
      transfers.cancelDevice(deviceId),
    ]);
  }

  Future<void> cancelContent(String deviceId) async =>
      await _content?.cancelDevice(deviceId);

  Future<void> stopForConnection(
    String deviceId,
    DeviceConnection connection, {
    required bool accepted,
  }) async {
    await Future.wait([
      if (accepted) cancelFiles(deviceId),
      if (accepted) cancelContent(deviceId),
      if (_jobs case final jobs?) jobs.stopForConnection(deviceId, connection),
      _executor.stopForConnection(connection),
    ], eagerError: true);
  }

  Future<String> acquireTransferCacheLease(String transferId) {
    _checkOpen();
    return transfers.acquireCacheLease(transferId);
  }

  void stopAdmission() {
    _closed = true;
    sharing?.stopIntake();
  }

  OrderedDisposal? _disposal;
  Future<void> close() {
    stopAdmission();
    _disposal ??= OrderedDisposal([
      () async => await _content?.close(),
      () async => await Future.wait([
        transfers.close(),
        if (_catalog case final catalog?) catalog.close(),
        if (_mutations case final mutations?) mutations.close(),
        _executor.close(),
      ], eagerError: true),
      () async => await sharing?.close(),
      () async => await _jobs?.close(),
    ]);
    return _disposal!.run();
  }
}

/// 只读查询暂存所在存储的实际可用量，不申请文件复制作用域。
Future<int?> _cacheStorageFreeBytes(String root) async {
  final value = await readNativeScrcpyLocalStorageFreeBytes(root);
  if (value < BigInt.zero || value > BigInt.from(0x7fffffffffffffff)) {
    return null;
  }
  return value.toInt();
}
