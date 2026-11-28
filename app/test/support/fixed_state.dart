import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/models/preferences_state.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';

/// 页面测试用的固定设备列表；`refresh` 不读取设备，只调用 [onRefresh]。
class FixedDeviceList extends DeviceListNotifier {
  FixedDeviceList({
    this._devices = const [],
    this._loading = false,
    this._onRefresh,
  });

  final List<DeviceSnapshot> _devices;
  final bool _loading;
  final void Function()? _onRefresh;

  @override
  DeviceListState build() =>
      DeviceListState(devices: _devices, loading: _loading);

  @override
  Future<void> refresh() async => _onRefresh?.call();
}

/// 没有待恢复内容的恢复状态。
class FixedRecovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}

/// 固定偏好，不读写存储。
class FixedPreferences extends PreferencesNotifier {
  FixedPreferences([this._values]);

  final Preferences? _values;

  @override
  PreferencesState build() => PreferencesState(values: _values);
}

/// 交付本轮微任务后排空 provider 的待处理刷新。
Future<void> flushProviders(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
}
