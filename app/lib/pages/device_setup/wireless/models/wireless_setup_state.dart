import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_details.dart';
import 'package:scrcpy_connect/core/devices/models/device_setup_receipt.dart';

part 'wireless_setup_state.freezed.dart';

enum WirelessSetupPhase {
  reading,
  idle,
  preparing,
  confirming,
  switching,
  cancelling,
  cancelled,
  completed,
  failed,
  cleanupRequired,
}

/// 确认框显示的精确来源与目标；确认后不能重新解析成另一条设备连接。
@freezed
abstract class WirelessSwitchRequest with _$WirelessSwitchRequest {
  const factory WirelessSwitchRequest({
    required String attemptId,
    required String deviceId,
    required String connectionId,
    required String address,
    required int port,
  }) = _WirelessSwitchRequest;
}

@freezed
abstract class WirelessSetupState with _$WirelessSetupState {
  const WirelessSetupState._();
  const factory WirelessSetupState({
    @Default(WirelessSetupPhase.reading) WirelessSetupPhase phase,
    @Default([]) List<DeviceNetworkAddress> addresses,
    WirelessSwitchRequest? confirmation,
    WirelessReceipt? result,
    String? error,
    String? notice,
  }) = _WirelessSetupState;

  bool get loading => phase == .reading || phase == .preparing;
  bool get busy => switch (phase) {
    .preparing ||
    .confirming ||
    .switching ||
    .cancelling ||
    .cleanupRequired => true,
    _ => false,
  };
  bool get canCancel => switch (phase) {
    .switching || .cancelling || .cleanupRequired => true,
    _ => false,
  };
}
