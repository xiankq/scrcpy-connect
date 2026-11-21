// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'file_transfer_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FileTransferRecord _$FileTransferRecordFromJson(Map<String, dynamic> json) =>
    _FileTransferRecord(
      id: json['id'] as String,
      deviceId: json['deviceId'] as String,
      batchId: json['batchId'] as String,
      direction: $enumDecode(_$FileTransferDirectionEnumMap, json['direction']),
      source: json['source'] as String,
      destination: json['destination'] as String,
      name: json['name'] as String? ?? '文件传输',
      shareId: json['shareId'] as String?,
      parentId: json['parentId'] as String?,
      sourceStamp: json['sourceStamp'] == null
          ? null
          : FileStamp.fromJson(json['sourceStamp'] as Map<String, dynamic>),
      kind:
          $enumDecodeNullable(
            _$FileTransferKindEnumMap,
            json['kind'],
            unknownValue: FileTransferKind.unsupported,
          ) ??
          FileTransferKind.file,
      status:
          $enumDecodeNullable(
            _$FileTransferStatusEnumMap,
            json['status'],
            unknownValue: FileTransferStatus.unknown,
          ) ??
          FileTransferStatus.unknown,
      policy:
          $enumDecodeNullable(_$FileTransferConflictEnumMap, json['policy']) ??
          FileTransferConflict.ask,
      destinationScope:
          $enumDecodeNullable(
            _$FileTransferDestinationEnumMap,
            json['destinationScope'],
          ) ??
          FileTransferDestination.localPath,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      generation: (json['generation'] as num?)?.toInt() ?? 0,
      itemIndex: (json['itemIndex'] as num?)?.toInt() ?? 0,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 1,
      transferred: (json['transferred'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt(),
      temporaryPath: json['temporaryPath'] as String?,
      saveMode: json['saveMode'] as String?,
      errorCode: json['errorCode'] as String?,
      error: json['error'] as String?,
      treeVerified: json['treeVerified'] as bool? ?? false,
      treeComplete: json['treeComplete'] as bool? ?? false,
      partialDestinationPossible:
          json['partialDestinationPossible'] as bool? ?? false,
      cleanupPending: json['cleanupPending'] as bool? ?? false,
      historyHidden: json['historyHidden'] as bool? ?? false,
      cleanupScopeId: json['cleanupScopeId'] as String?,
      cleanupScopeKey: json['cleanupScopeKey'] as String?,
    );

Map<String, dynamic> _$FileTransferRecordToJson(_FileTransferRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'deviceId': instance.deviceId,
      'batchId': instance.batchId,
      'direction': _$FileTransferDirectionEnumMap[instance.direction]!,
      'source': instance.source,
      'destination': instance.destination,
      'name': instance.name,
      'shareId': ?instance.shareId,
      'parentId': ?instance.parentId,
      'sourceStamp': ?instance.sourceStamp?.toJson(),
      'kind': _$FileTransferKindEnumMap[instance.kind]!,
      'status': _$FileTransferStatusEnumMap[instance.status]!,
      'policy': _$FileTransferConflictEnumMap[instance.policy]!,
      'destinationScope':
          _$FileTransferDestinationEnumMap[instance.destinationScope]!,
      'createdAt': instance.createdAt,
      'generation': instance.generation,
      'itemIndex': instance.itemIndex,
      'itemCount': instance.itemCount,
      'transferred': instance.transferred,
      'total': ?instance.total,
      'temporaryPath': ?instance.temporaryPath,
      'saveMode': ?instance.saveMode,
      'errorCode': ?instance.errorCode,
      'error': ?instance.error,
      'treeVerified': instance.treeVerified,
      'treeComplete': instance.treeComplete,
      'partialDestinationPossible': instance.partialDestinationPossible,
      'cleanupPending': instance.cleanupPending,
      'historyHidden': instance.historyHidden,
      'cleanupScopeId': ?instance.cleanupScopeId,
      'cleanupScopeKey': ?instance.cleanupScopeKey,
    };

const _$FileTransferDirectionEnumMap = {
  FileTransferDirection.push: 'push',
  FileTransferDirection.pull: 'pull',
};

const _$FileTransferKindEnumMap = {
  FileTransferKind.file: 'file',
  FileTransferKind.directory: 'directory',
  FileTransferKind.symlink: 'symlink',
  FileTransferKind.unsupported: 'unsupported',
};

const _$FileTransferStatusEnumMap = {
  FileTransferStatus.unknown: 'unknown',
  FileTransferStatus.queued: 'queued',
  FileTransferStatus.running: 'running',
  FileTransferStatus.finalizing: 'finalizing',
  FileTransferStatus.cancelling: 'cancelling',
  FileTransferStatus.conflict: 'conflict',
  FileTransferStatus.completed: 'completed',
  FileTransferStatus.skipped: 'skipped',
  FileTransferStatus.failed: 'failed',
  FileTransferStatus.cancelled: 'cancelled',
  FileTransferStatus.interrupted: 'interrupted',
  FileTransferStatus.paused: 'paused',
  FileTransferStatus.partial: 'partial',
  FileTransferStatus.partialFailure: 'partialFailure',
  FileTransferStatus.completedWithSkips: 'completedWithSkips',
};

const _$FileTransferConflictEnumMap = {
  FileTransferConflict.ask: 'ask',
  FileTransferConflict.keepBoth: 'keepBoth',
  FileTransferConflict.replace: 'replace',
  FileTransferConflict.skip: 'skip',
};

const _$FileTransferDestinationEnumMap = {
  FileTransferDestination.localPath: 'localPath',
  FileTransferDestination.privateCache: 'privateCache',
};
