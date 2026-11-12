// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'incoming_shares.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_IncomingShareFile _$IncomingShareFileFromJson(Map<String, dynamic> json) =>
    _IncomingShareFile(
      name: json['name'] as String,
      localPath: json['localPath'] as String,
      size: (json['size'] as num).toInt(),
    );

Map<String, dynamic> _$IncomingShareFileToJson(_IncomingShareFile instance) =>
    <String, dynamic>{
      'name': instance.name,
      'localPath': instance.localPath,
      'size': instance.size,
    };

_IncomingShare _$IncomingShareFromJson(
  Map<String, dynamic> json,
) => _IncomingShare(
  shareId: json['shareId'] as String,
  status: $enumDecode(_$IncomingShareStatusEnumMap, json['status']),
  text: json['text'] as String? ?? '',
  mime: json['mime'] as String?,
  files:
      (json['files'] as List<dynamic>?)
          ?.map((e) => IncomingShareFile.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  errors:
      (json['errors'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
);

Map<String, dynamic> _$IncomingShareToJson(_IncomingShare instance) =>
    <String, dynamic>{
      'shareId': instance.shareId,
      'status': _$IncomingShareStatusEnumMap[instance.status]!,
      'text': instance.text,
      'mime': instance.mime,
      'files': instance.files.map((e) => e.toJson()).toList(),
      'errors': instance.errors,
    };

const _$IncomingShareStatusEnumMap = {
  IncomingShareStatus.starting: 'starting',
  IncomingShareStatus.importing: 'importing',
  IncomingShareStatus.ready: 'ready',
  IncomingShareStatus.error: 'error',
  IncomingShareStatus.submitted: 'submitted',
};
