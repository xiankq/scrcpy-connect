import 'package:scrcpy_connect/core/devices/models/device_record.dart';

final class DeviceImportReceipt {
  DeviceImportReceipt({
    required Iterable<String> deviceIds,
    required this.importedAt,
    required this.importGlobalPreferences,
  }) : deviceIds = List.unmodifiable(deviceIds);
  final List<String> deviceIds;
  final int importedAt;
  final bool importGlobalPreferences;
  Map<String, Object?> toJson() => {
    'deviceIds': deviceIds,
    'importedAt': importedAt,
    'importGlobalPreferences': importGlobalPreferences,
  };
  factory DeviceImportReceipt.fromJson(Object? input) {
    final value = recordObject(input);
    final ids = value['deviceIds'];
    final stamp = value['importedAt'];
    if (ids is! List ||
        ids.length > 256 ||
        ids.any((id) => id is! String || !validDeviceId(id)) ||
        ids.toSet().length != ids.length ||
        stamp is! int ||
        stamp < 0 ||
        value['importGlobalPreferences'] is! bool) {
      throw const DeviceRecordsFailure('records_corrupt', '导入记录损坏，原文件已保留。');
    }
    return DeviceImportReceipt(
      deviceIds: ids.cast<String>(),
      importedAt: stamp,
      importGlobalPreferences: value['importGlobalPreferences']! as bool,
    );
  }
}
