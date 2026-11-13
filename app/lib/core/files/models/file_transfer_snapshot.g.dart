// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'file_transfer_snapshot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FileTransferSnapshot _$FileTransferSnapshotFromJson(
  Map<String, dynamic> json,
) => _FileTransferSnapshot(
  id: json['id'] as String,
  deviceId: json['deviceId'] as String? ?? '',
  batchId: json['batchId'] as String?,
  parentId: json['parentId'] as String?,
  name: json['name'] as String? ?? '文件传输',
  source: json['source'] as String? ?? '',
  destination: json['destination'] as String? ?? '',
  direction:
      $enumDecodeNullable(_$FileTransferDirectionEnumMap, json['direction']) ??
      FileTransferDirection.pull,
  destinationScope:
      $enumDecodeNullable(
        _$FileTransferDestinationEnumMap,
        json['destinationScope'],
      ) ??
      FileTransferDestination.localPath,
  kind:
      $enumDecodeNullable(_$FileTransferKindEnumMap, json['kind']) ??
      FileTransferKind.file,
  status:
      $enumDecodeNullable(_$FileTransferStatusEnumMap, json['status']) ??
      FileTransferStatus.unknown,
  policy:
      $enumDecodeNullable(_$FileTransferConflictEnumMap, json['policy']) ??
      FileTransferConflict.ask,
  generation: (json['generation'] as num?)?.toInt() ?? 0,
  itemIndex: (json['itemIndex'] as num?)?.toInt() ?? 0,
  itemCount: (json['itemCount'] as num?)?.toInt() ?? 1,
  transferred: (json['transferred'] as num?)?.toInt() ?? 0,
  total: (json['total'] as num?)?.toInt(),
  completedBytes: (json['completedBytes'] as num?)?.toInt(),
  totalBytes: (json['totalBytes'] as num?)?.toInt(),
  deviceName: json['deviceName'] as String?,
  sourceLabel: json['sourceLabel'] as String?,
  destinationLabel: json['destinationLabel'] as String?,
  localPath: json['localPath'] as String?,
  partialLocalPath: json['partialLocalPath'] as String?,
  error: json['error'] as String?,
  errorCode: json['errorCode'] as String?,
  exportReason: json['exportReason'] as String?,
  saveMode: json['saveMode'] as String?,
  cleanupPending: json['cleanupPending'] as bool? ?? false,
  partialDestinationPossible:
      json['partialDestinationPossible'] as bool? ?? false,
  treeVerified: json['treeVerified'] as bool? ?? false,
  treeComplete: json['treeComplete'] as bool? ?? false,
  cacheEvicted: json['cacheEvicted'] as bool? ?? false,
  canResume: json['canResume'] as bool? ?? false,
  canRestart: json['canRestart'] as bool? ?? false,
  canCancel: json['canCancel'] as bool? ?? false,
  canExport: json['canExport'] as bool? ?? false,
  canExportPartial: json['canExportPartial'] as bool? ?? false,
  restartFromBeginning: json['restartFromBeginning'] as bool? ?? true,
  restartRequiresSourceCheck:
      json['restartRequiresSourceCheck'] as bool? ?? true,
  items:
      (json['items'] as List<dynamic>?)
          ?.map((e) => FileTransferSnapshot.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  batch: json['batch'] == null
      ? null
      : FileTransferBatch.fromJson(json['batch'] as Map<String, dynamic>),
);

Map<String, dynamic> _$FileTransferSnapshotToJson(
  _FileTransferSnapshot instance,
) => <String, dynamic>{
  'id': instance.id,
  'deviceId': instance.deviceId,
  'batchId': instance.batchId,
  'parentId': instance.parentId,
  'name': instance.name,
  'source': instance.source,
  'destination': instance.destination,
  'direction': _$FileTransferDirectionEnumMap[instance.direction]!,
  'destinationScope':
      _$FileTransferDestinationEnumMap[instance.destinationScope]!,
  'kind': _$FileTransferKindEnumMap[instance.kind]!,
  'status': _$FileTransferStatusEnumMap[instance.status]!,
  'policy': _$FileTransferConflictEnumMap[instance.policy]!,
  'generation': instance.generation,
  'itemIndex': instance.itemIndex,
  'itemCount': instance.itemCount,
  'transferred': instance.transferred,
  'total': instance.total,
  'completedBytes': instance.completedBytes,
  'totalBytes': instance.totalBytes,
  'deviceName': instance.deviceName,
  'sourceLabel': instance.sourceLabel,
  'destinationLabel': instance.destinationLabel,
  'localPath': instance.localPath,
  'partialLocalPath': instance.partialLocalPath,
  'error': instance.error,
  'errorCode': instance.errorCode,
  'exportReason': instance.exportReason,
  'saveMode': instance.saveMode,
  'cleanupPending': instance.cleanupPending,
  'partialDestinationPossible': instance.partialDestinationPossible,
  'treeVerified': instance.treeVerified,
  'treeComplete': instance.treeComplete,
  'cacheEvicted': instance.cacheEvicted,
  'canResume': instance.canResume,
  'canRestart': instance.canRestart,
  'canCancel': instance.canCancel,
  'canExport': instance.canExport,
  'canExportPartial': instance.canExportPartial,
  'restartFromBeginning': instance.restartFromBeginning,
  'restartRequiresSourceCheck': instance.restartRequiresSourceCheck,
  'items': instance.items.map((e) => e.toJson()).toList(),
  'batch': instance.batch?.toJson(),
};

const _$FileTransferDirectionEnumMap = {
  FileTransferDirection.push: 'push',
  FileTransferDirection.pull: 'pull',
};

const _$FileTransferDestinationEnumMap = {
  FileTransferDestination.localPath: 'localPath',
  FileTransferDestination.privateCache: 'privateCache',
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

_FileTransferBatch _$FileTransferBatchFromJson(Map<String, dynamic> json) =>
    _FileTransferBatch(
      batchId: json['batchId'] as String,
      deviceId: json['deviceId'] as String? ?? '',
      direction:
          $enumDecodeNullable(
            _$FileTransferDirectionEnumMap,
            json['direction'],
          ) ??
          FileTransferDirection.pull,
      destinationScope:
          $enumDecodeNullable(
            _$FileTransferDestinationEnumMap,
            json['destinationScope'],
          ) ??
          FileTransferDestination.localPath,
      status:
          $enumDecodeNullable(_$FileTransferStatusEnumMap, json['status']) ??
          FileTransferStatus.unknown,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      fileCount: (json['fileCount'] as num?)?.toInt() ?? 0,
      directoryCount: (json['directoryCount'] as num?)?.toInt() ?? 0,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      cancelled: (json['cancelled'] as num?)?.toInt() ?? 0,
      skipped: (json['skipped'] as num?)?.toInt() ?? 0,
      interrupted: (json['interrupted'] as num?)?.toInt() ?? 0,
      transferred: (json['transferred'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      canCancel: json['canCancel'] as bool? ?? false,
      selectedRootCount: (json['selectedRootCount'] as num?)?.toInt() ?? 0,
      canResume: json['canResume'] as bool? ?? false,
      canRestart: json['canRestart'] as bool? ?? false,
      selectionSnapshot: json['selectionSnapshot'] as bool? ?? true,
    );

Map<String, dynamic> _$FileTransferBatchToJson(_FileTransferBatch instance) =>
    <String, dynamic>{
      'batchId': instance.batchId,
      'deviceId': instance.deviceId,
      'direction': _$FileTransferDirectionEnumMap[instance.direction]!,
      'destinationScope':
          _$FileTransferDestinationEnumMap[instance.destinationScope]!,
      'status': _$FileTransferStatusEnumMap[instance.status]!,
      'itemCount': instance.itemCount,
      'fileCount': instance.fileCount,
      'directoryCount': instance.directoryCount,
      'completed': instance.completed,
      'failed': instance.failed,
      'cancelled': instance.cancelled,
      'skipped': instance.skipped,
      'interrupted': instance.interrupted,
      'transferred': instance.transferred,
      'total': instance.total,
      'canCancel': instance.canCancel,
      'selectedRootCount': instance.selectedRootCount,
      'canResume': instance.canResume,
      'canRestart': instance.canRestart,
      'selectionSnapshot': instance.selectionSnapshot,
    };

_FileTransferCollection _$FileTransferCollectionFromJson(
  Map<String, dynamic> json,
) => _FileTransferCollection(
  transfers:
      (json['transfers'] as List<dynamic>?)
          ?.map((e) => FileTransferSnapshot.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  batches:
      (json['batches'] as List<dynamic>?)
          ?.map((e) => FileTransferBatch.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$FileTransferCollectionToJson(
  _FileTransferCollection instance,
) => <String, dynamic>{
  'transfers': instance.transfers.map((e) => e.toJson()).toList(),
  'batches': instance.batches.map((e) => e.toJson()).toList(),
};
