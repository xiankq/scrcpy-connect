// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'file_directory.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FileDirectorySnapshot _$FileDirectorySnapshotFromJson(
  Map<String, dynamic> json,
) => _FileDirectorySnapshot(
  deviceId: json['deviceId'] as String,
  path: json['path'] as String,
  entries:
      (json['entries'] as List<dynamic>?)
          ?.map((e) => FileCatalogEntry.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  total: (json['total'] as num?)?.toInt(),
  offset: (json['offset'] as num?)?.toInt() ?? 0,
  hasMore: json['hasMore'] as bool? ?? false,
  truncated: json['truncated'] as bool? ?? false,
);

Map<String, dynamic> _$FileDirectorySnapshotToJson(
  _FileDirectorySnapshot instance,
) => <String, dynamic>{
  'deviceId': instance.deviceId,
  'path': instance.path,
  'entries': instance.entries,
  'total': instance.total,
  'offset': instance.offset,
  'hasMore': instance.hasMore,
  'truncated': instance.truncated,
};
