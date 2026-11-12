// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'file_search.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FileSearchSnapshot _$FileSearchSnapshotFromJson(Map<String, dynamic> json) =>
    _FileSearchSnapshot(
      deviceId: json['deviceId'] as String,
      searchId: json['searchId'] as String,
      path: json['path'] as String,
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
      checkedAt: json['checkedAt'] == null
          ? null
          : DateTime.parse(json['checkedAt'] as String),
      query: json['query'] as String? ?? '',
      filter:
          $enumDecodeNullable(_$FileCatalogFilterEnumMap, json['filter']) ??
          FileCatalogFilter.all,
      status:
          $enumDecodeNullable(
            _$FileSearchStatusEnumMap,
            json['status'],
            unknownValue: FileSearchStatus.unknown,
          ) ??
          FileSearchStatus.unknown,
      entries:
          (json['entries'] as List<dynamic>?)
              ?.map((e) => FileCatalogEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      issues:
          (json['issues'] as List<dynamic>?)
              ?.map((e) => FileCatalogIssue.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      visitedEntries: (json['visitedEntries'] as num?)?.toInt() ?? 0,
      visitedDirectories: (json['visitedDirectories'] as num?)?.toInt() ?? 0,
      currentDirectory: json['currentDirectory'] as String? ?? '',
      total: (json['total'] as num?)?.toInt() ?? 0,
      hasMore: json['hasMore'] as bool? ?? false,
      limited: json['limited'] as bool? ?? false,
    );

Map<String, dynamic> _$FileSearchSnapshotToJson(_FileSearchSnapshot instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'searchId': instance.searchId,
      'path': instance.path,
      'startedAt': instance.startedAt?.toIso8601String(),
      'checkedAt': instance.checkedAt?.toIso8601String(),
      'query': instance.query,
      'filter': _$FileCatalogFilterEnumMap[instance.filter]!,
      'status': _$FileSearchStatusEnumMap[instance.status]!,
      'entries': instance.entries,
      'issues': instance.issues,
      'visitedEntries': instance.visitedEntries,
      'visitedDirectories': instance.visitedDirectories,
      'currentDirectory': instance.currentDirectory,
      'total': instance.total,
      'hasMore': instance.hasMore,
      'limited': instance.limited,
    };

const _$FileCatalogFilterEnumMap = {
  FileCatalogFilter.all: 'all',
  FileCatalogFilter.folders: 'folders',
  FileCatalogFilter.images: 'images',
  FileCatalogFilter.videos: 'videos',
  FileCatalogFilter.audio: 'audio',
  FileCatalogFilter.documents: 'documents',
  FileCatalogFilter.archives: 'archives',
};

const _$FileSearchStatusEnumMap = {
  FileSearchStatus.unknown: 'unknown',
  FileSearchStatus.running: 'running',
  FileSearchStatus.completed: 'completed',
  FileSearchStatus.partial: 'partial',
  FileSearchStatus.cancelled: 'cancelled',
  FileSearchStatus.failed: 'failed',
};
