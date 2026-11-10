import 'package:scrcpy_connect/models/device_import_receipt.dart';
import 'package:scrcpy_connect/models/device_record.dart';

Object? _freeze(Object? value) => switch (value) {
  Map() => Map<String, Object?>.unmodifiable(
    value.map((key, child) => MapEntry(key as String, _freeze(child))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};

final class DeviceRecordsSnapshot {
  DeviceRecordsSnapshot({
    required Iterable<DeviceRecord> devices,
    required this.identityFingerprint,
    required Map<String, String> deviceIdentityFingerprints,
    Map<String, Object?> legacySettings = const {},
    Map<String, DeviceImportReceipt> imports = const {},
  }) : imports = Map.unmodifiable(imports),
       devices = List.unmodifiable(devices),
       deviceIdentityFingerprints = Map.unmodifiable(
         deviceIdentityFingerprints,
       ),
       legacySettings = _freeze(legacySettings) as Map<String, Object?>;
  final List<DeviceRecord> devices;
  final Map<String, DeviceImportReceipt> imports;
  final String identityFingerprint;
  final Map<String, String> deviceIdentityFingerprints;

  /// 旧版偏好迁移的输入；设备操作保留它，不解释或写入新的产品偏好。
  final Map<String, Object?> legacySettings;
  DeviceRecord? find(String id) =>
      devices.where((device) => device.id == id).firstOrNull;
  Map<String, Object?> toJson() => {
    'version': 3,
    'identityFingerprint': identityFingerprint,
    'deviceIdentityFingerprints': deviceIdentityFingerprints,
    'devices': devices.map((record) => record.toJson()).toList(),
    'imports': {
      for (final entry in imports.entries) entry.key: entry.value.toJson(),
    },
    if (legacySettings.isNotEmpty) 'settings': legacySettings,
  };
}
