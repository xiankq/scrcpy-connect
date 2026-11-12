import 'package:scrcpy_connect/core/devices/models/device_import_receipt.dart';

final class DeviceRecordsImport {
  DeviceRecordsImport(
    this.fingerprint,
    this.receipt, {
    this.alreadyImported = false,
  });
  final String fingerprint;
  final DeviceImportReceipt receipt;
  final bool alreadyImported;
  int get restored => receipt.deviceIds.length;
  bool get authorizationRestored => false;
  Map<String, Object?> toJson() => {
    'fingerprint': fingerprint,
    'restored': restored,
    'authorizationRestored': false,
    'alreadyImported': alreadyImported,
    ...receipt.toJson(),
  };
}
