// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'document_outcome.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DocumentSource _$DocumentSourceFromJson(Map<String, dynamic> json) =>
    _DocumentSource(
      sourceId: json['sourceId'] as String,
      localPath: json['localPath'] as String,
      kind: $enumDecode(_$DocumentKindEnumMap, json['kind']),
    );

Map<String, dynamic> _$DocumentSourceToJson(_DocumentSource instance) =>
    <String, dynamic>{
      'sourceId': instance.sourceId,
      'localPath': instance.localPath,
      'kind': _$DocumentKindEnumMap[instance.kind]!,
    };

const _$DocumentKindEnumMap = {
  DocumentKind.file: 'file',
  DocumentKind.directory: 'directory',
};

_DocumentIssue _$DocumentIssueFromJson(Map<String, dynamic> json) =>
    _DocumentIssue(
      path: json['path'] as String? ?? '',
      code: json['code'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );

Map<String, dynamic> _$DocumentIssueToJson(_DocumentIssue instance) =>
    <String, dynamic>{
      'path': instance.path,
      'code': instance.code,
      'message': instance.message,
    };

_DocumentOutcome _$DocumentOutcomeFromJson(Map<String, dynamic> json) =>
    _DocumentOutcome(
      status: $enumDecode(_$DocumentOutcomeStatusEnumMap, json['status']),
      operationId: json['operationId'] as String?,
      managedSourceId: json['managedSourceId'] as String?,
      localPath: json['localPath'] as String?,
      uri: json['uri'] as String?,
      name: json['name'] as String?,
      bytes: (json['bytes'] as num?)?.toInt(),
      files: (json['files'] as num?)?.toInt(),
      directories: (json['directories'] as num?)?.toInt(),
      skipped: (json['skipped'] as num?)?.toInt(),
      errorCount: (json['errorCount'] as num?)?.toInt(),
      errorsTruncated: json['errorsTruncated'] as bool?,
      partialDestinationPossible: json['partialDestinationPossible'] as bool?,
      cacheRetained: json['cacheRetained'] as bool?,
      errors:
          (json['errors'] as List<dynamic>?)
              ?.map((e) => DocumentIssue.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$DocumentOutcomeToJson(_DocumentOutcome instance) =>
    <String, dynamic>{
      'status': _$DocumentOutcomeStatusEnumMap[instance.status]!,
      'operationId': ?instance.operationId,
      'managedSourceId': ?instance.managedSourceId,
      'localPath': ?instance.localPath,
      'uri': ?instance.uri,
      'name': ?instance.name,
      'bytes': ?instance.bytes,
      'files': ?instance.files,
      'directories': ?instance.directories,
      'skipped': ?instance.skipped,
      'errorCount': ?instance.errorCount,
      'errorsTruncated': ?instance.errorsTruncated,
      'partialDestinationPossible': ?instance.partialDestinationPossible,
      'cacheRetained': ?instance.cacheRetained,
      'errors': instance.errors.map((e) => e.toJson()).toList(),
    };

const _$DocumentOutcomeStatusEnumMap = {
  DocumentOutcomeStatus.pending: 'pending',
  DocumentOutcomeStatus.imported: 'imported',
  DocumentOutcomeStatus.saved: 'saved',
  DocumentOutcomeStatus.partial: 'partial',
  DocumentOutcomeStatus.failed: 'failed',
  DocumentOutcomeStatus.cancelled: 'cancelled',
  DocumentOutcomeStatus.resultUnknown: 'result_unknown',
};

_DocumentConflict _$DocumentConflictFromJson(Map<String, dynamic> json) =>
    _DocumentConflict(
      operationId: json['operationId'] as String,
      conflictId: json['conflictId'] as String,
      name: json['name'] as String,
    );

Map<String, dynamic> _$DocumentConflictToJson(_DocumentConflict instance) =>
    <String, dynamic>{
      'operationId': instance.operationId,
      'conflictId': instance.conflictId,
      'name': instance.name,
    };
