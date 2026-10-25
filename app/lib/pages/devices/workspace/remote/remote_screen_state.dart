import 'dart:async';

import 'package:flutter/foundation.dart';

import 'remote_window.dart';

/// 当前远控窗口的屏幕状态轮询；旧连接的迟到回执不能更新当前画面。
class RemoteScreenState {
  RemoteScreenState({
    required this.window,
    required this.foreground,
    required this.onChanged,
  });

  final RemoteWindow window;
  final bool Function() foreground;
  final VoidCallback onChanged;
  Timer? _timer;
  bool? _screenOn;
  bool? _screenLocked;
  bool _reading = false;
  bool _disposed = false;
  int _generation = 0;

  bool? get screenOn => _screenOn;
  bool? get screenLocked => _screenLocked;

  void start() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final presentation = window.presentation;
    if (_disposed ||
        presentation.exiting ||
        !foreground() ||
        presentation.covered ||
        _reading) {
      return;
    }
    _reading = true;
    final generation = ++_generation;
    final connection = window.controller
        .snapshot()
        .devices
        .where((device) => device['id'] == window.deviceId)
        .firstOrNull?['connectionId'];
    try {
      final result = await window.controller.request('device.screen.state', {
        'deviceId': window.deviceId,
        'connectionId': ?connection,
      });
      if (_disposed ||
          presentation.exiting ||
          generation != _generation ||
          !foreground() ||
          presentation.covered) {
        return;
      }
      final currentConnection = window.controller
          .snapshot()
          .devices
          .where((device) => device['id'] == window.deviceId)
          .firstOrNull?['connectionId'];
      if (connection != currentConnection ||
          result['deviceId'] != window.deviceId ||
          (connection != null && result['connectionId'] != connection)) {
        return;
      }
      _screenOn = result['screenOn'] is bool
          ? result['screenOn'] as bool
          : null;
      _screenLocked = result['locked'] is bool
          ? result['locked'] as bool
          : null;
      onChanged();
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _screenOn = null;
        _screenLocked = null;
        onChanged();
      }
    } finally {
      _reading = false;
    }
  }

  void invalidate() {
    if (_disposed) return;
    _generation++;
    _screenOn = null;
    _screenLocked = null;
    onChanged();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
