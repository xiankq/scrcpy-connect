import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/models/device_record.dart'
    show validDeviceId;
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/identity/identity_transaction_file.dart';
import 'package:scrcpy_connect/core/identity/models/authorization_identity.dart';
import 'package:scrcpy_connect/core/identity/models/identity_selection.dart';
import 'package:scrcpy_connect/core/identity/models/identity_transaction.dart';
import 'package:scrcpy_connect/core/identity/models/setup_identity.dart';

export 'package:scrcpy_connect/core/identity/models/authorization_identity.dart';

/// 身份准备事务的执行句柄；释放由创建它的身份模块确认。
abstract interface class IdentityAttempt {
  IdentitySelection get selection;
  Future<void> bindNew(String id);
  Future<void> dispose();
}

/// 回调必须在返回 Future 前同步撤销准入、取消有关 setup，再等待连接和活动清理。
/// global=true 还须取消尚未绑定设备且使用全局身份的 setup。
typedef InvalidateIdentities = Future<void> Function(
  Set<String> deviceIds, {
  required bool global,
});

/// 身份来源和失效规则归应用；密钥校验、生成与原子替换归 ADB SDK。
/// 同一目录只允许一个存活所有者，热重附着先重新核验真实文件再准入连接。
final class AdbIdentityService {
  AdbIdentityService._(
    this.directory,
    this.records,
    this.identities,
    this._invalidate,
  ) : _transactions = IdentityTransactionFile(directory);
  final Directory directory;
  final DeviceRecordStorage records;
  final AdbIdentities identities;
  final InvalidateIdentities _invalidate;
  final IdentityTransactionFile _transactions;
  IdentityTransaction? _transaction;
  Future<void> _tail = Future<void>.value();
  final _generations = <String, int>{};
  final _blocked = <String>{};
  int _globalGeneration = 0;
  bool _globalBlocked = false;
  final _pending = <String>{};
  bool _pendingGlobal = false;
  final _uncertain = <String>{};
  bool _globalUncertain = false;
  final _mutating = <String>{};
  bool _mutatingGlobal = false;
  final _candidates = <String>{};

  String get _globalPath => p.join(directory.path, 'host_identity.pem');
  String _devicePath(String id) =>
      p.join(directory.path, 'identities', '$id.pem');

  static Future<AdbIdentityService> open({
    required Directory directory,
    required DeviceRecordStorage records,
    required AdbIdentities identities,
    required InvalidateIdentities invalidate,
  }) async {
    final owner = AdbIdentityService._(
      directory,
      records,
      identities,
      invalidate,
    );
    await directory.create(recursive: true);
    await Directory(p.join(directory.path, 'identities')).create();
    await owner._load();
    return owner;
  }

  Future<void> _load() async {
    await _recoverTransaction();
    await identities.prepareIdentity(_globalPath);
    final global = await _inspect(_globalPath);
    final old = records.current;
    final custom = Map<String, String>.of(old.deviceIdentityFingerprints);
    final missing = <String>{};
    Map<String, Object?> legacy = const {};
    final file = File(p.join(directory.path, 'device_identities.json'));
    if (await file.exists()) {
      if (await file.length() > 16 * 1024 * 1024) {
        _fail('identity_error', '旧身份文件过大。');
      }
      try {
        final value = jsonDecode(await file.readAsString());
        if (value is! Map || value.keys.any((key) => key is! String)) {
          _fail('identity_error', '旧身份文件损坏，原文件已保留。');
        }
        legacy = Map<String, Object?>.from(value);
      } on FormatException {
        _fail('identity_error', '旧身份文件损坏，原文件已保留。');
      }
    }
    // 先完整校验需要迁移的材料，错误输入不产生部分新私钥文件。
    for (final entry in legacy.entries) {
      if (old.find(entry.key) == null) continue;
      await _validate(_pem(entry.value));
    }
    for (final id in {
      ...custom.keys,
      ...legacy.keys.where((id) => old.find(id) != null),
    }) {
      var info = await identities.inspectIdentity(_devicePath(id));
      final pem = legacy[id];
      if (info == null && pem is String) {
        // 旧公开指纹可能落后于已提交的私钥；按真实材料恢复并使旧信任失效。
        await _install(_devicePath(id), pem, null);
        info = await _inspect(_devicePath(id));
      }
      if (info != null) custom[id] = info.fingerprint;
      if (info == null && custom.containsKey(id)) missing.add(id);
      // 有公开绑定但无材料的记录保留专属来源，选择时明确失败。
    }
    final changed = <String>{
      ...missing,
      for (final device in old.devices)
        if ((old.deviceIdentityFingerprints[device.id] ??
                old.identityFingerprint) !=
            (custom[device.id] ?? global.fingerprint))
          device.id,
    };
    final globalChanged = old.identityFingerprint != global.fingerprint;
    if (changed.isNotEmpty || globalChanged) {
      await _startTransaction(
        IdentityTransaction(
          kind: IdentityTransactionKind.retire,
          affected: changed,
          global: globalChanged,
        ),
      );
    }
    await records.setIdentityFingerprints(
      global: global.fingerprint,
      devices: custom,
    );
    // 私钥文件和公开绑定全部持久化后才删除旧映射，避免遗忘设备仍残留第二份私钥。
    // 此前任一步失败都留下可继续迁移的原文件；损坏文件不会走到这里。
    if (await file.exists()) {
      await file.delete();
    }
    if (changed.isNotEmpty || globalChanged) {
      await _retire(changed, global: globalChanged, retainBlocked: true);
      await _finishTransaction();
      _unblock(changed, global: globalChanged);
    }
  }

  Future<void> _startTransaction(IdentityTransaction transaction) async {
    if (_transaction != null) {
      _fail('identity_changed', '上次身份事务尚未确认，请先核对或重试清理。');
    }
    await _transactions.write(transaction);
    _transaction = transaction;
  }

  Future<void> _finishTransaction() async {
    await _transactions.clear();
    _transaction = null;
  }

  Future<void> _recoverTransaction() async {
    final transaction = await _transactions.read();
    if (transaction == null) return;
    _transaction = transaction;
    final device = transaction.deviceId;
    if (transaction.kind == IdentityTransactionKind.key) {
      final path = device == null ? _globalPath : _devicePath(device);
      final actual = await identities.inspectIdentity(path);
      if (actual?.fingerprint != transaction.fingerprint) {
        if (actual?.fingerprint == transaction.previousFingerprint) {
          // 写前意图已落盘，但密钥并未发布；只撤销意图，不自动重放导入。
          await _finishTransaction();
          return;
        }
        await _retire(
          transaction.affected,
          global: transaction.global,
          retainBlocked: true,
        );
        _fail('identity_result_unknown', '身份文件与未完成事务不一致，已阻止连接；请核对本机存储。');
      }
    }
    final cleanup = _settle(
      _beginRetirement(transaction.affected, global: transaction.global),
    );
    Object? failure;
    StackTrace? trace;
    try {
      switch (transaction.kind) {
        case IdentityTransactionKind.key:
          if (device == null) {
            await records.setIdentityFingerprints(
              global: transaction.fingerprint!,
            );
          } else if (records.current.find(device) != null) {
            await records.bindIdentity(device, transaction.fingerprint);
          } else {
            // 遗忘记录不会因迟到事务重建；只回收该记录的私钥和原连接。
            final key = File(_devicePath(device));
            if (await key.exists()) await key.delete();
          }
        case IdentityTransactionKind.useGlobal:
          if (records.current.find(device!) != null) {
            await records.bindIdentity(device, null);
          }
        case IdentityTransactionKind.retire:
          break;
      }
      await _markUnauthorized(transaction.affected);
    } catch (error, stack) {
      failure = error;
      trace = stack;
    }
    final cleanupError = await cleanup;
    failure ??= cleanupError?.$1;
    trace ??= cleanupError?.$2;
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    await _finishTransaction();
    _unblock(transaction.affected, global: transaction.global);
  }

  Future<IdentitySelection> selectForDevice([String? deviceId]) async {
    if (deviceId != null) _requireDevice(deviceId);
    final custom =
        deviceId != null &&
        records.current.deviceIdentityFingerprints.containsKey(deviceId);
    if ((deviceId != null &&
            (_blocked.contains(deviceId) || _mutating.contains(deviceId))) ||
        (!custom && (_globalBlocked || _mutatingGlobal))) {
      _fail('identity_changed', '授权身份正在核对或清理，请稍后重新连接。');
    }
    final generation = deviceId == null
        ? _globalGeneration
        : (_generations[deviceId] ?? 0);
    final info = await identities.inspectIdentity(
      custom ? _devicePath(deviceId) : _globalPath,
    );
    if ((deviceId == null
                ? _globalGeneration
                : (_generations[deviceId] ?? 0)) !=
            generation ||
        deviceId != null &&
            (_blocked.contains(deviceId) || _mutating.contains(deviceId)) ||
        !custom && (_globalBlocked || _mutatingGlobal)) {
      _fail('identity_changed', '读取期间授权身份已改变。');
    }
    if (info == null) _fail('identity_unavailable', '已绑定的授权身份材料缺失，不会自动回退其他密钥。');
    final expected = custom
        ? records.current.deviceIdentityFingerprints[deviceId]
        : records.current.identityFingerprint;
    if (info.fingerprint != expected) {
      _fail('identity_changed', '授权身份文件已改变，请重新核验。');
    }
    return IdentitySelection(
      custom ? _devicePath(deviceId) : _globalPath,
      info.fingerprint,
      custom ? 'device' : 'global',
      generation,
      deviceId,
    );
  }

  Future<void> validateSelection(
    IdentitySelection selection, {
    String? deviceId,
  }) async {
    if (selection.deviceId != null &&
        deviceId != null &&
        selection.deviceId != deviceId) {
      _fail('identity_changed', '身份选择属于另一台设备。');
    }
    if (selection.deviceId == null && selection.scope == 'device') {
      if (!_candidates.contains(selection.path)) {
        _fail('identity_changed', '专属身份候选已经结束。');
      }
      final info = await _inspect(selection.path);
      if (!_candidates.contains(selection.path) ||
          info.fingerprint != selection.fingerprint) {
        _fail('identity_changed', '专属身份候选已改变。');
      }
      return;
    }
    // 未绑定全局候选属于全局代次；新记录的独立代次不能代替它。
    final selected = await selectForDevice(selection.deviceId);
    if (selected.path != selection.path ||
        selected.fingerprint != selection.fingerprint ||
        selected.generation != selection.generation) {
      _fail('identity_changed', '授权身份已改变，此次连接不能继续。');
    }
  }

  Future<AuthorizationIdentity> read({String? deviceId}) =>
      _exclusive(() async {
        if (deviceId != null) _checkDeviceId(deviceId);
        return _projection(await selectForDevice(deviceId));
      });

  Future<AuthorizationIdentity> importKey(
    String privateKeyPem, {
    String? deviceId,
  }) => _exclusive(() async {
    if (deviceId != null) _checkDeviceId(deviceId);
    return _replace(deviceId, _pem(privateKeyPem));
  });

  Future<AuthorizationIdentity> resetGlobal() => _exclusive(() async {
    final candidate = await _candidate();
    try {
      await identities.prepareIdentity(candidate.path);
      return await _replace(null, await candidate.readAsString());
    } finally {
      await _removeCandidate(candidate);
    }
  });

  Future<AuthorizationIdentity> useGlobal(String deviceId) =>
      _exclusive(() async {
        _checkDeviceId(deviceId);
        return _useGlobal(deviceId);
      });

  Future<AuthorizationIdentity> _replace(String? device, String pem) async {
    final intended = await _validate(pem);
    final affected = _affected(device);
    if (affected.any(_blocked.contains) || device == null && _globalBlocked) {
      _fail('identity_changed', '上次身份变更尚待核对或清理。');
    }
    final path = device == null ? _globalPath : _devicePath(device);
    final old = await identities.inspectIdentity(path);
    await _startTransaction(
      IdentityTransaction(
        kind: IdentityTransactionKind.key,
        affected: affected,
        global: device == null,
        deviceId: device,
        previousFingerprint: old?.fingerprint,
        fingerprint: intended.fingerprint,
      ),
    );
    _mutating.addAll(affected);
    _mutatingGlobal = device == null;
    late AdbIdentityCommitReceipt receipt;
    try {
      receipt = await identities.replaceIdentity(
        path,
        pem,
        expectedFingerprint: old?.fingerprint,
      );
    } catch (_) {
      // SDK 的异常保证尚未发布；事务删除失败仍留待重开核对。
      await _finishTransaction();
      rethrow;
    } finally {
      _mutating.removeAll(affected);
      _mutatingGlobal = false;
    }
    if (receipt.state == AdbIdentityCommitState.unchanged &&
        receipt.error != null) {
      await _finishTransaction();
      _fail('identity_conflict', '授权身份被其他写入改变，请重新核验。');
    }
    if (receipt.state == AdbIdentityCommitState.unknown) {
      _uncertain.addAll(affected);
      _globalUncertain |= device == null;
      await _retire(affected, global: device == null, retainBlocked: true);
      _fail('identity_result_unknown', '授权身份提交结果未知，请重新打开并核对，不要重复提交。');
    }
    // 文件发布后即撤准入；即使公开元数据写入失败，也不能放行旧握手。
    final cleanup = _settle(_beginRetirement(affected, global: device == null));
    Object? failure;
    StackTrace? trace;
    var metadataCommitted = false;
    try {
      final info = await _inspect(path);
      if (info.fingerprint != intended.fingerprint) {
        _fail('identity_conflict', '发布后身份文件又被改变，需要重新核对。');
      }
      if (device == null) {
        await records.setIdentityFingerprints(global: info.fingerprint);
      } else {
        await records.bindIdentity(device, info.fingerprint);
      }
      await _markUnauthorized(affected);
      metadataCommitted = true;
    } catch (error, stack) {
      failure = error;
      trace = stack;
      _uncertain.addAll(affected);
      _globalUncertain |= device == null;
    }
    final cleanupError = await cleanup;
    failure ??= cleanupError?.$1;
    trace ??= cleanupError?.$2;
    if (failure != null) {
      if (!metadataCommitted) {
        throw const RequestFailure(
          'identity_result_unknown',
          '私钥已发布，但身份记录未完整提交；请重新打开核对，不要重复提交。',
        );
      }
      Error.throwWithStackTrace(failure, trace!);
    }
    await _finishTransaction();
    _unblock(affected, global: device == null);
    return _projection(await selectForDevice(device))
        .copyWith(affectedDeviceIds: affected.toList());
  }

  Future<AuthorizationIdentity> _useGlobal(String device) async {
    if (_blocked.contains(device)) _fail('identity_changed', '上次身份变更尚待核对或清理。');
    await selectForDevice();
    await _startTransaction(
      IdentityTransaction(
        kind: IdentityTransactionKind.useGlobal,
        affected: {device},
        global: false,
        deviceId: device,
      ),
    );
    final cleanup = _settle(_beginRetirement({device}, global: false));
    Object? failure;
    StackTrace? trace;
    try {
      await records.bindIdentity(device, null);
      await _markUnauthorized({device});
    } catch (error, stack) {
      _uncertain.add(device);
      failure = const RequestFailure(
        'identity_result_unknown',
        '身份来源记录尚未完整提交，请重新打开核对。',
      );
      trace = stack;
    }
    final cleanupError = await cleanup;
    failure ??= cleanupError?.$1;
    trace ??= cleanupError?.$2;
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    await _finishTransaction();
    _unblock({device}, global: false);
    return _projection(await selectForDevice(device))
        .copyWith(affectedDeviceIds: [device]);
  }

  /// 只重试尚未完成的资源清理，不重放密钥替换。
  Future<void> retryCleanup() => _exclusive(() async {
    final ids = Set<String>.of(_pending);
    final global = _pendingGlobal;
    if (ids.isEmpty && !global) return;
    await _invalidate(Set.unmodifiable(ids), global: global);
    await _markUnauthorized(ids);
    if (_transaction != null && _uncertain.isEmpty && !_globalUncertain) {
      await _finishTransaction();
    }
    _unblock(ids, global: global);
  });

  Future<void> _retire(
    Set<String> ids, {
    required bool global,
    bool retainBlocked = false,
  }) async {
    final cleanup = _settle(_beginRetirement(ids, global: global));
    try {
      await _markUnauthorized(ids);
    } finally {
      final error = await cleanup;
      if (error != null) Error.throwWithStackTrace(error.$1, error.$2);
    }
    if (!retainBlocked) _unblock(ids, global: global);
  }

  Future<void> _beginRetirement(Set<String> ids, {required bool global}) {
    for (final id in ids) {
      _generations[id] = (_generations[id] ?? 0) + 1;
    }
    if (global) _globalGeneration++;
    _blocked.addAll(ids);
    _pending.addAll(ids);
    _globalBlocked |= global;
    _pendingGlobal |= global;
    // 调用方承诺同步撤准入；同步异常也转为回执，让后续元数据清理继续。
    return Future.sync(
      () => _invalidate(Set.unmodifiable(ids), global: global),
    );
  }

  Future<void> _markUnauthorized(Set<String> ids) async {
    for (final id in ids) {
      if (records.current.find(id) == null) continue;
      await records.update(
        id,
        (record) => record.copyWith(
          status: 'unauthorized',
          autoReconnect: false,
          reason: '授权密钥已改变，需要重新授权。',
        ),
      );
    }
  }

  void _unblock(Set<String> ids, {required bool global}) {
    _blocked.removeAll(ids.difference(_uncertain));
    _pending.removeAll(ids);
    if (global) {
      _globalBlocked = _globalUncertain;
      _pendingGlobal = false;
    }
  }

  Set<String> _affected(String? device) => device != null
      ? {device}
      : {
          for (final record in records.current.devices)
            if (!records.current.deviceIdentityFingerprints.containsKey(
              record.id,
            ))
              record.id,
        };

  /// 候选在绑定完成前仅属于本次 setup；取消不得发布成已有设备身份。
  Future<IdentityAttempt> prepareSetup({
    SetupIdentity? identity,
    String? deviceId,
  }) async {
    if (identity == null) {
      return _IdentityAttempt._(this, await selectForDevice(deviceId), null);
    }
    if (deviceId != null) _fail('identity_read_only', '已有设备的授权身份只读。');
    switch (identity) {
      case GlobalSetupIdentity():
        return _IdentityAttempt._(this, await selectForDevice(), null);
      case DedicatedSetupIdentity(:final privateKeyPem):
        final pem = _pem(privateKeyPem);
        final info = await _validate(pem);
        final candidate = await _candidate();
        try {
          await _install(candidate.path, pem, null);
          _candidates.add(candidate.path);
          return _IdentityAttempt._(
            this,
            IdentitySelection(
              candidate.path,
              info.fingerprint,
              'device',
              0,
              null,
            ),
            candidate,
          );
        } catch (_) {
          await _removeCandidate(candidate);
          rethrow;
        }
    }
  }

  Future<void> _bindAttempt(_IdentityAttempt attempt, String id) =>
      _exclusive(() async {
        _checkCandidate(attempt);
        _requireDevice(id);
        if (_transaction != null) _fail('identity_changed', '上次身份事务尚未确认。');
        if (records.current.deviceIdentityFingerprints.containsKey(id)) {
          _fail('identity_read_only', '设备已经绑定专属身份。');
        }
        if (attempt._candidate == null) {
          await validateSelection(attempt.selection);
          _checkCandidate(attempt);
          attempt._selection = await selectForDevice(id);
          return;
        }
        final destination = _devicePath(id);
        final existing = await identities.inspectIdentity(destination);
        _checkCandidate(attempt);
        final pem = await attempt._candidate.readAsString();
        _checkCandidate(attempt);
        final info = await _validate(pem);
        _checkCandidate(attempt);
        if (info.fingerprint != attempt.selection.fingerprint) {
          _fail('identity_changed', '专属候选材料已经改变。');
        }
        await _startTransaction(
          IdentityTransaction(
            kind: IdentityTransactionKind.key,
            affected: {id},
            global: false,
            deviceId: id,
            previousFingerprint: existing?.fingerprint,
            fingerprint: info.fingerprint,
          ),
        );
        try {
          _checkCandidate(attempt);
        } catch (_) {
          await _finishTransaction();
          rethrow;
        }
        // 此后替换已经开始，取消等待真实结果，不能把已发布密钥当作未发布。
        try {
          await _install(destination, pem, existing?.fingerprint);
          // 只有此提交成功后连接调用方才能发布新设备；候选文件发布不代表已绑定。
          await records.bindIdentity(id, attempt.selection.fingerprint);
          attempt._selection = await selectForDevice(id);
          await _finishTransaction();
        } catch (_) {
          _blocked.add(id);
          _uncertain.add(id);
          _pending.add(id);
          _generations[id] = (_generations[id] ?? 0) + 1;
          // setup 的连接回收由其调用方完成；这里不能反向等待同一连接准入队列。
          _fail('identity_result_unknown', '专属身份绑定尚未完整确认，请重新打开核对，不要重复提交。');
        }
      });

  void _checkCandidate(_IdentityAttempt attempt) {
    if (attempt._disposed ||
        attempt._candidate != null &&
            !_candidates.contains(attempt._candidate.path)) {
      _fail('identity_changed', '此次身份候选已取消，不能继续发布。');
    }
  }

  /// 设备记录删除成功后调用；仅回收私钥，不删除或重新建立设备记录。
  Future<void> forgetDevice(String id) => _exclusive(() async {
    if (!validDeviceId(id)) _fail('invalid_device_id', '设备标识无效。');
    if (records.current.find(id) != null) _fail('identity_in_use', '请先移除设备记录。');
    final file = File(_devicePath(id));
    if (await file.exists()) await file.delete();
    _generations.remove(id);
    _blocked.remove(id);
    _pending.remove(id);
  });

  Future<AdbIdentityInfo> _validate(String pem) async {
    try {
      return await identities.validateIdentity(_pem(pem));
    } catch (_) {
      _fail('invalid_identity', '私钥须为 RSA-2048、指数 65537 的有效 PEM。');
    }
  }

  Future<AdbIdentityInfo> _inspect(String path) async =>
      await identities.inspectIdentity(path) ??
      (throw const RequestFailure('identity_unavailable', '授权身份材料缺失。'));
  Future<void> _install(String path, String pem, String? expected) async {
    final receipt = await identities.replaceIdentity(
      path,
      pem,
      expectedFingerprint: expected,
    );
    if (receipt.state == AdbIdentityCommitState.unknown) {
      _fail('identity_result_unknown', '私钥文件提交结果未知，请核对后继续。');
    }
    if (receipt.error != null) _fail('identity_conflict', '私钥文件已改变，未完成绑定。');
  }

  Future<File> _candidate() async {
    final temporary = await Directory(p.join(directory.path, 'identities'))
        .createTemp('.candidate-');
    return File(p.join(temporary.path, 'identity.pem'));
  }

  Future<void> _removeCandidate(File file) async {
    await file.parent.delete(recursive: true);
  }

  void _requireDevice(String id) {
    if (records.current.find(id) == null) _fail('not_found', '这台设备的本机记录已不存在。');
  }

  void _checkDeviceId(String id) {
    if (!validDeviceId(id)) _fail('invalid_device_id', '设备标识无效。');
    _requireDevice(id);
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

final class _IdentityAttempt implements IdentityAttempt {
  _IdentityAttempt._(this._owner, this._selection, this._candidate);
  final AdbIdentityService _owner;
  IdentitySelection _selection;
  @override
  IdentitySelection get selection => _selection;
  final File? _candidate;
  bool _disposed = false;
  bool _bound = false;
  bool _cleaned = false;
  Future<void>? _disposing;
  @override
  Future<void> bindNew(String id) async {
    if (_disposed || _bound) _fail('identity_changed', '此次身份选择已经结束。');
    _bound = true;
    await _owner._bindAttempt(this, id);
  }

  @override
  Future<void> dispose() {
    if (_cleaned) return Future<void>.value();
    if (_disposing case final pending?) return pending;
    _disposed = true;
    if (_candidate != null) _owner._candidates.remove(_candidate.path);
    final operation = _owner
        ._exclusive(() async {
          if (_candidate != null) await _owner._removeCandidate(_candidate);
          _cleaned = true;
        })
        .catchError((Object error, StackTrace stack) {
          _disposing = null;
          Error.throwWithStackTrace(error, stack);
        });
    return _disposing = operation;
  }
}

AuthorizationIdentity _projection(IdentitySelection selection) =>
    AuthorizationIdentity(
      deviceId: selection.deviceId,
      scope: IdentityScope.values.byName(selection.scope),
      fingerprint: selection.fingerprint,
    );
String _pem(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      utf8.encode(value).length > 32 * 1024) {
    _fail('invalid_identity', '私钥必须为不超过 32 KiB 的 PEM 文本。');
  }
  return value;
}

Never _fail(String code, String message) => throw RequestFailure(code, message);

Future<(Object, StackTrace)?> _settle(Future<void> cleanup) async {
  try {
    await cleanup;
    return null;
  } catch (error, stack) {
    return (error, stack);
  }
}
