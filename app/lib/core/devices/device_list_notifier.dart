import 'package:scrcpy_connect/core/devices/device_snapshot.dart';

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/application_session_provider.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/core/application/application_session.dart';

import 'device_list_state.dart';

part 'device_list_notifier.g.dart';

@Riverpod(keepAlive: true)
class DeviceListNotifier extends _$DeviceListNotifier {
  late ApplicationSession _session;
  int _request = 0;

  @override
  DeviceListState build() {
    final session = _session = ref.watch(applicationSessionProvider);
    final initial = session.dependencies.initialState;
    final subscription = session.stateEvents.listen((event) {
      if (!_current(session)) return;
      final type = event['type'];
      if (type == 'state.resync' || type == 'state.resync.failed') {
        _request++;
      } else if (type == 'state.resynced') {
        _request++;
        state = state.copyWith(
          devices: [
            for (final item in objects(jsonObject(event['data'])['devices']))
              DeviceSnapshot.fromJson(item),
          ],
          loading: false,
          error: null,
        );
      } else if (value(event, 'type').startsWith('device')) {
        unawaited(refresh());
      }
    });
    final errors = session.connectionErrors.listen((error) {
      if (!_current(session)) return;
      state = state.copyWith(error: '连接状态更新中断：$error');
      unawaited(refresh());
    });
    ref.onDispose(() {
      unawaited(subscription.cancel());
      unawaited(errors.cancel());
    });
    if (session.dependencies.initialize) {
      scheduleMicrotask(() {
        if (_current(session)) unawaited(refresh());
      });
    }
    return DeviceListState(
      devices: initial.devices,
      loading: initial.loading,
      error: initial.deviceError,
    );
  }

  bool _current(ApplicationSession session) =>
      ref.mounted && !session.disposed && identical(_session, session);

  Future<void> refresh() async {
    final session = _session;
    if (!_current(session)) return;
    final requestId = ++_request;
    state = state.copyWith(loading: true);
    try {
      final result = await session.dependencies.devices.readDevices();
      if (!_current(session) || requestId != _request) return;
      state = state.copyWith(devices: result, loading: false, error: null);
    } catch (error) {
      if (_current(session) && requestId == _request) {
        state = state.copyWith(loading: false, error: '$error');
      }
    }
  }

  DeviceSnapshot current(DeviceSnapshot original) => state.devices.firstWhere(
    (device) => device.id == original.id,
    orElse: () => original,
  );
}
