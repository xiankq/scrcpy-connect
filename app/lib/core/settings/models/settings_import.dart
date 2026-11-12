import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_metadata.dart';
import 'package:scrcpy_connect/core/devices/models/device_records_import.dart';

part 'settings_import.freezed.dart';

enum ImportPreferencesStatus {
  preserved,
  imported,
  matchesCurrent,
  needsReview,
}

@freezed
class GlobalPreferenceChange with _$GlobalPreferenceChange {
  const GlobalPreferenceChange({
    required this.key,
    required this.current,
    required this.imported,
  });

  final String key;
  final Object? current;
  final Object? imported;
}

/// 确认时使用预览所读取的不可变文件与本机版本，不重新读取选择器路径。
@freezed
class SettingsImportPreview with _$SettingsImportPreview {
  SettingsImportPreview({
    required this.metadata,
    required this.expectedRevision,
    required this.newRecords,
    this.receipt,
    this.preferencesStatus,
    List<GlobalPreferenceChange> globalChanges = const [],
  }) : globalChanges = List.unmodifiable(globalChanges);

  final DeviceMetadata metadata;
  final int expectedRevision;
  final int newRecords;
  final DeviceRecordsImport? receipt;
  final ImportPreferencesStatus? preferencesStatus;
  final List<GlobalPreferenceChange> globalChanges;

  bool get alreadyImported => receipt != null;
}

@freezed
class SettingsImportResult with _$SettingsImportResult {
  const SettingsImportResult({
    required this.records,
    required this.preferencesStatus,
  });

  final DeviceRecordsImport records;
  final ImportPreferencesStatus preferencesStatus;
}
