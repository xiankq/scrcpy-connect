import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/content/content_cache_failure.dart';
import 'package:scrcpy_connect/core/content/content_cache_gate.dart';
import 'package:scrcpy_connect/core/content/models/cache_status.dart';
import 'package:scrcpy_connect/core/files/file_cache_leases.dart';
import 'package:scrcpy_connect/core/files/file_cache_reservation.dart';
import 'package:uuid/uuid.dart';

export 'package:scrcpy_connect/core/content/models/cache_status.dart';

const defaultMediaCacheBudget = 512 * 1024 * 1024;
const _maximumConfigurationBytes = 1024 * 1024;
const _maximumInteger = 0x7fffffffffffffff;
final _random = Random.secure();

typedef CacheProtectedPaths = FutureOr<Iterable<String>> Function();
typedef CacheProtectionDetails = FutureOr<List<CacheProtection>> Function();
typedef CacheFreeBytes = Future<int?> Function(String root);
typedef CacheConfigurationCommit = Future<void> Function(
  File temporary,
  File destination,
);

/// 页面只能管理已登记的缓存，不取得底层写入预算和所有者关闭权。
abstract interface class ContentCacheControl {
  Future<CacheStatus> status();
  Future<void> configure({int? budgetBytes, String? outgoingDirectory});
  Future<int> clear();
  Future<bool> retain(String path, {bool ifManaged = false});
  Future<void> release(String leaseId);
}

/// 明确持有写入路径及剩余字节预算；本机任务的 finally 中关闭，不用 GC 决定租约寿命。
final class _CacheWriter implements CacheWriter {
  _CacheWriter._(this._owner, this.leaseId);
  final ContentCache _owner;
  @override
  final String leaseId;
  bool _closed = false;
  @override
  Future<void> close() async {
    if (_closed) return;
    await _owner.release(leaseId);
    _closed = true;
  }
}

/// 受管缓存的应用所有者；配置提交结果未知时只允许释放已有租约。
/// 恢复存储后应结束旧任务、释放租约，再重新打开；旧实例不会自行解除封锁。
final class ContentCache implements FileCacheLeases, ContentCacheControl {
  ContentCache._(
    this.root,
    this.gate,
    this._protectedPaths,
    this._commitConfiguration,
    this._freeBytes,
    this._protectionDetails,
    this._onChanged,
    this._isDisposed,
  );
  final Directory root;
  final ContentCacheGate gate;
  final CacheProtectedPaths _protectedPaths;
  final CacheConfigurationCommit _commitConfiguration;
  final CacheFreeBytes? _freeBytes;
  final CacheProtectionDetails? _protectionDetails;
  final void Function()? _onChanged;
  final bool Function()? _isDisposed;
  late _Configuration _configuration;
  List<int>? _storedConfigurationBytes;
  bool _storageUnknown = false;
  static const _unknownStorage = ContentCacheFailure(
    'cache_storage_unknown',
    '无法确认媒体缓存配置是否已提交，请恢复存储后重新打开缓存。',
  );
  final _leases = <String, List<_Reservation>>{};
  File get _configurationFile => File(p.join(root.path, 'media-cache.json'));

  static Future<ContentCache> open({
    required Directory root,
    ContentCacheGate? gate,
    CacheProtectedPaths? protectedPaths,
    CacheConfigurationCommit? commitConfiguration,
    CacheFreeBytes? freeBytes,
    CacheProtectionDetails? protectionDetails,
    void Function()? onChanged,
    bool Function()? isDisposed,
  }) async {
    await _plainPath(root.path);
    await root.create(recursive: true);
    final owner = ContentCache._(
      Directory(p.normalize(root.path)),
      gate ?? ContentCacheGate(),
      protectedPaths ?? () => const <String>[],
      commitConfiguration ??
          (temporary, destination) async {
            await temporary.rename(destination.path);
          },
      freeBytes,
      protectionDetails,
      onChanged,
      isDisposed,
    );
    await owner.gate.runExclusive(() async {
      final file = owner._configurationFile;
      await _plainPath(file.path);
      if (await file.exists()) {
        try {
          final bytes = await _boundedRead(file);
          final document = jsonDecode(utf8.decode(bytes));
          owner._configuration = _Configuration.parse(document);
          owner._storedConfigurationBytes = bytes;
        } on FormatException {
          throw const ContentCacheFailure(
            'cache_storage_invalid',
            '媒体缓存所有权记录损坏。',
          );
        }
      } else {
        // 失效链接不应被当成缺少配置并在之后覆盖。
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const ContentCacheFailure(
            'cache_storage_invalid',
            '缓存配置不是普通文件。',
          );
        }
        owner._configuration = const _Configuration();
      }
      await _plainPath(file.path);
      await owner._validateConfiguration(owner._configuration);
    });
    return owner;
  }

  @override
  Future<CacheStatus> status() => gate.runExclusive(() {
    _requireActive();
    return _statusLocked();
  });

  void _requireActive() {
    if (_isDisposed?.call() == true) {
      throw const ContentCacheFailure('disposed', '应用缓存所有者已关闭。');
    }
  }

  @override
  Future<void> configure({int? budgetBytes, String? outgoingDirectory}) async {
    await gate.runExclusive(() async {
      _requireActive();
      _requireConfirmedStorage();
      final next = _Configuration(
        budget: budgetBytes ?? _configuration.budget,
        outgoing: outgoingDirectory ?? _configuration.outgoing,
        retained: _configuration.retained,
      );
      await _validateConfiguration(next);
      if (_configuration.outgoing != null &&
          next.outgoing != _configuration.outgoing) {
        throw const ContentCacheFailure(
          'cache_configuration_conflict',
          '已登记的原件缓存目录不能被另一目录替换。',
        );
      }
      if (next.outgoing != null) {
        await Directory(next.outgoing!).create(recursive: true);
      }
      await _writeConfiguration(next);
      _configuration = next;
    });
    _onChanged?.call();
  }

  @override
  Future<int> clear() async {
    final deleted = await gate.runExclusive(() async {
      _requireActive();
      final snapshot = await _snapshot();
      return _delete(snapshot, _maximumInteger);
    });
    _onChanged?.call();
    return deleted;
  }

  @override
  Future<bool> retain(String path, {bool ifManaged = false}) async {
    final retained = await gate.runExclusive(() async {
      _requireActive();
      _requireConfirmedStorage();
      await _plainPath(path);
      if (!_managed(path)) {
        if (ifManaged) return false;
        throw const ContentCacheFailure('invalid_argument', '只能保留已登记媒体缓存中的内容。');
      }
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        throw const ContentCacheFailure('cache_evicted', '此媒体缓存已经清理，请重新取回。');
      }
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.directory) {
        throw const ContentCacheFailure('invalid_argument', '只能保留普通文件或目录。');
      }
      final next = _Configuration(
        budget: _configuration.budget,
        outgoing: _configuration.outgoing,
        retained: {..._configuration.retained, p.normalize(path)},
      );
      await _writeConfiguration(next);
      _configuration = next;
      return true;
    });
    if (retained) _onChanged?.call();
    return retained;
  }

  @override
  Future<String> reserve(List<FileCacheReservation> reservations) {
    // 调用方仍拥有原列表；入队前固定本次请求，不能在异步核验途中改变其身份或预算。
    final captured = List<FileCacheReservation>.unmodifiable(reservations);
    return gate.runExclusive(() async {
      _requireConfirmedStorage();
      if (captured.isEmpty || captured.length > 2000) {
        throw const ContentCacheFailure(
          'invalid_argument',
          '缓存保留路径必须为 1 至 2000 项。',
        );
      }
      if (_leases.length >= 1024) {
        throw const ContentCacheFailure('busy', '缓存租约达到上限。');
      }
      final records = <_Reservation>[];
      var requested = 0;
      final protected = await _protections();
      final fresh = captured.any((reservation) => reservation.bytes > 0);
      for (final reservation in captured) {
        _size(reservation.bytes);
        await _plainPath(reservation.path);
        final path = p.normalize(reservation.path);
        if (!_managed(path)) {
          throw const ContentCacheFailure('invalid_argument', '目标不属于已登记缓存目录。');
        }
        if (fresh && protected.any((other) => _overlaps(path, other))) {
          throw const ContentCacheFailure(
            'cache_in_use',
            '目标缓存正被其他操作使用，请使用新的取回位置。',
          );
        }
        if (reservation.bytes > 0 &&
            records.any(
              (record) => record.bytes > 0 && _overlaps(path, record.path),
            )) {
          throw const ContentCacheFailure(
            'invalid_argument',
            '写入预算不能重复覆盖同一路径或其子树。',
          );
        }
        requested = _add(requested, reservation.bytes);
        records.add(
          _Reservation(
            path,
            reservation.bytes,
            reservation.name,
            reservation.sourceLabel,
            reservation.sourcePath,
          ),
        );
      }
      final snapshot = requested > 0 ? await _snapshot() : null;
      // 读取已有内容只检查选中子树，不为了建立只读租约遍历和驱逐全部缓存。
      final selectedFiles =
          snapshot?.files ??
          await _scan(records.map((record) => record.path).toList());
      final baselines = _bytesUnderPaths(
        selectedFiles,
        records.map((record) => record.path),
      );
      for (final record in records) {
        record.baseline = baselines[record.path]!;
      }
      // 选中的现存原件在准入驱逐前就受到保护，不能为新字节腾挪而删除本次目标。
      if (snapshot != null) {
        snapshot.protected.addAll(records.map((record) => record.path));
        await _admit(snapshot, requested);
      }
      final id = const Uuid().v4();
      _leases[id] = records;
      return id;
    });
  }

  @override
  Future<void> release(String lease) => gate.runExclusive(() {
    _releaseLocked(lease);
  });
  void _releaseLocked(String lease) {
    if (!RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    ).hasMatch(lease)) {
      throw const ContentCacheFailure('invalid_argument', '缓存租约标识必须为 UUID。');
    }
    _leases.remove(lease);
  }

  Future<CacheWriter> writer(
    String path,
    int bytes, {
    String? name,
    String? sourceLabel,
    String? sourcePath,
  }) async => _CacheWriter._(
    this,
    await reserve([
      FileCacheReservation(
        path,
        bytes,
        name: name,
        sourceLabel: sourceLabel,
        sourcePath: sourcePath,
      ),
    ]),
  );

  /// FileDeliveryJournal 持有同一个 gate 后调用，再在 gate 内提交 pending 记录。
  /// 此方法不排队；protectedPaths 回调也必须遵循 gate → journal 的锁顺序。
  Future<void> validateDeliveryLocked(String path) async {
    _requireConfirmedStorage();
    if (!_managed(path)) return;
    await _plainPath(path);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw const ContentCacheFailure('cache_evicted', '此媒体缓存已经清理，请重新取回。');
    }
  }

  List<String> get _roots => [
    p.join(root.path, 'media'),
    ?_configuration.outgoing,
  ];
  bool _managed(String path) => _roots.any((root) => _contains(root, path));
  Future<void> _validateConfiguration(_Configuration configuration) async {
    _size(configuration.budget);
    if (configuration.budget == 0) {
      throw const ContentCacheFailure('invalid_argument', '缓存预算必须为正整数。');
    }
    final outgoing = configuration.outgoing;
    if (outgoing != null) {
      await _plainPath(outgoing);
      if (p.basename(outgoing) != 'outgoing' ||
          _contains(outgoing, root.path) ||
          _contains(p.join(root.path, 'media'), outgoing)) {
        throw const ContentCacheFailure(
          'invalid_argument',
          '仅可登记应用缓存中的 outgoing 目录，不能登记应用根目录。',
        );
      }
    }
    for (final retained in configuration.retained) {
      await _plainPath(retained);
      if (![
        p.join(root.path, 'media'),
        ?outgoing,
      ].any((root) => _contains(root, retained))) {
        throw const ContentCacheFailure(
          'cache_storage_invalid',
          '保留路径不属于受管缓存目录。',
        );
      }
    }
    await _plainPath(p.join(root.path, 'media'));
  }

  Future<Set<String>> _protections() async => {
    ..._configuration.retained,
    ..._leases.values.expand((records) => records.map((record) => record.path)),
    for (final path in await _protectedPaths()) p.normalize(path),
  };
  Future<_Snapshot> _snapshot() async {
    _requireConfirmedStorage();
    for (final root in _roots) {
      await _plainPath(root);
    }
    final files = await _scan(_roots);
    final protected = await _protections();
    final records = _leases.values.expand((records) => records).toList();
    final totals = _bytesUnderPaths(
      files,
      records.map((record) => record.path),
    );
    var reserved = 0;
    for (final record in records) {
      final growth = max(0, totals[record.path]! - record.baseline);
      reserved = _add(reserved, max(0, record.bytes - growth));
    }
    return _Snapshot(files, protected, reserved);
  }

  Future<int?> _readFreeBytes() async {
    if (_freeBytes == null) return null;
    try {
      final free = await _freeBytes(root.path);
      return free != null && free >= 0 ? free : null;
    } catch (_) {
      return null;
    }
  }

  Future<CacheStatus> _statusLocked() async {
    final snapshot = await _snapshot();
    final details = [
      ...?await _protectionDetails?.call(),
      for (final record in _leases.values.expand((records) => records))
        if (record.name != null)
          CacheProtection(
            path: record.path,
            name: record.name,
            sourceLabel: record.sourceLabel,
            sourcePath: record.sourcePath,
          ),
    ];
    final free = await _readFreeBytes();
    final budgetAvailable = max(
      0,
      _configuration.budget - snapshot.protectedBytes - snapshot.reserved,
    );
    final roots = snapshot.protected.toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    final groups = <String>[];
    for (final path in roots) {
      if (!groups.any((parent) => _contains(parent, path))) groups.add(path);
    }
    final items = <ProtectedCacheItem>[];
    for (final path in groups) {
      final files = snapshot.files
          .where((file) => _contains(path, file.path))
          .toList();
      if (files.isEmpty) continue;
      final matching = details
          .where(
            (detail) =>
                _contains(path, detail.path) || _contains(detail.path, path),
          )
          .toList();
      final source = matching.firstOrNull;
      final external = _configuration.retained.any(
        (retained) => _overlaps(retained, path),
      );
      final reasons = matching
          .map((item) => item.reason)
          .whereType<String>()
          .toSet()
          .join('；');
      items.add(
        ProtectedCacheItem(
          localPath: path,
          name: source?.name ?? p.basename(path),
          sourceLabel: source?.sourceLabel ?? '来源暂不可核验',
          sourcePath: source?.sourcePath,
          transferId: source?.transferId,
          bytes: files.fold<int>(0, (total, file) => _add(total, file.bytes)),
          reason: external
              ? '系统分享或打开后的读取寿命未知，继续保留原件'
              : reasons.isNotEmpty
              ? reasons
              : '预览、传输或准备仍在使用',
          canExport: source?.canExport ?? false,
          canShare:
              source?.canExport == true &&
              FileSystemEntity.typeSync(path, followLinks: false) ==
                  FileSystemEntityType.file,
          externalLifetimeUnknown: external,
        ),
      );
    }
    return CacheStatus(
      budgetBytes: _configuration.budget,
      usedBytes: snapshot.used,
      protectedBytes: snapshot.protectedBytes,
      reclaimableBytes: snapshot.used - snapshot.protectedBytes,
      reservedBytes: snapshot.reserved,
      freeBytes: free,
      availableBytes: free == null
          ? budgetAvailable
          : min(
              budgetAvailable,
              max(
                0,
                free +
                    snapshot.used -
                    snapshot.protectedBytes -
                    snapshot.reserved,
              ),
            ),
      spaceVerified: _freeBytes == null || free != null,
      protectedItems: items,
      retainedShareCount: _configuration.retained.length,
      retentionReason: _configuration.retained.isEmpty
          ? null
          : '系统分享尚无可靠的读取完成回执，已分享的缓存会继续保留。',
    );
  }

  Future<void> _admit(_Snapshot snapshot, int bytes) async {
    final budgetAvailable = max(
      0,
      _configuration.budget - snapshot.protectedBytes - snapshot.reserved,
    );
    final free = await _readFreeBytes();
    if (_freeBytes != null && free == null) {
      throw ContentCacheFailure(
        'cache_space_unknown',
        '需要 ${_storageSize(bytes)}，当前无法核验本机可用空间，请检查存储后重试。',
      );
    }
    final reclaimable = snapshot.used - snapshot.protectedBytes;
    final available = free == null
        ? budgetAvailable
        : min(budgetAvailable, max(0, free + reclaimable - snapshot.reserved));
    if (bytes > available) {
      throw ContentCacheFailure(
        'cache_budget_exceeded',
        '需要 ${_storageSize(bytes)}，当前可用 ${_storageSize(available)}。${reclaimable > 0 ? '可清理 ${_storageSize(reclaimable)} 的可回收暂存，或减少选择后重试。' : '当前没有可清理项目；可减少选择、在原手机打开，或使用已有的其他传输方式。'}受保护原件会继续保留。',
      );
    }
    final required = _add(_add(snapshot.used, snapshot.reserved), bytes);
    final needed = max(
      0,
      max(
        required - _configuration.budget,
        free == null ? 0 : bytes + snapshot.reserved - free,
      ),
    );
    if (needed > 0) await _delete(snapshot, needed);
    final after = await _snapshot();
    final remainingFree = await _readFreeBytes();
    if (_freeBytes != null && remainingFree == null) {
      throw ContentCacheFailure(
        'cache_space_unknown',
        '需要 ${_storageSize(bytes)}，当前无法核验本机可用空间，请检查存储后重试。',
      );
    }
    if (_add(_add(after.used, after.reserved), bytes) > _configuration.budget ||
        _freeBytes != null &&
            (remainingFree == null || bytes + after.reserved > remainingFree)) {
      final remaining = min(
        max(0, _configuration.budget - after.used - after.reserved),
        remainingFree == null ? 0 : max(0, remainingFree - after.reserved),
      );
      throw ContentCacheFailure(
        'cache_budget_exceeded',
        '需要 ${_storageSize(bytes)}，当前可用 ${_storageSize(remaining)}。暂存空间已变化，请减少选择或在手机上打开。',
      );
    }
  }

  Future<int> _delete(_Snapshot snapshot, int wanted) async {
    snapshot.files.sort((a, b) {
      final byTime = a.modified.compareTo(b.modified);
      return byTime == 0 ? a.path.compareTo(b.path) : byTime;
    });
    var deleted = 0;
    for (final file in snapshot.files) {
      if (deleted >= wanted) break;
      if (snapshot.protected.any((path) => _contains(path, file.path))) {
        continue;
      }
      await _plainPath(file.path);
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      try {
        final length = await File(file.path).length();
        await File(file.path).delete();
        deleted = _add(deleted, length);
      } on PathNotFoundException {
        /* 并发消失不计入本次实际删除量。 */
      }
    }
    return deleted;
  }

  Future<void> _writeConfiguration(_Configuration configuration) async {
    _requireConfirmedStorage();
    final bytes = utf8.encode(jsonEncode(configuration.toJson()));
    if (bytes.length > _maximumConfigurationBytes) {
      throw const ContentCacheFailure('cache_capacity', '媒体分享保留记录已满，请先保留当前原件。');
    }
    await _plainPath(_configurationFile.path);
    final temporary = File(
      p.join(root.path, '.media-cache-$pid-${_random.nextInt(0x7fffffff)}.tmp'),
    );
    try {
      final output = await temporary.open(mode: FileMode.writeOnly);
      try {
        await output.writeFrom(bytes);
        await output.flush();
      } finally {
        await output.close();
      }
      try {
        await _commitConfiguration(temporary, _configurationFile);
      } on Object {
        final outcome = await _verifyConfiguration(bytes);
        if (outcome == _CommitOutcome.unchanged) rethrow;
        if (outcome == _CommitOutcome.unknown) {
          _storageUnknown = true;
          throw _unknownStorage;
        }
      }
      _storedConfigurationBytes = bytes;
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        /* 清理失败不改写已完成的提交。 */
      }
    }
  }

  void _requireConfirmedStorage() {
    if (_storageUnknown) throw _unknownStorage;
  }

  Future<_CommitOutcome> _verifyConfiguration(List<int> proposed) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _plainPath(_configurationFile.path);
        final actual = await _readConfigurationOrMissing(_configurationFile);
        if (_equalBytes(actual, proposed)) return _CommitOutcome.committed;
        if (_equalBytes(actual, _storedConfigurationBytes)) {
          return _CommitOutcome.unchanged;
        }
        return _CommitOutcome.unknown;
      } on FileSystemException {
        // 回执和一次回读可以同时失败；再核验一次，仍无法读取时不能猜测提交结果。
      } on ContentCacheFailure {
        // 路径变成链接、配置超限等也不能证明旧配置仍在原处。
      }
    }
    return _CommitOutcome.unknown;
  }
}

enum _CommitOutcome { committed, unchanged, unknown }

final class _Configuration {
  const _Configuration({
    this.budget = defaultMediaCacheBudget,
    this.outgoing,
    this.retained = const {},
  });
  factory _Configuration.parse(Object? value) {
    if (value is! Map ||
        value.keys.any(
          (key) => !const {
            'budgetBytes',
            'outgoingDirectory',
            'retainedShares',
          }.contains(key),
        ) ||
        value['budgetBytes'] is! int ||
        value['retainedShares'] is! List ||
        value['outgoingDirectory'] != null &&
            value['outgoingDirectory'] is! String) {
      throw const ContentCacheFailure('cache_storage_invalid', '媒体缓存所有权记录损坏。');
    }
    final retained = value['retainedShares'] as List;
    if (retained.any((path) => path is! String)) {
      throw const ContentCacheFailure('cache_storage_invalid', '媒体缓存保留路径无效。');
    }
    return _Configuration(
      budget: value['budgetBytes'] as int,
      outgoing: value['outgoingDirectory'] as String?,
      retained: Set<String>.unmodifiable(retained.cast<String>()),
    );
  }
  final int budget;
  final String? outgoing;
  final Set<String> retained;
  Map<String, Object?> toJson() => {
    'budgetBytes': budget,
    'outgoingDirectory': outgoing,
    'retainedShares': retained.toList()..sort(),
  };
}

final class _Reservation {
  _Reservation(
    this.path,
    this.bytes,
    this.name,
    this.sourceLabel,
    this.sourcePath,
  );
  final String path;
  final int bytes;
  final String? name, sourceLabel, sourcePath;
  int baseline = 0;
}

typedef _CacheFile = ({String path, int bytes, DateTime modified});

final class _Snapshot(
  final List<_CacheFile> files,
  final Set<String> protected,
  final int reserved,
) {
  int get used => files.fold(0, (sum, file) => _add(sum, file.bytes));
  int get protectedBytes => files
      .where((file) => protected.any((path) => _contains(path, file.path)))
      .fold(0, (sum, file) => _add(sum, file.bytes));
}

Future<void> _plainPath(String path) async {
  if (!p.isAbsolute(path) ||
      path.contains('\u0000') ||
      path.split(RegExp(r'[/\\]')).any((part) => part == '.' || part == '..')) {
    throw const ContentCacheFailure('invalid_argument', '缓存路径必须是不含相对分量的绝对路径。');
  }
  var current = '';
  final parts = p.split(path);
  for (var index = 0; index < parts.length; index++) {
    current = p.join(current, parts[index]);
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type == FileSystemEntityType.link ||
        index < parts.length - 1 && type == FileSystemEntityType.file) {
      throw const ContentCacheFailure('invalid_argument', '缓存路径不能经过符号链接或普通文件。');
    }
  }
}

bool _contains(String parent, String child) =>
    p.equals(parent, child) || p.isWithin(parent, child);
bool _overlaps(String first, String second) =>
    _contains(first, second) || _contains(second, first);
// 每个文件只遍历祖先组件一次，避免每条租约重复扫描完整缓存。
Map<String, int> _bytesUnderPaths(
  List<_CacheFile> files,
  Iterable<String> paths,
) {
  final totals = {for (final path in paths) path: 0};
  for (final file in files) {
    var ancestor = file.path;
    while (true) {
      if (totals.containsKey(ancestor)) {
        totals[ancestor] = _add(totals[ancestor]!, file.bytes);
      }
      final parent = p.dirname(ancestor);
      if (parent == ancestor) break;
      ancestor = parent;
    }
  }
  return totals;
}

Future<List<_CacheFile>> _scan(List<String> roots) async {
  final unique = roots.toSet();
  final pending = unique
      .where(
        (path) =>
            !unique.any((other) => other != path && _contains(other, path)),
      )
      .toList();
  final files = <_CacheFile>[];
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await for (final entry in Directory(path).list(followLinks: false)) {
        pending.add(entry.path);
      }
    } else if (type == FileSystemEntityType.file) {
      final stat = await File(path).stat();
      files.add((path: path, bytes: stat.size, modified: stat.modified));
    }
  }
  return files;
}

void _size(int bytes) {
  if (bytes < 0 || bytes > _maximumInteger) {
    throw const ContentCacheFailure('invalid_argument', '缓存字节数必须为非负整数。');
  }
}

int _add(int first, int second) {
  if (first > _maximumInteger - second) {
    throw const ContentCacheFailure('invalid_argument', '缓存字节数超过容量。');
  }
  return first + second;
}

Future<List<int>> _boundedRead(File file) async {
  if (await file.length() > _maximumConfigurationBytes) {
    throw const ContentCacheFailure('cache_storage_invalid', '媒体缓存所有权记录过大。');
  }
  final bytes = await file
      .openRead(0, _maximumConfigurationBytes + 1)
      .fold<List<int>>([], (bytes, part) => bytes..addAll(part));
  if (bytes.length > _maximumConfigurationBytes) {
    throw const ContentCacheFailure('cache_storage_invalid', '媒体缓存所有权记录过大。');
  }
  return bytes;
}

Future<List<int>?> _readConfigurationOrMissing(File file) async {
  try {
    return await _boundedRead(file);
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode == 2 ||
        Platform.isWindows && error.osError?.errorCode == 3) {
      return null;
    }
    rethrow;
  }
}

bool _equalBytes(List<int>? first, List<int>? second) {
  if (first == null || second == null) return first == second;
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}

String _storageSize(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB'
    : bytes >= 1024
    ? '${(bytes / 1024).toStringAsFixed(2)} KiB'
    : '$bytes B';
