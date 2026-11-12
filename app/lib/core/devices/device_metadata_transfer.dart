import 'dart:async';

import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/models/device_metadata.dart';
import 'package:scrcpy_connect/core/devices/models/device_records_import.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 元数据迁移的设备侧所有者；连接排空在设置队列之外，冻结覆盖整次提交。
/// 调用方在自己的保存队列内复核版本后使用本次提交函数，不能将它带出作用域。
final class DeviceMetadataTransfer {
  DeviceMetadataTransfer({
    required this._records,
    required this._prepareImport,
    required this._holdReconnect,
    required this._onImported,
    required this._isDisposed,
  });

  final DeviceRecordStorage _records;
  final Future<void> Function() _prepareImport;
  final Future<void> Function() Function() _holdReconnect;
  final void Function() _onImported;
  final bool Function() _isDisposed;
  final _pending = <Future<void>>{};
  final _releases = <Future<void> Function()>{};
  bool _closed = false;
  Future<void>? _closing;

  void _checkOpen() {
    if (_closed || _isDisposed()) {
      throw const RequestFailure('disposed', '设备迁移所有者已关闭。');
    }
  }

  Future<DeviceMetadata> export({
    required Map<String, Object?> settings,
  }) async {
    _checkOpen();
    await _records.reload();
    _checkOpen();
    return _records.exportMetadata(settings: settings);
  }

  Future<DeviceRecordsImport?> preview(DeviceMetadata metadata) {
    _checkOpen();
    return _records.previewMetadata(metadata);
  }

  Future<T> import<T>(
    DeviceMetadata metadata, {
    required bool importGlobalPreferences,
    required Future<T> Function(Future<DeviceRecordsImport> Function() commit)
    apply,
  }) {
    _checkOpen();
    final result = Completer<T>();
    final settled = result.future.then<void>((_) {}, onError: (Object _) {});
    _pending.add(settled);
    unawaited(settled.then((_) => _pending.remove(settled)));
    unawaited(
      _import(
        metadata,
        importGlobalPreferences: importGlobalPreferences,
        apply: apply,
      ).then(result.complete, onError: result.completeError),
    );
    return result.future;
  }

  Future<T> _import<T>(
    DeviceMetadata metadata, {
    required bool importGlobalPreferences,
    required Future<T> Function(Future<DeviceRecordsImport> Function() commit)
    apply,
  }) async {
    await _prepareImport();
    _checkOpen();
    final resume = _holdReconnect();
    _releases.add(resume);
    var active = true;
    Future<DeviceRecordsImport>? saving;
    Future<DeviceRecordsImport> commit() {
      _checkOpen();
      if (!active) {
        throw const RequestFailure('cancelled', '本次设备导入已结束。');
      }
      if (saving case final existing?) return existing;
      final accepted = saving = _save(metadata, importGlobalPreferences);
      unawaited(accepted.then<void>((_) {}, onError: (Object _) {}));
      return accepted;
    }

    try {
      return await apply(commit);
    } finally {
      active = false;
      // 调用方提前失败也必须等已受理的保存结束；业务错误由原调用方解释。
      try {
        await saving;
      } catch (_) {
        /* 原提交回执保留失败结果，不把业务失败当成资源释放失败。 */
      }
      await _release(resume);
    }
  }

  Future<DeviceRecordsImport> _save(
    DeviceMetadata metadata,
    bool global,
  ) async {
    final result = await _records.importMetadata(
      metadata,
      importGlobalPreferences: global,
    );
    // 核对出已有回执也重新交付当前投影；上次保存可能成功但通知没有交付。
    if (!_closed && !_isDisposed()) _onImported();
    return result;
  }

  Future<void> close() {
    _closed = true;
    return _closing ??= _drain().whenComplete(() => _closing = null);
  }

  Future<void> _release(Future<void> Function() resume) async {
    await resume();
    _releases.remove(resume);
  }

  Future<void> _drain() async {
    await Future.wait(_pending.toList());
    await Future.wait(_releases.toList().map(_release));
  }
}
