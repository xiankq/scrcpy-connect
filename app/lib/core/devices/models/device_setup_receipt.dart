import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_endpoint.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';

part 'device_setup_receipt.freezed.dart';

enum DiscoveredDeviceKind { pairing, tls, tcp }

typedef DiscoveredEndpoint = ({String address, int port});

@freezed
abstract class DiscoveredDevice with _$DiscoveredDevice {
  const DiscoveredDevice._();
  const factory DiscoveredDevice({
    required DiscoveredDeviceKind kind,
    required String instance,
    required String serviceName,
    required String hostname,
    required List<DiscoveredEndpoint> endpoints,
    String? deviceId,
  }) = _DiscoveredDevice;

  bool get trusted => deviceId != null;
}

/// 只表达已经发生的设置事实；失败和取消不能抹去已完成的配对或监听切换。
sealed class DeviceSetupReceipt {
  const DeviceSetupReceipt();
}

@freezed
abstract class PairingReceipt extends DeviceSetupReceipt with _$PairingReceipt {
  const PairingReceipt._();
  const factory PairingReceipt({
    required String guid,
    required String address,
    DeviceSnapshot? device,
    DeviceConnectionReceipt? connection,
    @Default(false) bool cancelled,
    @Default(false) bool connectionPortRequired,
    SetupIssue? connectionFailure,
  }) = _PairingReceipt;

  String? get deviceId => device?.id;
  bool get recorded => device != null;
  bool get connected => connection != null;
}

@freezed
abstract class WirelessReceipt extends DeviceSetupReceipt
    with _$WirelessReceipt {
  const WirelessReceipt._();
  const factory WirelessReceipt({
    required String deviceId,
    required String address,
    required int port,
    DeviceConnectionReceipt? connection,
  }) = _WirelessReceipt;

  bool get connected => connection != null;
}

@freezed
abstract class SetupIssue with _$SetupIssue {
  const factory SetupIssue(String code, String message) = _SetupIssue;
}

@freezed
sealed class UsbSetupResult extends DeviceSetupReceipt with _$UsbSetupResult {
  const UsbSetupResult._();
  const factory UsbSetupResult.selectionRequired(
    List<UsbDeviceChoice> devices, {
    String? message,
  }) = UsbSelectionRequired;
  const factory UsbSetupResult.connected(DeviceConnectionReceipt receipt) =
      UsbConnected;

  DeviceSnapshot? get device => switch (this) {
    UsbConnected(:final receipt) => receipt.device,
    UsbSelectionRequired() => null,
  };
  String? get deviceId => device?.id;
  bool get connected => this is UsbConnected;
}

@freezed
abstract class UsbDeviceChoice with _$UsbDeviceChoice {
  const factory UsbDeviceChoice({
    @Default('') String serial,
    @Default('') String state,
    String? usbPath,
    String? model,
    int? transportId,
    String? usbDeviceId,
    String? name,
    DeviceSnapshot? device,
  }) = _UsbDeviceChoice;
}
