import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

/// 页面查询按主题与设备失效；在途事件合并为下一次核对，不并发堆积读取。
class CommandQuery extends ChangeNotifier {
  CommandQuery({
    required this._request,
    required Stream<Json> events,
    required this.command,
    required Json params,
  }) : params = immutableJson(params) {
    _subscription = events.listen((event) {
      if (_invalidatedBy(event)) unawaited(refresh());
    });
    unawaited(refresh());
  }

  final ApplicationRequest _request;
  final String command;
  final Json params;
  late final StreamSubscription<Json> _subscription;
  Future<void>? _pending;
  bool _dirty = false;
  bool _disposed = false;
  bool loading = true;
  Json? data;
  Object? error;

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    _dirty = true;
    return _pending ??= Future<void>.microtask(_drain);
  }

  Future<void> _drain() async {
    try {
      while (!_disposed && _dirty) {
        _dirty = false;
        loading = true;
        error = null;
        notifyListeners();
        try {
          final result = await _request(command, params);
          if (_disposed) return;
          data = immutableJson(result);
        } catch (failure) {
          if (_disposed) return;
          error = failure;
        }
        loading = false;
        notifyListeners();
      }
    } finally {
      _pending = null;
    }
  }

  bool _invalidatedBy(Json event) {
    final type = value(event, 'type');
    if (type == 'session.frame') return false;
    if (type.startsWith('state.resync')) return true;
    final payload = jsonObject(event['data']);
    final device = event['deviceId'] ?? payload['deviceId'];
    if (params['deviceId'] != null &&
        device != null &&
        device != params['deviceId']) {
      return false;
    }
    final connectionChanged =
        type == 'devices.changed' ||
        type.startsWith('device.') ||
        type == 'connections.stopped';
    final observationChanged =
        type.startsWith('observation.') || type == 'companion.stopped';
    return switch (command) {
      'calls.list' =>
        connectionChanged ||
            observationChanged ||
            type.startsWith('calls.') ||
            type == 'call.incoming',
      'notifications.list' =>
        connectionChanged ||
            observationChanged ||
            type.startsWith('notifications.'),
      'activities.list' =>
        connectionChanged ||
            observationChanged ||
            type.startsWith('activities.') ||
            type.startsWith('session.') ||
            type.startsWith('audio.') ||
            type.startsWith('transfers.') ||
            type.startsWith('calls.') ||
            type == 'call.incoming',
      'transfers.list' => connectionChanged || type.startsWith('transfers.'),
      'transfers.get' =>
        connectionChanged ||
            (type.startsWith('transfers.') &&
                _includesTransfer(event, payload)),
      'apps.list' ||
      'session.quality.options' ||
      'device.capabilities' ||
      'device.data.get' ||
      'device.diagnose' ||
      'files.list' => connectionChanged,
      _ => false,
    };
  }

  bool _includesTransfer(Json event, Json payload) {
    final id = event['transferId'] ?? payload['transferId'];
    // 首次快照尚未确定批次成员；没有归属信息的事件也必须保守核对。
    if (data == null || id == null) return true;
    return id == params['transferId'] ||
        objects(data!['items']).any((item) => item['id'] == id);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
