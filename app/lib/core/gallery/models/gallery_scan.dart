import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';

part 'gallery_scan.freezed.dart';
part 'gallery_scan.g.dart';

typedef GalleryScanTarget = ({String deviceId, String scanId});

enum GalleryScanStatus { unknown, scanning, completed, partial, cancelled }

@freezed
abstract class GalleryScanScope with _$GalleryScanScope {
  const factory GalleryScanScope({
    @Default([]) List<String> roots,
    @Default([]) List<String> excluded,
  }) = _GalleryScanScope;
  factory GalleryScanScope.fromJson(Map<String, dynamic> json) =>
      _$GalleryScanScopeFromJson(json);
}

@freezed
abstract class GalleryScanSnapshot with _$GalleryScanSnapshot {
  const GalleryScanSnapshot._();
  const factory GalleryScanSnapshot({
    required String deviceId,
    required String scanId,
    @JsonKey(unknownEnumValue: GalleryScanStatus.unknown)
    @Default(GalleryScanStatus.unknown)
    GalleryScanStatus status,
    DateTime? startedAt,
    DateTime? checkedAt,
    @Default([]) List<FileCatalogEntry> items,
    @Default([]) List<FileCatalogIssue> issues,
    @Default(GalleryScanScope()) GalleryScanScope scope,
    @Default(0) int total,
    @Default(0) int offset,
    int? nextOffset,
    @Default(0) int visitedEntries,
    @Default(0) int visitedDirectories,
    @Default('') String currentDirectory,
    @Default(false) bool limited,
  }) = _GalleryScanSnapshot;
  factory GalleryScanSnapshot.fromJson(Map<String, dynamic> json) =>
      _$GalleryScanSnapshotFromJson(json);

  GalleryScanTarget get target => (deviceId: deviceId, scanId: scanId);
}
