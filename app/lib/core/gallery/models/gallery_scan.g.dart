// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'gallery_scan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_GalleryScanScope _$GalleryScanScopeFromJson(Map<String, dynamic> json) =>
    _GalleryScanScope(
      roots:
          (json['roots'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      excluded:
          (json['excluded'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$GalleryScanScopeToJson(_GalleryScanScope instance) =>
    <String, dynamic>{'roots': instance.roots, 'excluded': instance.excluded};

_GalleryScanSnapshot _$GalleryScanSnapshotFromJson(Map<String, dynamic> json) =>
    _GalleryScanSnapshot(
      deviceId: json['deviceId'] as String,
      scanId: json['scanId'] as String,
      status:
          $enumDecodeNullable(
            _$GalleryScanStatusEnumMap,
            json['status'],
            unknownValue: GalleryScanStatus.unknown,
          ) ??
          GalleryScanStatus.unknown,
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
      checkedAt: json['checkedAt'] == null
          ? null
          : DateTime.parse(json['checkedAt'] as String),
      items:
          (json['items'] as List<dynamic>?)
              ?.map((e) => FileCatalogEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      issues:
          (json['issues'] as List<dynamic>?)
              ?.map((e) => FileCatalogIssue.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      scope: json['scope'] == null
          ? const GalleryScanScope()
          : GalleryScanScope.fromJson(json['scope'] as Map<String, dynamic>),
      total: (json['total'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      nextOffset: (json['nextOffset'] as num?)?.toInt(),
      visitedEntries: (json['visitedEntries'] as num?)?.toInt() ?? 0,
      visitedDirectories: (json['visitedDirectories'] as num?)?.toInt() ?? 0,
      currentDirectory: json['currentDirectory'] as String? ?? '',
      limited: json['limited'] as bool? ?? false,
    );

Map<String, dynamic> _$GalleryScanSnapshotToJson(
  _GalleryScanSnapshot instance,
) => <String, dynamic>{
  'deviceId': instance.deviceId,
  'scanId': instance.scanId,
  'status': _$GalleryScanStatusEnumMap[instance.status]!,
  'startedAt': instance.startedAt?.toIso8601String(),
  'checkedAt': instance.checkedAt?.toIso8601String(),
  'items': instance.items,
  'issues': instance.issues,
  'scope': instance.scope,
  'total': instance.total,
  'offset': instance.offset,
  'nextOffset': instance.nextOffset,
  'visitedEntries': instance.visitedEntries,
  'visitedDirectories': instance.visitedDirectories,
  'currentDirectory': instance.currentDirectory,
  'limited': instance.limited,
};

const _$GalleryScanStatusEnumMap = {
  GalleryScanStatus.unknown: 'unknown',
  GalleryScanStatus.scanning: 'scanning',
  GalleryScanStatus.completed: 'completed',
  GalleryScanStatus.partial: 'partial',
  GalleryScanStatus.cancelled: 'cancelled',
};
