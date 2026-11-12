import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';

part 'current_device_notifier.g.dart';

/// 当前操作设备归用户焦点选择，不属于宿主恢复状态。
@Riverpod(keepAlive: true)
class CurrentDeviceNotifier extends _$CurrentDeviceNotifier {
  @override
  String? build() => ref
      .watch(stateSubscriptionProvider)
      .dependencies
      .initialState
      .focusedDeviceId;

  Future<void> focus(String? deviceId) async {
    if (ref.mounted && state != deviceId) state = deviceId;
  }
}
