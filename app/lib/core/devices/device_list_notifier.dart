import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

import 'device_capabilities_provider.dart';
import 'device_management.dart';

part 'device_list_notifier.g.dart';

@Riverpod(keepAlive: true)
class DeviceListNotifier extends _$DeviceListNotifier {
  _DeviceListOwner? _owner;

  @override
  DeviceListState build() {
    final session = ref.watch(stateSubscriptionProvider);
    final previous = _owner;
    final owner = _owner = _DeviceListOwner(
      session,
      ref.watch(deviceManagementProvider),
    );
    final initial = session.session.initialState;
    final subscription = session.stateEvents.listen((event) {
      if (!_current(owner)) return;
      final type = event['type'];
      if (type == 'state.resync' || type == 'state.resync.failed') {
        owner.request++;
      } else if (type == 'state.resynced') {
        owner.request++;
        state = state.copyWith(
          devices: (event['data'] as RuntimeSnapshot).devices,
          loading: false,
          error: null,
        );
      } else if (value(event, 'type').startsWith('device')) {
        unawaited(refresh());
      }
    });
    final errors = session.connectionErrors.listen((error) {
      if (!_current(owner)) return;
      state = state.copyWith(error: '连接状态更新中断：$error');
      unawaited(refresh());
    });
    ref.onDispose(() {
      owner.disposed = true;
      unawaited(subscription.cancel());
      unawaited(errors.cancel());
    });
    if (session.session.initialize) {
      scheduleMicrotask(() {
        if (_current(owner)) unawaited(refresh());
      });
    }
    return identical(previous?.session, session)
        ? DeviceListState(loading: session.session.initialize)
        : DeviceListState(
            devices: initial.devices,
            loading: initial.loading,
            error: initial.deviceError,
          );
  }

  bool _current(_DeviceListOwner owner) =>
      ref.mounted &&
      !owner.disposed &&
      !owner.session.disposed &&
      identical(ref.read(deviceManagementProvider), owner.source) &&
      identical(_owner, owner);

  Future<void> refresh() async {
    final owner = _owner!;
    if (!_current(owner)) return;
    final requestId = ++owner.request;
    state = state.copyWith(loading: true);
    try {
      final result = await owner.source.readDevices();
      if (!_current(owner) || requestId != owner.request) return;
      state = state.copyWith(devices: result, loading: false, error: null);
    } catch (error) {
      if (_current(owner) && requestId == owner.request) {
        state = state.copyWith(loading: false, error: '$error');
      }
    }
  }

  DeviceSnapshot current(DeviceSnapshot original) => state.devices.firstWhere(
    (device) => device.id == original.id,
    orElse: () => original,
  );
}

final class _DeviceListOwner {
  _DeviceListOwner(this.session, this.source);
  final StateSubscription session;
  final DeviceManagement source;
  int request = 0;
  bool disposed = false;
}
