// Public constructor dependency names remain independent of private storage.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'connection_policy.dart';
import 'interop_exception.dart';

typedef SetupJson = Map<String, dynamic>;
typedef SetupRequest = Future<SetupJson> Function(String, SetupJson);

/// Product setup flows. Every native call performs one leased execution;
/// this owner alone decides whether and when another call should be made.
class ConnectionSetupCoordinator {
  ConnectionSetupCoordinator({
    required SetupRequest request,
    required this.policy,
    required this.emit,
    this.authorizeUsb,
    this.releaseUsb,
    this.cancelUsb,
    this.holdDevice,
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
  }) : _request = request,
       _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final SetupRequest _request;
  final ConnectionPolicy policy;
  final void Function(SetupJson) emit;
  final Future<SetupJson> Function(SetupJson)? authorizeUsb;
  final Future<void> Function(SetupJson)? releaseUsb;
  final Future<void> Function(SetupJson)? cancelUsb;
  final Future<void> Function() Function(String)? holdDevice;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;
  final _flows = <String, _SetupFlow>{};
  bool _disposed = false, _recovering = false;
  int _next = 0, _revision = 0;
  final _stops = <String, int>{};

  bool handles(String command) => const {
    'devices.pair',
    'devices.pair.qr',
    'devices.usb',
    'devices.wireless',
  }.contains(command);

  void beforeRequest(String command, SetupJson params) {
    if (command.startsWith('identity.') && !command.endsWith('.get') ||
        command == 'settings.import') {
      for (final flow in _flows.values.toList()) {
        _cancel(flow);
      }
      return;
    }
    var id = params['deviceId'];
    final connectionStop =
        command == 'activities.stop' &&
        params['activityId'] is String &&
        (params['activityId'] as String).startsWith('connection:');
    if (command == 'activities.stop' && !connectionStop) return;
    if (connectionStop) {
      id = (params['activityId'] as String).substring(11);
    }
    if (id is String &&
        const {
          'devices.disconnect',
          'devices.forget',
          'activities.stop',
        }.contains(command)) {
      _stops[id] = ++_revision;
    }
    if (const {
      'devices.cancel',
      'devices.connect',
      'devices.disconnect',
      'devices.forget',
      'activities.stop',
    }.contains(command)) {
      for (final flow in _flows.values.toList()) {
        if (params['attemptId'] == flow.attempt ||
            id != null && id == flow.deviceId) {
          _cancel(flow);
        }
      }
    }
  }

  void handleEvent(SetupJson event) {
    if (event['type'] == 'state.resync' ||
        event['type'] == 'state.resync.failed') {
      _recovering = true;
    } else if (event['type'] == 'state.resynced') {
      _recovering = false;
    } else if (event['type'] == 'connections.stopped') {
      for (final flow in _flows.values.toList()) {
        _cancel(flow);
      }
    }
  }

  Future<SetupJson> request(String command, SetupJson params) async {
    if (_disposed) throw const InteropException('disposed', '连接协调器已释放。');
    policy.validate();
    final attempt =
        params['attemptId'] as String? ??
        'setup-${_now().microsecondsSinceEpoch}-${_next++}';
    final flow = _SetupFlow(
      attempt,
      params['deviceId'] as String?,
      _revision,
      _now().add(policy.setupLeaseTimeout),
    );
    for (final previous in _flows.values.toList()) {
      if (previous.attempt == attempt ||
          flow.deviceId != null && flow.deviceId == previous.deviceId) {
        _cancel(previous);
      }
    }
    _flows[attempt] = flow;
    _bind(flow, flow.deviceId);
    try {
      if (command == 'devices.pair.qr') {
        final receipt = await _request('adb.pair.qr', _lease(flow, params));
        flow.operation = receipt['operationId'] as String;
        _check(flow);
        unawaited(_finishQr(flow));
        return receipt;
      }
      if (command == 'devices.pair') {
        final receipt = await _request('adb.pair', _lease(flow, params));
        flow.operation = receipt['operationId'] as String;
        _check(flow);
        return await _afterPair(flow, receipt);
      }
      if (command == 'devices.usb') return await _usb(flow, params);
      if (command == 'devices.wireless') return await _tcpip(flow, params);
      throw const InteropException('unknown_command', '未知连接流程。');
    } finally {
      if (command != 'devices.pair.qr' ||
          flow.operation == null ||
          flow.cancelled) {
        await _finish(flow);
      }
    }
  }

  SetupJson _lease(_SetupFlow flow, SetupJson params) => {
    ...params,
    'attemptId': flow.attempt,
    'leaseMs': policy.setupLeaseTimeout.inMilliseconds,
  };

  void _bind(_SetupFlow flow, String? id) {
    if (id == null || flow.hold != null) return;
    flow.deviceId = id;
    if ((_stops[id] ?? -1) > flow.revision) {
      _cancel(flow);
      _check(flow);
    }
    flow.hold = holdDevice?.call(id);
  }

  Future<void> _finishQr(_SetupFlow flow) async {
    final deadline = _now().add(policy.qrPairingTimeout);
    try {
      while (true) {
        await _ready(flow);
        final state = await _request('adb.operation.get', {
          'operationId': flow.operation,
        });
        _check(flow);
        final outcome = _object(state['outcome']);
        if (outcome['status'] == 'completed') {
          final result = await _afterPair(flow, _object(outcome['result']));
          _check(flow);
          emit({
            'type': 'pairing.changed',
            'deviceId': flow.deviceId,
            'data': {
              'status': 'paired',
              'attemptId': flow.attempt,
              'result': result,
            },
          });
          return;
        }
        if (outcome['status'] == 'failed') {
          throw InteropException(
            outcome['code'] as String? ?? 'pairing_failed',
            outcome['message'] as String? ?? '配对执行失败。',
          );
        }
        if (!_now().isBefore(deadline)) {
          throw const InteropException('expired', '二维码已过期，请重新生成。');
        }
        await _delay(policy.setupPollInterval);
      }
    } catch (error) {
      if (!_disposed && !flow.cancelled) {
        final code = _code(error);
        emit({
          'type': 'pairing.changed',
          'data': {
            'attemptId': flow.attempt,
            'status': code == 'expired' ? 'expired' : 'failed',
            'code': code,
            'message': '$error',
          },
        });
      }
    } finally {
      await _finish(flow);
    }
  }

  Future<SetupJson> _afterPair(_SetupFlow flow, SetupJson paired) async {
    _bind(flow, paired['deviceId'] as String);
    if (paired['connected'] == true) return paired;
    final deadline = _now().add(policy.pairingDiscoveryTimeout);
    var generations = 0;
    Object? failure;
    while (_now().isBefore(deadline)) {
      await _ready(flow);
      try {
        final connected = await _request('devices.connect', {
          'deviceId': flow.deviceId,
          'attemptId': flow.attempt,
          'candidateSource': 'discovery',
          'parentOperationId': flow.operation,
        });
        _check(flow);
        return {...paired, ...connected, 'paired': true};
      } catch (error) {
        _check(flow);
        failure = error;
        final code = _code(error);
        if (code == 'discovery_changed') {
          if (++generations >= policy.pairingDiscoveryRetries) break;
        } else if (code != 'discovery_pending') {
          break;
        }
      }
      await _delay(policy.setupPollInterval);
    }
    _check(flow);
    final devices = await _devices();
    _check(flow);
    final device = devices.where((d) => d['id'] == flow.deviceId).firstOrNull;
    return {
      ...paired,
      'connected': false,
      'device': device ?? paired['device'],
      'connectionPortRequired':
          failure == null || _code(failure) == 'discovery_pending',
      if (failure != null)
        'connectionFailure': {'code': _code(failure), 'message': '$failure'},
    };
  }

  Future<SetupJson> _usb(_SetupFlow flow, SetupJson params) async {
    SetupJson authorized = params;
    try {
      if (!params.containsKey('fd')) {
        final authorize = authorizeUsb;
        if (authorize == null) {
          throw const InteropException(
            'usb_permission_required',
            '需要主控系统USB授权。',
          );
        }
        authorized = {
          ...params,
          ...await authorize({...params, 'attemptId': flow.attempt}),
        };
      }
      _check(flow);
      final opened = await _request('adb.usb.open', _lease(flow, authorized));
      flow.operation = opened['operationId'] as String;
      _check(flow);
      var id = flow.deviceId;
      if (id == null) {
        final serial = _object(opened['metadata'])['serial'];
        if (serial is String && serial.isNotEmpty) {
          final matching = (await _devices())
              .where((device) => device['serial'] == serial)
              .toList();
          _check(flow);
          if (matching.length > 1) {
            throw const InteropException(
              'usb_selection_required',
              '多条记录匹配USB序列号，请选择设备记录。',
            );
          }
          id = matching.firstOrNull?['id'] as String?;
        }
      }
      _bind(flow, id);
      final receipt = await _request('adb.usb.attach', {
        'operationId': flow.operation,
        'deviceId': ?id,
      });
      _check(flow);
      return receipt;
    } finally {
      if (authorized['usbLeaseId'] is String && releaseUsb != null) {
        await releaseUsb!({'usbLeaseId': authorized['usbLeaseId']});
      }
    }
  }

  Future<SetupJson> _tcpip(_SetupFlow flow, SetupJson params) async {
    final id = flow.deviceId;
    if (id == null) {
      throw const InteropException('invalid_argument', '缺少设备标识。');
    }
    final current = (await _devices())
        .where((device) => device['id'] == id)
        .firstOrNull;
    _check(flow);
    final connection = current?['connectionId'];
    if (connection is! String) {
      throw const InteropException('disconnected', '请先连接设备。');
    }
    final port = params['port'] ?? 5555;
    final begin = await _request(
      'adb.tcpip.begin',
      _lease(flow, {'deviceId': id, 'connectionId': connection, 'port': port}),
    );
    flow.operation = begin['operationId'] as String;
    _check(flow);
    final bytes = (begin['responseBytes'] as List).cast<int>();
    if (String.fromCharCodes(bytes).trim() !=
        'restarting in TCP mode port: $port') {
      throw const InteropException(
        'wireless_setup_failed',
        '设备未确认在指定端口开启IP连接。',
      );
    }
    final deadline = _now().add(policy.tcpipReconnectTimeout);
    while (true) {
      await _ready(flow);
      try {
        final receipt = await _request('adb.tcpip.connect', {
          'operationId': flow.operation,
          'address': params['address'],
        });
        _check(flow);
        return {...receipt, 'enabled': true, 'port': port, 'encrypted': false};
      } catch (error) {
        _check(flow);
        if (!const {
          'unreachable',
          'timeout',
          'io_error',
          'disconnected',
        }.contains(_code(error))) {
          rethrow;
        }
        if (!_now().isBefore(deadline)) {
          throw const InteropException('timeout', 'IP监听已开启，但目标尚未连接，请核对地址和端口。');
        }
      }
      await _delay(policy.tcpipRetryInterval);
    }
  }

  Future<List<SetupJson>> _devices() async =>
      ((_object(await _request('devices.list', {}))['devices'] as List?) ?? [])
          .map(_object)
          .toList();

  Future<void> _ready(_SetupFlow flow) async {
    _check(flow);
    while (_recovering) {
      await _delay(policy.setupPollInterval);
      _check(flow);
    }
  }

  void _check(_SetupFlow flow) {
    if (!_now().isBefore(flow.deadline)) {
      throw const InteropException('expired', '本次连接流程已到期。');
    }
    if (_disposed || flow.cancelled || !identical(_flows[flow.attempt], flow)) {
      throw const InteropException('cancelled', '本次连接流程已停止。');
    }
  }

  void _cancel(_SetupFlow flow) {
    flow.cancelled = true;
    flow.cancelling ??= () async {
      if (cancelUsb != null) {
        try {
          await cancelUsb!({'attemptId': flow.attempt});
        } catch (_) {}
      }
      try {
        await _request('devices.cancel', {'attemptId': flow.attempt});
      } catch (_) {}
    }();
    unawaited(flow.cancelling!);
  }

  Future<void> _finish(_SetupFlow flow) async {
    if (flow.finished) return;
    flow.finished = true;
    if (identical(_flows[flow.attempt], flow)) _flows.remove(flow.attempt);
    final operation = flow.operation;
    if (operation != null) {
      try {
        await _request('adb.operation.release', {'operationId': operation});
      } catch (_) {
        /* Native lease still expires. */
      }
    }
    await flow.hold?.call();
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final flow in _flows.values.toList()) {
      _cancel(flow);
      await flow.cancelling;
      await _finish(flow);
    }
  }
}

SetupJson _object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String _code(Object? error) =>
    error is InteropException ? error.code : 'setup_failed';

class _SetupFlow {
  _SetupFlow(this.attempt, this.deviceId, this.revision, this.deadline);
  final String attempt;
  final int revision;
  final DateTime deadline;
  String? deviceId, operation;
  Future<void> Function()? hold;
  Future<void>? cancelling;
  bool cancelled = false, finished = false;
}
