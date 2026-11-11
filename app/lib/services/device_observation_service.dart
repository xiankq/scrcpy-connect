import 'package:scrcpy_connect/models/companion_exception.dart';

import 'package:scrcpy_connect/models/device_connection.dart';
import 'package:scrcpy_connect/models/companion_update.dart';

import 'dart:async';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/services/device_record_storage.dart';
import 'package:scrcpy_connect/services/companion_service.dart';

Map<String, Object?> _unknown(String section, String phase, String reason) => {
  section: <Object?>[],
  'status': phase == 'stopped' ? 'stopped' : 'unknown',
  'live': false,
  'reason': reason,
};

final class _Observation {
  _Observation(this.wanted)
    : phase = wanted ? 'waiting_connection' : 'stopped' {
    clear('尚未建立当前连接的实时观察。');
  }
  bool wanted;
  bool intentCommitted = true;
  String phase;
  int epoch = 0, failures = 0;
  DeviceConnection? connection;
  AdbCancellation? operation;
  AdbCancellation admission = AdbCancellation();
  Timer? retry;
  final revisions = <String, int>{'notifications': 0, 'calls': 0};
  final sections = <String, Map<String, Object?>>{};
  void clear(String reason) {
    for (final section in revisions.keys) {
      revisions[section] = revisions[section]! + 1;
      sections[section] = _unknown(section, phase, reason);
    }
  }

  void invalidate(String reason) {
    epoch++;
    retry?.cancel();
    retry = null;
    operation?.cancel();
    operation = null;
    admission.cancel();
    admission = AdbCancellation();
    phase = wanted ? 'waiting_connection' : 'stopped';
    clear(reason);
  }
}

/// 设备记录持久化观察意图，本对象只持有本次连接的监听和快照。
/// 列表与状态读取不会部署服务；通知动作必须属于当前实时观察代次。
final class DeviceObservationService {
  DeviceObservationService({
    required this.companion,
    required this.records,
    required this.emit,
  }) {
    _subscription = companion.updates.listen(_update);
  }
  final CompanionService companion;
  final DeviceRecordStorage records;
  final CompanionEmitter emit;
  late final StreamSubscription<CompanionUpdate> _subscription;
  final _observations = <String, _Observation>{};
  final _tails = <String, Future<void>>{};
  final _tasks = <Future<void>>{};
  bool _closed = false, _paused = false;
  Future<void>? _closing;

  bool handles(String name) => const {
    'observation.list',
    'observation.status',
    'observation.start',
    'observation.stop',
    'notifications.list',
    'notifications.open',
    'notifications.dismiss',
    'calls.list',
    'calls.open',
    'calls.action',
  }.contains(name);

  DeviceRecord _record(String device) => records.current.devices.firstWhere(
    (record) => record.id == device,
    orElse: () => throw const CompanionException('not_found', '这台设备的本机记录已不存在。'),
  );
  _Observation _state(String device) => _observations.putIfAbsent(
    device,
    () => _Observation(_record(device).observationWanted),
  );
  bool _valid(
    String device,
    _Observation state,
    int epoch,
    DeviceConnection connection,
  ) =>
      !_closed &&
      !_paused &&
      identical(_observations[device], state) &&
      state.epoch == epoch &&
      identical(state.connection, connection) &&
      identical(companion.currentConnection(device), connection) &&
      companion.hasActive(device);

  Map<String, Object?> status(String device) {
    _record(device);
    final state = _state(device);
    final live =
        !_closed &&
        !_paused &&
        state.connection != null &&
        identical(companion.currentConnection(device), state.connection) &&
        companion.hasActive(device);
    final phase = !live && const {'observing', 'limited'}.contains(state.phase)
        ? (companion.currentConnection(device) == null
              ? 'waiting_connection'
              : 'failed')
        : state.phase;
    return {
      'deviceId': device,
      'wanted': state.wanted,
      'phase': phase,
      'generation': state.epoch,
      for (final section in state.sections.keys)
        section: phase != state.phase
            ? _unknown(section, phase, '实时观察连接已失效，等待重新核验。')
            : state.sections[section],
    };
  }

  List<Map<String, Object?>> list() => [
    for (final record in records.current.devices) status(record.id),
  ];
  void _publish(String device) {
    if (records.current.find(device) != null) {
      _emitEvent('observation.changed', device, status(device));
    }
  }

  Future<T> _track<T>(Future<T> action) {
    late final Future<void> settled;
    settled = action.then<void>((_) {}, onError: (Object _) {}).whenComplete(
      () {
        _tasks.remove(settled);
      },
    );
    _tasks.add(settled);
    return action;
  }

  Future<T> _serial<T>(String device, Future<T> Function() action) {
    final result = (_tails[device] ?? Future<void>.value()).then(
      (_) => action(),
    );
    _tails[device] = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Map<String, Object?>> command(
    String name,
    Map<String, Object?> params, {
    AdbCancellation? cancellation,
  }) {
    if (_closed) throw const CompanionException('closed', '观察所有者已关闭。');
    cancellation?.check();
    if (!handles(name)) {
      throw const CompanionException('unknown_command', '未知观察命令。');
    }
    if (name == 'observation.list') {
      return Future.value({'observations': list()});
    }
    final device = params['deviceId'];
    if (device is! String || device.isEmpty) {
      throw const CompanionException('invalid_argument', '请指定设备。');
    }
    _record(device);
    if (name == 'observation.status') return Future.value(status(device));
    if (name == 'observation.start' || name == 'observation.stop') {
      return _track(
        _setWanted(
          device,
          name == 'observation.start',
          cancellation,
          allowStart: params['allowStart'] != false,
        ),
      );
    }
    return _track(_content(device, name, Map.from(params), cancellation));
  }

  Future<Map<String, Object?>> _setWanted(
    String device,
    bool wanted,
    AdbCancellation? cancellation, {
    required bool allowStart,
  }) {
    final state = _state(device);
    // 同步撤销旧回执；持久化失败也不能恢复旧动作准入。
    state.wanted = wanted;
    state.intentCommitted = false;
    state.invalidate(wanted ? '正在建立实时观察。' : '已主动停止通知与来电观察。');
    final epoch = state.epoch;
    return _serial(device, () async {
      try {
        await records.setObservationWanted(device, wanted);
      } catch (error) {
        if (!_closed && state.epoch == epoch) {
          _failed(device, state, error, retry: false);
        }
        rethrow;
      }
      if (_closed || state.epoch != epoch) {
        throw const CompanionException('cancelled', '此观察意图已被替换。');
      }
      state.intentCommitted = true;
      cancellation?.check();
      _publish(device);
      final connection = companion.currentConnection(device);
      state.connection = connection;
      if (_paused || connection == null) return status(device);
      if (!wanted && !companion.hasActive(device)) return status(device);
      await _bind(
        device,
        state,
        connection,
        epoch,
        allowStart: wanted && allowStart,
        cancellation: cancellation,
      );
      return status(device);
    });
  }

  Future<void> _bind(
    String device,
    _Observation state,
    DeviceConnection connection,
    int epoch, {
    required bool allowStart,
    AdbCancellation? cancellation,
  }) async {
    if (_closed || _paused || !state.intentCommitted || state.epoch != epoch) {
      return;
    }
    state.connection = connection;
    state.phase = state.wanted ? 'starting' : 'stopped';
    final operation = state.operation = AdbCancellation();
    final unsubscribe = cancellation?.onCancel(operation.cancel);
    final revisions = Map<String, int>.from(state.revisions);
    _publish(device);
    try {
      final response = await companion.request(
        device,
        'observation.set',
        {'enabled': state.wanted, 'epoch': epoch},
        allowStart: allowStart,
        expectedConnection: connection,
        cancellation: operation,
      );
      if (!_valid(device, state, epoch, connection)) {
        throw const CompanionException('cancelled', '观察回执所属连接或意图已变化。');
      }
      if (response['observationEpoch'] is! int ||
          response['observationEpoch'] != epoch ||
          response['observationEnabled'] != state.wanted ||
          response['cleanupConfirmed'] != true) {
        throw const CompanionException(
          'observation_cleanup_unknown',
          '尚未确认远端观察监听完成切换。',
        );
      }
      for (final section in revisions.keys) {
        final raw = response[section];
        if (raw is! Map<String, Object?>) {
          throw const CompanionException('protocol_error', '观察快照缺少分区。');
        }
        if (state.revisions[section] == revisions[section]) {
          state.sections[section] = _decorate(device, section, raw);
        }
      }
      state.failures = 0;
      state.phase = !state.wanted
          ? 'stopped'
          : state.sections.values.any((v) => v['status'] == 'limited')
          ? 'limited'
          : 'observing';
      _publish(device);
    } catch (error) {
      if (!_closed && state.epoch == epoch) {
        _failed(device, state, error, retry: state.wanted && allowStart);
      }
      rethrow;
    } finally {
      unsubscribe?.call();
      if (identical(state.operation, operation)) state.operation = null;
    }
  }

  Map<String, Object?> _decorate(
    String device,
    String section,
    Map<String, Object?> raw,
  ) {
    if (raw[section] is! List<Object?> ||
        raw['status'] is! String ||
        raw['live'] is! bool ||
        (raw[section]! as List<Object?>).any(
          (value) => value is! Map<String, Object?>,
        )) {
      throw const CompanionException('protocol_error', '观察分区不是有效的实时快照。');
    }
    return Map.unmodifiable({
      ...raw,
      'deviceId': device,
      if (section == 'calls' && raw['calls'] is List<Object?>)
        'calls': [
          for (final call in raw['calls']! as List<Object?>)
            if (call is Map<String, Object?>)
              {...call, 'deviceId': device, 'deviceName': _record(device).name},
        ],
    });
  }

  Future<Map<String, Object?>> _content(
    String device,
    String name,
    Map<String, Object?> params,
    AdbCancellation? cancellation,
  ) async {
    final state = _state(device);
    final section = name.startsWith('notifications.')
        ? 'notifications'
        : 'calls';
    final view = status(device);
    final sectionView = view[section]! as Map<String, Object?>;
    if (name.endsWith('.list') &&
        (!state.wanted ||
            !const {'observing', 'limited'}.contains(view['phase']))) {
      return {...sectionView, 'deviceId': device};
    }
    if (_paused || !state.wanted || sectionView['live'] != true) {
      if (name.endsWith('.list')) return {...sectionView, 'deviceId': device};
      throw const CompanionException('observation_required', '请先核验此设备的实时观察。');
    }
    if (name == 'calls.open' && params.containsKey('callId')) {
      throw const CompanionException(
        'call_targeting_unavailable',
        '此入口不能定位指定通话。',
      );
    }
    final epoch = state.epoch, revision = state.revisions[section];
    final connection = state.connection!;
    final operation = AdbCancellation();
    final removeIntent = state.admission.onCancel(operation.cancel);
    final removeCaller = cancellation?.onCancel(operation.cancel);
    late final Map<String, Object?> response;
    try {
      response = await companion.request(
        device,
        name,
        params,
        allowStart: false,
        expectedConnection: connection,
        cancellation: operation,
      );
    } finally {
      removeIntent();
      removeCaller?.call();
    }
    if (!_valid(device, state, epoch, connection) ||
        !state.wanted ||
        !const {'observing', 'limited'}.contains(state.phase)) {
      throw const CompanionException('cancelled', '观察对象已失效，未交付旧回执。');
    }
    if (name.endsWith('.list')) {
      if (response['observationEpoch'] is! int ||
          response['observationEpoch'] != epoch ||
          response['observationEnabled'] != true) {
        throw const CompanionException('cancelled', '实时快照代次已失效。');
      }
      if (state.revisions[section] == revision) {
        state.sections[section] = _decorate(device, section, response);
      }
      return {...state.sections[section]!};
    }
    return response;
  }

  void _update(CompanionUpdate update) {
    final state = _observations[update.device];
    if (state == null || !identical(state.connection, update.connection)) {
      return;
    }
    if (update.type == 'companion.stopped') {
      if (!_closed) {
        _failed(
          update.device,
          state,
          const CompanionException('disconnected', '互联服务连接已失效。'),
          retry: state.wanted,
        );
      }
      return;
    }
    if (!_valid(update.device, state, state.epoch, update.connection) ||
        !state.wanted ||
        !const {'starting', 'observing', 'limited'}.contains(state.phase) ||
        update.data['observationEpoch'] is! int ||
        update.data['observationEpoch'] != state.epoch ||
        update.data['observationEnabled'] != true) {
      return;
    }
    final section = update.type.startsWith('notifications.')
        ? 'notifications'
        : 'calls';
    state.revisions[section] = state.revisions[section]! + 1;
    try {
      state.sections[section] = _decorate(update.device, section, update.data);
    } on CompanionException catch (error) {
      _failed(update.device, state, error, retry: false);
      return;
    }
    if (state.phase != 'starting') {
      state.phase =
          state.sections.values.any((value) => value['status'] == 'limited')
          ? 'limited'
          : 'observing';
    }
    _emitEvent(update.type, update.device, state.sections[section]!);
    _publish(update.device);
  }

  void _emitEvent(String type, String device, Map<String, Object?> data) {
    try {
      emit(type, device, data);
    } catch (_) {
      // 观察事实已提交；仅隔离通知消费者，不能让它夺走监听的精确关闭权。
    }
  }

  void _failed(
    String device,
    _Observation state,
    Object error, {
    required bool retry,
  }) {
    state.admission.cancel();
    state.admission = AdbCancellation();
    state.phase = companion.currentConnection(device) == null && state.wanted
        ? 'waiting_connection'
        : 'failed';
    state.clear(error is CompanionException ? error.message : '实时观察未完成。');
    _publish(device);
    state.retry?.cancel();
    if (!retry ||
        _closed ||
        _paused ||
        !state.wanted ||
        !state.intentCommitted) {
      return;
    }
    final failures = ++state.failures;
    final epoch = state.epoch;
    state.retry = Timer(
      Duration(seconds: 1 << (failures > 5 ? 5 : failures)),
      () {
        if (_closed || _paused || state.epoch != epoch || !state.wanted) return;
        final connection = companion.currentConnection(device);
        if (connection == null) return;
        state.invalidate('正在重新核验实时观察。');
        _track(_bind(device, state, connection, state.epoch, allowStart: true))
            .ignore();
      },
    );
  }

  /// 明确的连接发布钩子，恢复持久 wanted；列表读取不能替代此入口。
  Future<void> connectionChanged(String device) =>
      _track(_connectionChanged(device));
  Future<void> _connectionChanged(String device) async {
    final state = _state(device), old = _observations[device]?.connection;
    state.invalidate('连接已变化，实时内容等待重新核验。');
    final epoch = state.epoch;
    state.connection = null;
    _publish(device);
    if (old != null) await companion.stopForConnection(device, old);
    if (_closed ||
        _paused ||
        !state.wanted ||
        !state.intentCommitted ||
        state.epoch != epoch) {
      return;
    }
    final connection = companion.currentConnection(device);
    if (connection != null) {
      await _bind(device, state, connection, epoch, allowStart: true);
    }
  }

  void pause() {
    _paused = true;
    for (final entry in _observations.entries) {
      entry.value.invalidate('实时状态待核验，动作已暂停。');
      _publish(entry.key);
    }
  }

  /// 恢复只核验现存助手；不会因前台恢复而重新部署已结束的观察。
  Future<void> resume() async {
    if (_closed) throw const CompanionException('closed', '观察所有者已关闭。');
    _paused = false;
    for (final entry in _observations.entries.toList()) {
      final state = entry.value,
          connection = companion.currentConnection(entry.key);
      if (!state.wanted ||
          !state.intentCommitted ||
          connection == null ||
          !companion.hasActive(entry.key)) {
        continue;
      }
      await _track(
        _bind(entry.key, state, connection, state.epoch, allowStart: false),
      );
    }
  }

  Future<void> stopForConnection(
    String device,
    DeviceConnection connection,
  ) async {
    final state = _observations[device];
    if (state != null && identical(state.connection, connection)) {
      state.invalidate('连接已停止，实时观察内容已失效。');
      state.connection = null;
      _publish(device);
    }
    await companion.stopForConnection(device, connection);
  }

  /// 记录删除前由应用调用，撤销该记录的定时恢复和所有迟到回执。
  Future<void> forget(String device) async {
    final state = _observations.remove(device);
    if (state == null) return;
    state.invalidate('设备记录已删除。');
    final connection = state.connection;
    if (connection != null) {
      await companion.stopForConnection(device, connection);
    }
  }

  Future<void> close() {
    if (_closing case final pending?) return pending;
    _closed = true;
    for (final state in _observations.values) {
      state.invalidate('观察所有者已关闭。');
    }
    return _closing = _close().catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _close() async {
    await Future.wait(_tasks.toList());
    Object? failure;
    StackTrace? trace;
    for (final entry in _observations.entries) {
      final state = entry.value, connection = state.connection;
      if (connection == null || !companion.hasActive(entry.key)) continue;
      try {
        final result = await companion.request(
          entry.key,
          'observation.set',
          {'enabled': false, 'epoch': state.epoch},
          allowStart: false,
          expectedConnection: connection,
        );
        if (result['observationEnabled'] != false ||
            result['cleanupConfirmed'] != true ||
            result['observationEpoch'] != state.epoch) {
          throw const CompanionException(
            'observation_cleanup_unknown',
            '尚未确认观察监听已停止。',
          );
        }
        state.connection = null;
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    await _subscription.cancel();
  }
}
