// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'file_catalog_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FileCatalogEntry _$FileCatalogEntryFromJson(Map<String, dynamic> json) =>
    _FileCatalogEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String?,
      kind: json['kind'] as String? ?? 'file',
      isDirectory: json['isDirectory'] as bool? ?? false,
      isSymlink: json['isSymlink'] as bool? ?? false,
      nameIsUtf8: json['nameIsUtf8'] as bool? ?? true,
      canOpen: json['canOpen'] as bool? ?? true,
      canManage: json['canManage'] as bool? ?? true,
      size: (json['size'] as num?)?.toInt(),
      modified: (json['modified'] as num?)?.toInt(),
      modifiedSeconds: (json['modifiedSeconds'] as num?)?.toInt() ?? 0,
      mime: json['mime'] as String? ?? 'application/octet-stream',
      mode: (json['mode'] as num?)?.toInt() ?? 0,
      sourceIdentity: json['sourceIdentity'] as String?,
      sourceStamp: _readStamp(json['sourceStamp'] as Map<String, dynamic>?),
      selectable: json['selectable'] as bool? ?? false,
      errorCode: json['errorCode'] as String?,
      reason: json['reason'] as String?,
    );

Map<String, dynamic> _$FileCatalogEntryToJson(_FileCatalogEntry instance) =>
    <String, dynamic>{
      'name': instance.name,
      'path': instance.path,
      'kind': instance.kind,
      'isDirectory': instance.isDirectory,
      'isSymlink': instance.isSymlink,
      'nameIsUtf8': instance.nameIsUtf8,
      'canOpen': instance.canOpen,
      'canManage': instance.canManage,
      'size': instance.size,
      'modified': instance.modified,
      'modifiedSeconds': instance.modifiedSeconds,
      'mime': instance.mime,
      'mode': instance.mode,
      'sourceIdentity': instance.sourceIdentity,
      'sourceStamp': ?_writeStamp(instance.sourceStamp),
      'selectable': instance.selectable,
      'errorCode': ?instance.errorCode,
      'reason': ?instance.reason,
    };

_FileCatalogIssue _$FileCatalogIssueFromJson(Map<String, dynamic> json) =>
    _FileCatalogIssue(
      path: json['path'] as String,
      code: json['code'] as String,
      reason: json['reason'] as String,
    );

Map<String, dynamic> _$FileCatalogIssueToJson(_FileCatalogIssue instance) =>
    <String, dynamic>{
      'path': instance.path,
      'code': instance.code,
      'reason': instance.reason,
    };
