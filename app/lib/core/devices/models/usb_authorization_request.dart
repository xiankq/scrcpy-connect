final class UsbAuthorizationRequest {
  const UsbAuthorizationRequest({
    required this.attemptId,
    this.deviceId,
    this.serial,
    this.usbDeviceId,
    this.connect = false,
  });

  final String attemptId;
  final String? deviceId, serial, usbDeviceId;
  final bool connect;
}
