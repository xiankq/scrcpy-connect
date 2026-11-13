import 'package:adb/adb.dart' show AdbCancellation;
import 'package:scrcpy_connect/core/devices/models/device_setup_receipt.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart'
    show RequestFailure;
import 'package:scrcpy_connect/core/identity/models/setup_identity.dart';

export 'package:scrcpy_connect/core/devices/models/device_setup_receipt.dart';

abstract interface class DeviceSetup {
  Future<List<DiscoveredDevice>> discoverDevices({
    String? attemptId,
    AdbCancellation? cancellation,
  });
  Future<PairingReceipt> pairDevice(
    String address,
    int port,
    String code, {
    String? deviceId,
    String? attemptId,
    SetupIdentity? identity,
  });
  Future<QrPairingSession> beginQrPairing({
    String? deviceId,
    String? attemptId,
    SetupIdentity? identity,
  });
  Future<UsbSetupResult> connectUsb({
    String? deviceId,
    String? attemptId,
    String? serial,
    String? usbDeviceId,
    bool connect = false,
    SetupIdentity? identity,
  });
  Future<WirelessReceipt> enableWireless(
    String deviceId,
    String address, {
    int port = 5555,
    required String connectionId,
    String? attemptId,
  });
}

/// 本次二维码的完成句柄；结果可以先于页面取得句柄完成，无须额外缓存全局事件。
final class QrPairingSession {
  const QrPairingSession({
    required this.attemptId,
    required this.payload,
    required this.expiresAt,
    required this.result,
  });
  final String attemptId, payload;
  final DateTime expiresAt;
  final Future<PairingReceipt> result;
}

final class DeviceSetupFailure extends RequestFailure {
  const DeviceSetupFailure(
    String code,
    String message, {
    this.receipt,
    Object? cause,
  }) : super(code, message, cause);
  final DeviceSetupReceipt? receipt;
}
