import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_mutations.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner.dart';

/// 文件能力入口：核验操作准入并转换执行失败；任务与资源仍由各自所有者管理。
final class FileOperations
    implements
        FileSearch,
        GalleryScanner,
        FileDirectories,
        FileMutations,
        FileTransfers,
        IncomingShares {
  FileOperations({
    required FileSearch Function() search,
    required GalleryScanner Function() gallery,
    required FileDirectories Function() directories,
    required FileMutations Function() mutations,
    required this._transfers,
    this._sharing,
    required this.isDisposed,
    required this.isStateUnverified,
    required this._diagnostics,
  }) : _createSearch = search,
       _createGallery = gallery,
       _createDirectories = directories,
       _createMutations = mutations;

  final FileSearch Function() _createSearch;
  FileSearch get _search => _createSearch();
  final GalleryScanner Function() _createGallery;
  GalleryScanner get _gallery => _createGallery();
  final FileDirectories Function() _createDirectories;
  FileDirectories get _directories => _createDirectories();
  final FileMutations Function() _createMutations;
  FileMutations get _mutations => _createMutations();
  final FileTransfers _transfers;
  final IncomingShares? _sharing;
  final bool Function() isDisposed;
  final bool Function() isStateUnverified;
  final DiagnosticReporter _diagnostics;

  @override
  Future<GalleryScanSnapshot> startScan(String deviceId, {int limit = 100}) =>
      _fileOperation(
        'media.list',
        deviceId,
        () => _gallery.startScan(deviceId, limit: limit),
      );

  @override
  Future<GalleryScanSnapshot> readScan(
    GalleryScanTarget target, {
    int offset = 0,
    int limit = 100,
  }) => _fileOperation(
    'media.list',
    target.deviceId,
    () => _gallery.readScan(target, offset: offset, limit: limit),
  );

  @override
  Future<GalleryScanSnapshot> cancelScan(GalleryScanTarget target) =>
      _fileOperation(
        'media.scan.cancel',
        target.deviceId,
        () => _gallery.cancelScan(target),
      );

  @override
  Future<FileDirectorySnapshot> readDirectory(
    FileDirectoryTarget target, {
    FileCatalogFilter filter = .all,
    FileDirectorySort sort = .name,
    bool descending = false,
    int offset = 0,
    int limit = 10000,
    FileCancellation? cancellation,
  }) => _fileOperation(
    'files.list',
    target.deviceId,
    () => _directories.readDirectory(
      target,
      filter: filter,
      sort: sort,
      descending: descending,
      offset: offset,
      limit: limit,
      cancellation: cancellation,
    ),
  );

  @override
  Future<FileTransferCollection> readTransfers() =>
      _fileOperation('transfers.list', null, _transfers.readTransfers);

  @override
  Future<FileTransferSnapshot> readTransfer(String id) => _fileOperation(
    'transfers.get',
    null,
    () => _transfers.readTransfer(id),
    transferId: id,
  );

  @override
  Future<FileTransferSubmission> startTransfer(
    FileTransferPlan plan, {
    String? shareId,
  }) => _fileOperation(
    'files.${plan.direction.name}',
    plan.deviceId,
    () => _transfers.startTransfer(plan, shareId: shareId),
    requiresVerifiedState: true,
  );

  @override
  Future<void> cancelTransfer(FileTransferTarget target) => _fileOperation(
    'transfers.cancel',
    null,
    () => _transfers.cancelTransfer(target),
    transferId: target.id,
  );

  @override
  Future<FileTransferSnapshot> resolveConflict(
    String id,
    FileTransferConflict policy, {
    bool applyToAll = false,
  }) => _fileOperation(
    'transfers.resolve',
    null,
    () => _transfers.resolveConflict(id, policy, applyToAll: applyToAll),
    transferId: id,
    requiresVerifiedState: true,
  );

  @override
  Future<FileTransferSnapshot> restartTransfer(
    String id, {
    FileTransferConflict? policy,
    bool applyToAll = false,
  }) => _fileOperation(
    'transfers.resume',
    null,
    () =>
        _transfers.restartTransfer(id, policy: policy, applyToAll: applyToAll),
    transferId: id,
    requiresVerifiedState: true,
  );

  @override
  Future<List<String>> removeTransfer(FileTransferTarget target) =>
      _fileOperation(
        'transfers.remove',
        null,
        () => _transfers.removeTransfer(target),
        transferId: target.id,
      );

  @override
  Future<void> clearTransferHistory(List<FileTransferTarget> targets) =>
      _fileOperation(
        'files.transfer.history.clear',
        null,
        () => _transfers.clearTransferHistory(targets),
      );

  @override
  Future<List<IncomingShare>> readIncomingShares() => _fileOperation(
    'sharing.pending',
    null,
    () async => await _sharing?.readIncomingShares() ?? [],
  );

  @override
  Future<void> consumeShare(String id) =>
      _fileOperation('sharing.consume', null, () async {
        final sharing = _sharing;
        if (sharing == null) {
          throw const RequestFailure('platform_unavailable', '此宿主不支持接收系统分享。');
        }
        await sharing.consumeShare(id);
      });

  @override
  Future<void> createDirectory(String deviceId, String path) => _fileOperation(
    'files.mkdir',
    deviceId,
    () => _mutations.createDirectory(deviceId, path),
    requiresVerifiedState: true,
  );

  @override
  Future<void> rename(
    String deviceId,
    FileMutationSelection source, {
    required String destination,
  }) => _fileOperation(
    'files.rename',
    deviceId,
    () => _mutations.rename(deviceId, source, destination: destination),
    requiresVerifiedState: true,
  );

  @override
  Future<void> delete(String deviceId, List<FileMutationSelection> sources) =>
      _fileOperation(
        'files.delete',
        deviceId,
        () => _mutations.delete(deviceId, sources),
        requiresVerifiedState: true,
      );

  @override
  Future<FileSearchSnapshot> startSearch(
    String deviceId, {
    required String path,
    required String query,
    FileCatalogFilter filter = .all,
  }) => _fileOperation(
    'files.search.start',
    deviceId,
    () =>
        _search.startSearch(deviceId, path: path, query: query, filter: filter),
  );

  @override
  Future<FileSearchSnapshot> readSearch(
    FileSearchTarget target, {
    int offset = 0,
    int limit = 500,
  }) => _fileOperation(
    'files.search.get',
    target.deviceId,
    () => _search.readSearch(target, offset: offset, limit: limit),
  );

  @override
  Future<void> cancelSearch(FileSearchTarget target) => _fileOperation(
    'files.search.cancel',
    target.deviceId,
    () => _search.cancelSearch(target),
  );

  Future<T> _fileOperation<T>(
    String label,
    String? deviceId,
    Future<T> Function() action, {
    bool requiresVerifiedState = false,
    String? transferId,
  }) async {
    if (isDisposed()) throw const RequestFailure('disposed', '连接界面已关闭。');
    if (deviceId != null && (deviceId.isEmpty || deviceId.contains('\u0000'))) {
      throw const RequestFailure('invalid_argument', '请指定设备。');
    }
    if (transferId != null &&
        (transferId.isEmpty || transferId.contains('\u0000'))) {
      throw const RequestFailure('invalid_argument', '请指定传输任务。');
    }
    if (requiresVerifiedState && isStateUnverified()) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    try {
      return await action();
    } catch (error, stack) {
      final failure = switch (error) {
        FileFailure(:final code, :final message) ||
        AdbException(
          :final code,
          :final message,
        ) => RequestFailure(code, message),
        DeviceRecordsFailure(:final code, :final message, :final details) =>
          RequestFailure(code, message, details),
        _ => error,
      };
      _diagnostics.fileOperationFailed(
        label,
        deviceId,
        failure,
        watch.elapsedMilliseconds,
      );
      Error.throwWithStackTrace(failure, stack);
    }
  }
}
