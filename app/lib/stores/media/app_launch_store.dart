import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:scrcpy_connect/models/application_request.dart';

/// 副作用记录的阶段，不表示 Android 应用当前的生命周期。
enum AppLaunchStatus { pending, unknown, observed, closed }

/// 单次打开的准入；调用方在实际交给控制队列前认领，取消后不能再次认领。
///
/// 已认领不表示远端收到消息，关闭仍须排空精确捕获并保留未知记录。
final class AppLaunchPermit {
  AppLaunchPermit._(this._admitted);
  final bool Function() _admitted;
  bool _claimed = false, _cancelled = false;
  bool get cancelled => _cancelled || !_admitted();
  bool claim() {
    if (_claimed || cancelled) return false;
    _claimed = true;
    return true;
  }

  void cancel() => _cancelled = true;
}

/// 持久保存的一次应用打开意图及已知结果。
final class AppLaunchRecord {
  const AppLaunchRecord({
    required this.operationId,
    required this.sessionId,
    required this.deviceId,
    required this.packageName,
    required this.status,
    required this.updatedAt,
    this.failureCode,
  });
  final String operationId, sessionId, deviceId, packageName;
  final AppLaunchStatus status;
  final String? failureCode;

  /// 与原 v1 文件契约相同的 Unix 秒。
  final int updatedAt;
  bool get unresolved =>
      status == AppLaunchStatus.pending || status == AppLaunchStatus.unknown;

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'sessionId': sessionId,
    'deviceId': deviceId,
    'packageName': packageName,
    'status': status.name,
    'failureCode': failureCode,
    'updatedAt': updatedAt,
  };

  Map<String, Object?> get projection => {
    'sessionId': operationId,
    'launchOperationId': operationId,
    'linkedSessionId': operationId == sessionId ? null : sessionId,
    'deviceId': deviceId,
    'packageName': packageName,
    'name': packageName,
    'status': 'failed',
    'kind': 'app',
    'launchOutcome': 'unknown',
    'recordOnly': true,
    'failureCode': failureCode,
    'reason': '应用打开请求可能已提交。请先核对手机并明确关闭本次记录，再选择重新打开。',
  };

  AppLaunchRecord _with(AppLaunchStatus status, int time, String? failure) =>
      AppLaunchRecord(
        operationId: operationId,
        sessionId: sessionId,
        deviceId: deviceId,
        packageName: packageName,
        status: status,
        failureCode: failure,
        updatedAt: time,
      );
}

/// 应用打开副作用的持久所有者，不拥有远端应用任务或捕获。
///
/// 只有先排空旧业务所有者后才能打开；跨 isolate 排空由应用宿主负责。
/// 写入结果未知即封存本实例，重新打开核验原记录，不在内存中解除防重。
final class AppLaunchStore {
  AppLaunchStore._(this.file, this._now);
  static const _maximumBytes = 2 * 1024 * 1024, _maximumRecords = 1024;
  static final _queues = <String, Future<void>>{};
  static final _owners = <String, WeakReference<AppLaunchStore>>{};
  static final _random = Random.secure();
  final File file;
  final DateTime Function() _now;
  var _records = <String, AppLaunchRecord>{};
  final _permits = <String, AppLaunchPermit>{};
  bool _uncertain = false;

  static Future<AppLaunchStore> open({
    required Directory directory,
    DateTime Function()? now,
  }) async {
    await directory.create(recursive: true);
    final canonical = Directory(await directory.resolveSymbolicLinks());
    final store = AppLaunchStore._(
      File.fromUri(canonical.uri.resolve('app-opens.json')),
      now ?? DateTime.now,
    );
    await store._exclusive(() async {
      final old = _owners[store.file.path]?.target;
      for (final permit in old?._permits.values ?? <AppLaunchPermit>[]) {
        permit.cancel();
      }
      _owners[store.file.path] = WeakReference(store);
      await store._load();
    }, opening: true);
    return store;
  }

  Future<T> _exclusive<T>(Future<T> Function() action, {bool opening = false}) {
    final key = file.path;
    final result = (_queues[key] ?? Future<void>.value()).then((_) {
      if (!opening) {
        if (!identical(_owners[key]?.target, this)) {
          throw const RequestFailure(
            'app_open_owner_replaced',
            '应用打开记录已被后继接管。',
          );
        }
        if (_uncertain) {
          throw const RequestFailure(
            'app_open_storage_unknown',
            '应用打开记录提交结果未知，请重新打开核验，不要重放打开请求。',
          );
        }
      }
      return action();
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_queues[key], tail)) _queues.remove(key);
      }),
    );
    return result;
  }

  Future<void> _load() async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.file) _invalid();
    final input = await file.open();
    final bytes = <int>[];
    try {
      while (bytes.length <= _maximumBytes) {
        final chunk = await input.read(_maximumBytes + 1 - bytes.length);
        if (chunk.isEmpty) break;
        bytes.addAll(chunk);
      }
    } finally {
      await input.close();
    }
    if (bytes.length > _maximumBytes) _invalid();
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map ||
          value.length != 2 ||
          value['version'] is! int ||
          value['version'] != 1 ||
          value['records'] is! Map) {
        _invalid();
      }
      final saved = value['records'] as Map;
      if (saved.length > _maximumRecords) _invalid();
      var interrupted = false;
      for (final entry in saved.entries) {
        final record = _decode(entry.key, entry.value);
        final restore =
            record.status == AppLaunchStatus.pending ||
            record.status == AppLaunchStatus.observed;
        _records[record.operationId] = restore
            ? record._with(
                AppLaunchStatus.unknown,
                record.updatedAt,
                'interrupted',
              )
            : record;
        interrupted |= restore;
      }
      if (interrupted) await _write(_records);
    } on FormatException {
      _invalid();
    }
  }

  Future<void> _write(Map<String, AppLaunchRecord> records) async {
    final bytes = utf8.encode(
      jsonEncode({
        'version': 1,
        'records': {
          for (final entry in records.entries) entry.key: entry.value.toJson(),
        },
      }),
    );
    if (bytes.length > _maximumBytes) {
      throw const RequestFailure('app_open_capacity', '应用打开记录已满，请先核对并关闭待处理记录。');
    }
    final temporary = File('${file.path}.${_random.nextInt(1 << 32)}.tmp');
    var created = false;
    try {
      await temporary.create(exclusive: true);
      created = true;
      final output = await temporary.open(mode: FileMode.writeOnly);
      try {
        await output.writeFrom(bytes);
        await output.flush();
      } finally {
        await output.close();
      }
      await temporary.rename(file.path);
    } catch (error) {
      Object? cleanupError;
      if (created) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (error) {
          cleanupError = error;
        }
      }
      _uncertain = true;
      for (final permit in _permits.values) {
        permit.cancel();
      }
      throw RequestFailure(
        'app_open_storage_unknown',
        '应用打开记录未能确认保存，请重新打开核验。',
        {
          'cause': '$error',
          if (cleanupError != null) 'cleanupError': '$cleanupError',
          if (cleanupError != null) 'temporaryPath': temporary.path,
        },
      );
    }
  }

  void _available(String device, String package) {
    final record = _records.values
        .where(
          (record) =>
              record.deviceId == device &&
              record.packageName == package &&
              record.unresolved,
        )
        .firstOrNull;
    if (record != null) {
      throw RequestFailure(
        'app_launch_unknown',
        '应用打开结果尚待核对，不会再次提交打开请求。',
        record.projection,
      );
    }
  }

  /// 先持久化打开意图，再交付一次性提交许可。
  ///
  /// 调用方仍须保留用户意图的取消权，并在实际执行前核验
  /// [AppLaunchPermit.claim]；返回许可不表示消息已经进入原生控制队列。
  Future<AppLaunchPermit> begin({
    required String operationId,
    required String sessionId,
    required String deviceId,
    required String packageName,
  }) => _exclusive(() async {
    final record = AppLaunchRecord(
      operationId: operationId,
      sessionId: sessionId,
      deviceId: deviceId,
      packageName: packageName,
      status: AppLaunchStatus.pending,
      updatedAt: _now().millisecondsSinceEpoch ~/ 1000,
    );
    _decode(operationId, record.toJson());
    _available(deviceId, packageName);
    if (_records.containsKey(operationId)) {
      throw const RequestFailure('app_open_conflict', '这次打开意图已经处理。');
    }
    final next = Map<String, AppLaunchRecord>.of(_records);
    if (next.length >= _maximumRecords) {
      final closed =
          next.values
              .where((value) => value.status == AppLaunchStatus.closed)
              .toList()
            ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      if (closed.isEmpty) {
        throw const RequestFailure(
          'app_open_capacity',
          '应用打开记录已满，请先核对并关闭待处理记录。',
        );
      }
      next.remove(closed.first.operationId);
    }
    next[operationId] = record;
    await _write(next);
    _records = next;
    return _permits[operationId] = AppLaunchPermit._(
      () => identical(_owners[file.path]?.target, this) && !_uncertain,
    );
  });

  /// 只接纳本次真实呈现或失败回执；未知和已关闭结果不被迟到成功覆盖。
  Future<void> finish(String operationId, {String? failureCode}) =>
      _exclusive(() async {
        final previous = _records[operationId];
        if (previous == null) {
          throw const RequestFailure('app_open_not_found', '找不到这次应用打开记录。');
        }
        if (previous.status == AppLaunchStatus.closed ||
            previous.status == AppLaunchStatus.unknown && failureCode == null) {
          throw const RequestFailure('cancelled', '这次打开已关闭或需要核对，不接受迟到结果。');
        }
        if (failureCode != null) _permits[operationId]?.cancel();
        final status = failureCode != null
            ? AppLaunchStatus.unknown
            : previous.operationId == previous.sessionId
            ? AppLaunchStatus.observed
            : AppLaunchStatus.closed;
        final record = previous._with(
          status,
          _now().millisecondsSinceEpoch ~/ 1000,
          failureCode,
        );
        _decode(operationId, record.toJson());
        final next = {..._records, operationId: record};
        await _write(next);
        _records = next;
        if (status != AppLaunchStatus.pending) {
          _permits.remove(operationId)?.cancel();
        }
      });

  /// 关闭记录不强停真实应用；调用方仍须收尾该操作的精确捕获。
  Future<bool> close(String operationId, {String? deviceId}) =>
      _exclusive(() async {
        final previous = _records[operationId];
        if (previous == null) return false;
        if (deviceId != null && previous.deviceId != deviceId) {
          throw const RequestFailure('invalid_argument', '应用打开记录不属于所选设备。');
        }
        _permits.remove(operationId)?.cancel();
        if (previous.status == AppLaunchStatus.closed) return true;
        final next = {
          ..._records,
          operationId: previous._with(
            AppLaunchStatus.closed,
            _now().millisecondsSinceEpoch ~/ 1000,
            previous.failureCode,
          ),
        };
        await _write(next);
        _records = next;
        return true;
      });

  Future<List<AppLaunchRecord>> unresolved({String? deviceId}) => _exclusive(
    () async => List.unmodifiable(
      _records.values.where(
        (record) =>
            record.unresolved &&
            (deviceId == null || record.deviceId == deviceId),
      ),
    ),
  );
}

Never _invalid() => throw const RequestFailure(
  'app_open_storage_invalid',
  '应用打开记录内容或版本无效，原文件已保留。',
);

AppLaunchRecord _decode(Object? key, Object? value) {
  const fields = {
    'operationId',
    'sessionId',
    'deviceId',
    'packageName',
    'status',
    'failureCode',
    'updatedAt',
  };
  if (key is! String ||
      value is! Map ||
      value.keys.any((key) => !fields.contains(key)) ||
      value['operationId'] != key ||
      !_uuid(key) ||
      !_uuid(value['sessionId']) ||
      value['deviceId'] is! String ||
      (value['deviceId'] as String).isEmpty ||
      utf8.encode(value['deviceId'] as String).length > 256 ||
      (value['deviceId'] as String).contains('\u0000') ||
      value['packageName'] is! String ||
      !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$')
          .hasMatch(value['packageName'] as String) ||
      (value['packageName'] as String).length > 230 ||
      value['updatedAt'] is! int ||
      (value['updatedAt'] as int) < 0 ||
      value['failureCode'] != null &&
          (value['failureCode'] is! String ||
              utf8.encode(value['failureCode'] as String).length > 128 ||
              (value['failureCode'] as String).contains('\u0000'))) {
    _invalid();
  }
  final status = AppLaunchStatus.values
      .where((item) => item.name == value['status'])
      .firstOrNull;
  if (status == null) _invalid();
  return AppLaunchRecord(
    operationId: key,
    sessionId: value['sessionId'] as String,
    deviceId: value['deviceId'] as String,
    packageName: value['packageName'] as String,
    status: status,
    updatedAt: value['updatedAt'] as int,
    failureCode: value['failureCode'] as String?,
  );
}

bool _uuid(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
