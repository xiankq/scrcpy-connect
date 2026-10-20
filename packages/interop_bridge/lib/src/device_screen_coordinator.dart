import 'dart:async';

import 'interop_exception.dart';

typedef ScreenJson = Map<String, dynamic>;

/// One Dart owner consumes connection wake intents before automatic reconnect
/// starts. Input events must already have passed StateRecovery's sequence fence.
class DeviceScreenCoordinator {
  DeviceScreenCoordinator({required this.request, required this.emit});

  final Future<ScreenJson> Function(String command, ScreenJson params) request;
  final void Function(ScreenJson event) emit;
  final _connections = <String, String>{};
  ScreenJson _settings = {};
  int _sequence = -1;
  bool _ready = false, _disposed = false;

  bool isConnectionCurrent(String device, String token) =>
      !_disposed && _connections[device] == token;

  void handleEvent(ScreenJson event) {
    if (_disposed) return;
    final type = event['type'];
    if (type == 'state.resync' || type == 'state.resync.failed') {
      _ready = false;
      return;
    }
    final data = _object(event['data']);
    if (type == 'state.resynced') {
      final sequence = data['sequence'];
      if (sequence is! int || sequence < _sequence) return;
      _sequence = sequence;
      _settings = _object(data['settings']);
      _observe(data['devices'], baseline: true);
      _ready = true;
      return;
    }
    if (!_ready) return;
    final sequence = event['sequence'];
    if (sequence is! int || sequence <= _sequence) return;
    _sequence = sequence;
    if (type == 'settings.changed') {
      _settings = data;
    } else if (type == 'devices.changed') {
      _observe(data['devices']);
    } else if (type == 'device.changed') {
      _observe([data], complete: false);
    }
  }

  void _observe(
    Object? devices, {
    bool baseline = false,
    bool complete = true,
  }) {
    if (devices is! List) return;
    final entries = devices
        .whereType<Map<Object?, Object?>>()
        .map(_object)
        .toList();
    if (complete) {
      final ids = entries.map((device) => device['id']).toSet();
      _connections.removeWhere((id, _) => !ids.contains(id));
    }
    final preferences = _object(_settings['deviceSettings']);
    for (final device in entries) {
      final id = device['id'];
      final token = device['connectionId'];
      if (id is! String ||
          device['status'] != 'connected' ||
          token is! String ||
          token.isEmpty ||
          _connections[id] == token) {
        continue;
      }
      // Consume before submitting: a lost receipt must never replay input.
      _connections[id] = token;
      if (!baseline && _object(preferences[id])['wakeOnConnect'] == true) {
        unawaited(_wake(id, token));
      }
    }
  }

  Future<void> _wake(String device, String token) async {
    try {
      await request('devices.wake', {
        'deviceId': device,
        'connectionId': token,
      });
    } catch (error) {
      if (!isConnectionCurrent(device, token) ||
          (error is InteropException && error.code == 'stale_connection')) {
        return;
      }
      emit({
        'type': 'device.screen.failed',
        'deviceId': device,
        'data': {'connectionId': token, 'reason': '$error'},
      });
    }
  }

  void dispose() {
    _disposed = true;
  }

  static ScreenJson _object(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
}
