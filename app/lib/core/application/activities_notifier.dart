import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/app_dependencies_provider.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';

import 'activities.dart';

import 'package:scrcpy_connect/core/application/application_session_provider.dart';
import 'package:scrcpy_connect/core/application/application_status_notifier.dart';

import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

export 'activities.dart';

part 'activities_notifier.g.dart';

/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。
@riverpod
class ActivitiesNotifier extends _$ActivitiesNotifier {
  Future<void>? _pending;
  bool _dirty = false;
  int _generation = 0;
  String? _deviceId;
  AppDependencies? _source;
  ActivitiesState? _lastSuccess;

  @override
  ActivitiesState build({String? deviceId}) {
    _deviceId = deviceId;
    // 依赖替换时 notifier 身份可保持，查询仍须释放旧订阅和旧回执。
    final source = ref.watch(appDependenciesProvider);
    if (!identical(_source, source)) _lastSuccess = null;
    _source = source;
    final session = ref.watch(applicationSessionProvider);
    if (deviceId != null) {
      ref.watch(
        deviceListProvider.select((state) {
          final device = state.devices
              .where((item) => item.id == deviceId)
              .firstOrNull;
          return (device?.connectionId, device?.status);
        }),
      );
      ref.watch(
        applicationStatusProvider.select(
          (state) => state.reconciliationPending,
        ),
      );
    }
    final generation = ++_generation;
    _pending = null;
    _dirty = false;
    final subscription = session.events.listen((event) {
      if (_current(generation) && _invalidatedBy(event)) {
        unawaited(refresh());
      }
    });
    ref.onDispose(() {
      if (_generation == generation) _generation++;
      unawaited(subscription.cancel());
    });
    scheduleMicrotask(() {
      if (_current(generation)) unawaited(refresh());
    });
    return ActivitiesState(
      data: _lastSuccess?.data,
      revision: _lastSuccess?.revision ?? 0,
    );
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  Future<void> refresh() {
    if (!ref.mounted) return Future.value();
    _dirty = true;
    if (!state.loading) state = state.copyWith(loading: true, error: null);
    final generation = _generation;
    return _pending ??= Future<void>.microtask(() => _drain(generation));
  }

  Future<void> _drain(int generation) async {
    if (!_current(generation)) return;
    try {
      while (_current(generation) && _dirty) {
        _dirty = false;
        state = state.copyWith(loading: true, error: null);
        try {
          final result = await _source!.activities.readActivities(
            deviceId: _deviceId,
          );
          if (!_current(generation)) return;
          // 在途失效的回执不能短暂恢复操作资格，先完成下一次核对。
          if (_dirty) continue;
          final next = ActivitiesState(
            loading: false,
            data: result,
            revision: state.revision + 1,
          );
          _lastSuccess = next;
          state = next;
        } catch (failure) {
          if (!_current(generation)) return;
          if (_dirty) continue;
          state = state.copyWith(loading: false, error: failure);
        }
      }
    } finally {
      if (_current(generation)) _pending = null;
    }
  }

  bool _invalidatedBy(Json event) {
    final type = value(event, 'type');
    if (type == 'session.frame') return false;
    if (type.startsWith('state.resync')) return true;
    final payload = jsonObject(event['data']);
    final device = event['deviceId'] ?? payload['deviceId'];
    if (_deviceId != null && device != null && device != _deviceId) {
      return false;
    }
    final connectionChanged =
        type == 'devices.changed' ||
        type.startsWith('device.') ||
        type == 'connections.stopped';
    return connectionChanged ||
        type.startsWith('audio.') ||
        type.startsWith('session.') ||
        type.startsWith('observation.') ||
        type == 'companion.stopped' ||
        type.startsWith('activities.') ||
        type.startsWith('transfers.') ||
        type.startsWith('calls.') ||
        type == 'call.incoming';
  }
}
