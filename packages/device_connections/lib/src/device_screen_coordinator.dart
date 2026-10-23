typedef ScreenJson = Map<String, dynamic>;

/// Tracks live connection identities without coupling ADB changes to screen
/// actions. Window creation owns wake intent; reconnection never replays it.
class DeviceScreenCoordinator {
  DeviceScreenCoordinator({required this.request, required this.emit});

  final Future<ScreenJson> Function(String command, ScreenJson params) request;
  final void Function(ScreenJson event) emit;
  final _connections = <String, String>{};
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
      _observe(data['devices']);
      _ready = true;
      return;
    }
    if (!_ready) return;
    final sequence = event['sequence'];
    if (sequence is! int || sequence <= _sequence) return;
    _sequence = sequence;
    if (type == 'devices.changed') {
      _observe(data['devices']);
    } else if (type == 'device.changed') {
      _observe([data], complete: false);
    }
  }

  void _observe(Object? devices, {bool complete = true}) {
    if (devices is! List) return;
    final entries = devices
        .whereType<Map<Object?, Object?>>()
        .map(_object)
        .toList();
    if (complete) {
      final ids = entries.map((device) => device['id']).toSet();
      _connections.removeWhere((id, _) => !ids.contains(id));
    }
    for (final device in entries) {
      final id = device['id'];
      final token = device['connectionId'];
      if (id is String && device['status'] != 'connected') {
        _connections.remove(id);
        continue;
      }
      if (id is! String ||
          token is! String ||
          token.isEmpty ||
          _connections[id] == token) {
        continue;
      }
      // The token is a live transport fact, never a screen action trigger.
      _connections[id] = token;
    }
  }

  void dispose() {
    _disposed = true;
  }

  static ScreenJson _object(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
}
