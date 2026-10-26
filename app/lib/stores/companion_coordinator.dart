import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/stores/companion_client.dart';
import 'package:scrcpy_connect/stores/companion_recovery.dart';

typedef CompanionEmitter = void Function(
  String type,
  String? device,
  Map<String, Object?> data,
);

/// 已通过当前部署和精确连接核验的事件；观察意图仍由观察协调器核验。
final class CompanionUpdate {
  const CompanionUpdate(this.device, this.connection, this.type, this.data);
  final String device, type;
  final DeviceConnection connection;
  final Map<String, Object?> data;
}

final class _Deployment {
  _Deployment(this.device, this.connection, this.client);
  final String device;
  final DeviceConnection connection;
  final CompanionClient client;
  final cancellation = AdbCancellation();
  StreamSubscription<Map<String, Object?>>? subscription;
  Map<String, Object?>? ready;
  bool retired = false;
  Future<void>? releasing;
}

/// 按精确设备连接拥有唯一部署，不拥有设备连接本身。
/// 通知及通话的用户意图、订阅代次由 ObservationCoordinator 负责。
final class CompanionCoordinator {
  CompanionCoordinator({
    required this.requireConnection,
    required Uint8List serverBytes,
    required this.config,
    required this.emit,
    this.recovery,
    this.deviceSerial,
  }) : _serverBytes = Uint8List.fromList(serverBytes);

  final DeviceConnection Function(String) requireConnection;
  final Uint8List _serverBytes;
  final CompanionConfig config;
  final CompanionEmitter emit;
  final CompanionRecovery? recovery;
  final String? Function(String)? deviceSerial;
  final _deployments = <String, _Deployment>{};
  final _retiring = <_Deployment>{};
  final _tails = <String, Future<void>>{};
  final _updates = StreamController<CompanionUpdate>.broadcast(sync: true);
  bool _closed = false;
  Future<void>? _closing;

  Stream<CompanionUpdate> get updates => _updates.stream;

  bool handles(String name) => const {'apps.list', 'apps.icon'}.contains(name);

  DeviceConnection? currentConnection(String device) {
    try {
      return requireConnection(device);
    } catch (_) {
      return null;
    }
  }

  bool hasActive(String device) {
    final entry = _deployments[device];
    return entry != null && entry.ready != null && _current(entry);
  }

  Map<String, Object?> capabilityState(String device) {
    final entry = _deployments[device];
    if (entry == null || !_current(entry) || entry.ready == null) {
      return const {'status': 'unknown', 'live': false};
    }
    return {
      'status': 'available',
      'live': true,
      'protocol': entry.ready!['protocol'],
      'apiLevel': entry.ready!['apiLevel'],
    };
  }

  bool _current(_Deployment entry) =>
      !_closed &&
      !entry.retired &&
      identical(_deployments[entry.device], entry) &&
      identical(currentConnection(entry.device), entry.connection);

  void _check(_Deployment entry) {
    if (!_current(entry)) {
      throw const CompanionException('cancelled', '互联服务所属连接已变化。');
    }
  }

  Future<T> _serial<T>(String device, Future<T> Function() action) {
    final result = (_tails[device] ?? Future<void>.value()).then(
      (_) => action(),
    );
    _tails[device] = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _retire(_Deployment entry) {
    if (entry.retired) return;
    entry.retired = true;
    _retiring.add(entry);
    entry.cancellation.cancel();
  }

  Future<void> _release(_Deployment entry) => entry.releasing ??= (() async {
    final journal = recovery;
    final connection = entry.connection;
    Future<bool> closed() async =>
        journal != null &&
        (await connection.client.services.connectionFacts(connection.device))
            .closed;
    var detached = await closed();
    if (!detached) {
      try {
        await entry.client.close();
      } catch (_) {
        if (!await closed()) rethrow;
        detached = true;
      }
    }
    if (detached) {
      await entry.client.detachClosedConnection();
      final identity = entry.client.deploymentIdentity;
      if (identity != null) {
        final serial = deviceSerial?.call(entry.device);
        if (serial == null || serial.isEmpty) {
          throw const CompanionException(
            'cleanup_unconfirmed',
            '缺少原设备身份，不能移交互联服务清理。',
          );
        }
        // 写入成功前原 entry 与 identity 不移除；本机释放不冒充远端已退出。
        await journal!.remember(entry.device, serial, identity);
      }
    }
    await entry.subscription?.cancel();
    _retiring.remove(entry);
    if (identical(_deployments[entry.device], entry)) {
      _deployments.remove(entry.device);
    }
  })().whenComplete(() => entry.releasing = null);

  /// 候选已核验同设备，但尚未准入；只回收旧部署，不启动观察或重放动作。
  Future<void> prepareConnection(
    String device,
    DeviceConnection connection,
    String? observedSerial,
    AdbCancellation cancellation,
  ) async {
    await recovery?.recover(device, observedSerial, connection, cancellation);
  }

  Future<_Deployment> _obtain(
    String device,
    DeviceConnection connection,
    bool allowStart,
  ) => _serial(device, () async {
    if (_closed || !identical(currentConnection(device), connection)) {
      throw const CompanionException('cancelled', '设备连接已停止准入。');
    }
    final existing = _deployments[device];
    if (existing != null && _current(existing)) return existing;
    if (existing != null) _retire(existing);
    for (final entry in _retiring.where((e) => e.device == device).toList()) {
      await _release(entry);
    }
    if (!allowStart) {
      throw const CompanionException('observation_required', '当前连接尚未建立互联服务。');
    }
    if (_closed || !identical(currentConnection(device), connection)) {
      throw const CompanionException('cancelled', '设备连接已变化。');
    }
    final entry = _Deployment(
      device,
      connection,
      CompanionClient(
        connection: connection,
        serverBytes: _serverBytes,
        config: config,
      ),
    );
    _deployments[device] = entry;
    entry.subscription = entry.client.events.listen(
      (event) => _event(entry, event),
      onError: (Object error) => _lost(entry, error),
      onDone: () =>
          _lost(entry, const CompanionException('disconnected', '互联服务已结束。')),
    );
    try {
      // 发布属于启动事务；消费者抛错也必须回收已登记但尚未启动的所有者。
      emit('companion.starting', device, const {'status': 'starting'});
      entry.ready = await entry.client.start(cancellation: entry.cancellation);
      _check(entry);
      emit('companion.ready', device, capabilityState(device));
      return entry;
    } catch (error, stack) {
      _retire(entry);
      try {
        await _release(entry);
      } catch (cleanup) {
        throw CompanionException(
          'cleanup_unconfirmed',
          '部署失败且精确资源尚未关闭：$cleanup',
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  });

  void _lost(_Deployment entry, Object error) {
    if (!_current(entry)) return;
    _retire(entry);
    // 先启动精确回收，通知消费者的异常不能阻断资源清理。
    // 关闭失败仍在 _retiring 中，后续 stop/close 继续重试同一对象。
    unawaited(_release(entry).catchError((Object _) {}));
    _updates.add(
      CompanionUpdate(entry.device, entry.connection, 'companion.stopped', {
        'status': 'unknown',
        'live': false,
        'reason': error is CompanionException ? error.message : '互联服务连接失效。',
      }),
    );
    _emitEvent('companion.stopped', entry.device, const {
      'status': 'unknown',
      'live': false,
    });
  }

  void _event(_Deployment entry, Map<String, Object?> message) {
    if (!_current(entry)) return;
    final type = message['event'];
    if (type is! String) return;
    if (type == 'companion.error') {
      _lost(entry, const CompanionException('companion_error', '被控互联服务失败。'));
      return;
    }
    final raw = message['data'];
    if (raw is! Map<String, Object?>) return;
    final data = Map<String, Object?>.unmodifiable({
      ...raw,
      'deviceId': entry.device,
    });
    if (type == 'notifications.changed' ||
        type == 'calls.changed' ||
        type == 'calls.incoming') {
      _updates.add(CompanionUpdate(entry.device, entry.connection, type, data));
    }
  }

  void _emitEvent(String type, String device, Map<String, Object?> data) {
    try {
      emit(type, device, data);
    } catch (_) {
      // 仅隔离应用事件消费者；远端 RPC、部署和资源回收错误不经过此捕获。
    }
  }

  Future<Map<String, Object?>> command(
    String name,
    Map<String, Object?> params, {
    AdbCancellation? cancellation,
  }) {
    if (!handles(name)) {
      throw const CompanionException('unknown_command', '未知互联命令。');
    }
    final device = params['deviceId'];
    if (device is! String || device.isEmpty) {
      throw const CompanionException('invalid_argument', '请指定设备。');
    }
    if (params['allowStart'] != null && params['allowStart'] is! bool) {
      throw const CompanionException('invalid_argument', '启动许可必须是布尔值。');
    }
    if (name == 'apps.list') {
      final filter = params['filter'];
      if (!params.containsKey('filter') || filter == 'installed') {
        throw const CompanionException('unsupported', '已安装应用列表由应用清单读取器负责。');
      }
      if (filter != 'running') {
        throw const CompanionException('invalid_argument', '应用列表筛选条件无效。');
      }
    }
    if (name == 'apps.icon') {
      final package = params['packageName'];
      if (package is! String ||
          package.length > 255 ||
          !RegExp(r'^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*$').hasMatch(package)) {
        throw const CompanionException('invalid_argument', '请指定有效的应用包名。');
      }
    }
    return request(
      device,
      name,
      params,
      allowStart: params['allowStart'] != false,
      cancellation: cancellation,
    );
  }

  /// 观察协调器也使用同一部署；expectedConnection 固定请求准入时的连接。
  Future<Map<String, Object?>> request(
    String device,
    String name,
    Map<String, Object?> params, {
    required bool allowStart,
    DeviceConnection? expectedConnection,
    AdbCancellation? cancellation,
  }) async {
    // 连接退休先撤准入，仍允许原操作在原部署上确认远端子进程退出。
    // 此入口不能启动助手、选择后继连接或对其他命令绕过当前连接核验。
    if (name == 'media.thumbnail.cancel' &&
        !allowStart &&
        expectedConnection != null) {
      final candidates = <_Deployment>{
        ?_deployments[device],
        ..._retiring.where((entry) => entry.device == device),
      }.where((entry) => identical(entry.connection, expectedConnection));
      if (candidates.length != 1) {
        throw const CompanionException(
          'media_cleanup_unknown',
          '原媒体任务的精确部署已不可访问，无法确认远端任务退出。',
        );
      }
      final entry = candidates.single;
      cancellation?.check();
      final value = await entry.client.request(
        name,
        Map<String, Object?>.from(params)
          ..remove('deviceId')
          ..remove('allowStart'),
        mutation: true,
        cancellation: cancellation,
      );
      if (value is! Map<String, Object?>) {
        throw const CompanionException('protocol_error', '互联回执不是对象。');
      }
      return {...value, 'deviceId': device};
    }
    if (_closed) throw const CompanionException('closed', '互联服务所有者已关闭。');
    cancellation?.check();
    final connection = expectedConnection ?? requireConnection(device);
    // 部署可能异步等待；在准入时固定嵌套参数，防止调用方改写动作目标。
    final payload =
        Map<String, Object?>.from(jsonDecode(jsonEncode(params)) as Map)
          ..remove('deviceId')
          ..remove('allowStart');
    final entry = await _obtain(device, connection, allowStart);
    _check(entry);
    cancellation?.check();
    final value = await entry.client.request(
      name,
      payload,
      mutation: !const {
        'apps.list',
        'apps.icon',
        'notifications.list',
        'calls.list',
        'observation.set',
      }.contains(name),
      cancellation: cancellation,
    );
    _check(entry);
    if (value is! Map<String, Object?>) {
      throw const CompanionException('protocol_error', '互联回执不是对象。');
    }
    return {...value, 'deviceId': device};
  }

  Future<void> stopForConnection(
    String device,
    DeviceConnection connection,
  ) async {
    final entry = _deployments[device];
    if (entry != null && identical(entry.connection, connection)) {
      _retire(entry);
    }
    for (final old
        in _retiring
            .where(
              (e) => e.device == device && identical(e.connection, connection),
            )
            .toList()) {
      await _release(old);
    }
  }

  Future<void> close() {
    if (_closing case final pending?) return pending;
    _closed = true;
    for (final entry in _deployments.values.toList()) {
      _retire(entry);
    }
    return _closing = _close().catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _close() async {
    Object? failure;
    StackTrace? trace;
    for (final entry in _retiring.toList()) {
      try {
        await _release(entry);
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
    }
    await Future.wait(_tails.values.toList());
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    await _updates.close();
  }
}
