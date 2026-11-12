import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';

import 'device_list_notifier.dart';
import 'models/device_readiness.dart';

export 'models/device_readiness.dart';

final deviceReadinessProvider = Provider.autoDispose
    .family<DeviceReadiness, String>((ref, deviceId) {
      final connection = ref.watch(
        deviceListProvider.select((state) {
          final device = state.devices
              .where((item) => item.id == deviceId)
              .firstOrNull;
          return (device?.connectionId, device?.status);
        }),
      );
      final recovering = ref.watch(
        recoveryStateProvider.select((state) => state.reconciliationPending),
      );
      return DeviceReadiness(
        connectionId: connection.$1,
        status: connection.$2,
        recovering: recovering,
      );
    });
