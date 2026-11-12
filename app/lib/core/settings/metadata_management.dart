import 'package:scrcpy_connect/core/devices/models/device_metadata.dart';
import 'package:scrcpy_connect/core/settings/models/settings_import.dart';

export 'package:scrcpy_connect/core/settings/models/settings_import.dart';

abstract interface class MetadataManagement {
  Future<DeviceMetadata> exportMetadata();
  Future<SettingsImportPreview> previewImport(DeviceMetadata metadata);
  Future<SettingsImportResult> importMetadata(
    SettingsImportPreview preview, {
    bool importGlobalPreferences = false,
  });
}
