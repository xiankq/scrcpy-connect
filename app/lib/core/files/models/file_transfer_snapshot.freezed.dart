// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'file_transfer_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FileTransferSnapshot {

 String get id; String get deviceId; String? get batchId; String? get parentId; String get name; String get source; String get destination; FileTransferDirection get direction; FileTransferDestination get destinationScope; FileTransferKind get kind; FileTransferStatus get status; FileTransferConflict get policy; int get generation; int get itemIndex; int get itemCount; int get transferred; int? get total; int? get completedBytes; int? get totalBytes; int? get endedAt; String? get deviceName; String? get sourceLabel; String? get destinationLabel; String? get localPath; String? get partialLocalPath; String? get error; String? get errorCode; String? get exportReason; String? get saveMode; bool get cleanupPending; bool get historyHidden; bool get partialDestinationPossible; bool get treeVerified; bool get treeComplete; bool get cacheEvicted; bool get canResume; bool get canRestart; bool get canCancel; bool get canExport; bool get canExportPartial; bool get restartFromBeginning; bool get restartRequiresSourceCheck; List<FileTransferSnapshot> get items; FileTransferBatch? get batch;
/// Create a copy of FileTransferSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileTransferSnapshotCopyWith<FileTransferSnapshot> get copyWith => _$FileTransferSnapshotCopyWithImpl<FileTransferSnapshot>(this as FileTransferSnapshot, _$identity);

  /// Serializes this FileTransferSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FileTransferSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileTransferSnapshot&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.batchId, _this.batchId) || other.batchId == _this.batchId)&&(identical(other.parentId, _this.parentId) || other.parentId == _this.parentId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.destination, _this.destination) || other.destination == _this.destination)&&(identical(other.direction, _this.direction) || other.direction == _this.direction)&&(identical(other.destinationScope, _this.destinationScope) || other.destinationScope == _this.destinationScope)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.policy, _this.policy) || other.policy == _this.policy)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.itemIndex, _this.itemIndex) || other.itemIndex == _this.itemIndex)&&(identical(other.itemCount, _this.itemCount) || other.itemCount == _this.itemCount)&&(identical(other.transferred, _this.transferred) || other.transferred == _this.transferred)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.completedBytes, _this.completedBytes) || other.completedBytes == _this.completedBytes)&&(identical(other.totalBytes, _this.totalBytes) || other.totalBytes == _this.totalBytes)&&(identical(other.endedAt, _this.endedAt) || other.endedAt == _this.endedAt)&&(identical(other.deviceName, _this.deviceName) || other.deviceName == _this.deviceName)&&(identical(other.sourceLabel, _this.sourceLabel) || other.sourceLabel == _this.sourceLabel)&&(identical(other.destinationLabel, _this.destinationLabel) || other.destinationLabel == _this.destinationLabel)&&(identical(other.localPath, _this.localPath) || other.localPath == _this.localPath)&&(identical(other.partialLocalPath, _this.partialLocalPath) || other.partialLocalPath == _this.partialLocalPath)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.errorCode, _this.errorCode) || other.errorCode == _this.errorCode)&&(identical(other.exportReason, _this.exportReason) || other.exportReason == _this.exportReason)&&(identical(other.saveMode, _this.saveMode) || other.saveMode == _this.saveMode)&&(identical(other.cleanupPending, _this.cleanupPending) || other.cleanupPending == _this.cleanupPending)&&(identical(other.historyHidden, _this.historyHidden) || other.historyHidden == _this.historyHidden)&&(identical(other.partialDestinationPossible, _this.partialDestinationPossible) || other.partialDestinationPossible == _this.partialDestinationPossible)&&(identical(other.treeVerified, _this.treeVerified) || other.treeVerified == _this.treeVerified)&&(identical(other.treeComplete, _this.treeComplete) || other.treeComplete == _this.treeComplete)&&(identical(other.cacheEvicted, _this.cacheEvicted) || other.cacheEvicted == _this.cacheEvicted)&&(identical(other.canResume, _this.canResume) || other.canResume == _this.canResume)&&(identical(other.canRestart, _this.canRestart) || other.canRestart == _this.canRestart)&&(identical(other.canCancel, _this.canCancel) || other.canCancel == _this.canCancel)&&(identical(other.canExport, _this.canExport) || other.canExport == _this.canExport)&&(identical(other.canExportPartial, _this.canExportPartial) || other.canExportPartial == _this.canExportPartial)&&(identical(other.restartFromBeginning, _this.restartFromBeginning) || other.restartFromBeginning == _this.restartFromBeginning)&&(identical(other.restartRequiresSourceCheck, _this.restartRequiresSourceCheck) || other.restartRequiresSourceCheck == _this.restartRequiresSourceCheck)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.batch, _this.batch) || other.batch == _this.batch));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FileTransferSnapshot;
  return Object.hashAll([runtimeType,_this.id,_this.deviceId,_this.batchId,_this.parentId,_this.name,_this.source,_this.destination,_this.direction,_this.destinationScope,_this.kind,_this.status,_this.policy,_this.generation,_this.itemIndex,_this.itemCount,_this.transferred,_this.total,_this.completedBytes,_this.totalBytes,_this.endedAt,_this.deviceName,_this.sourceLabel,_this.destinationLabel,_this.localPath,_this.partialLocalPath,_this.error,_this.errorCode,_this.exportReason,_this.saveMode,_this.cleanupPending,_this.historyHidden,_this.partialDestinationPossible,_this.treeVerified,_this.treeComplete,_this.cacheEvicted,_this.canResume,_this.canRestart,_this.canCancel,_this.canExport,_this.canExportPartial,_this.restartFromBeginning,_this.restartRequiresSourceCheck,const DeepCollectionEquality().hash(_this.items),_this.batch]);
}

@override
String toString() {
  final _this = this as FileTransferSnapshot;
  return 'FileTransferSnapshot(id: ${_this.id}, deviceId: ${_this.deviceId}, batchId: ${_this.batchId}, parentId: ${_this.parentId}, name: ${_this.name}, source: ${_this.source}, destination: ${_this.destination}, direction: ${_this.direction}, destinationScope: ${_this.destinationScope}, kind: ${_this.kind}, status: ${_this.status}, policy: ${_this.policy}, generation: ${_this.generation}, itemIndex: ${_this.itemIndex}, itemCount: ${_this.itemCount}, transferred: ${_this.transferred}, total: ${_this.total}, completedBytes: ${_this.completedBytes}, totalBytes: ${_this.totalBytes}, endedAt: ${_this.endedAt}, deviceName: ${_this.deviceName}, sourceLabel: ${_this.sourceLabel}, destinationLabel: ${_this.destinationLabel}, localPath: ${_this.localPath}, partialLocalPath: ${_this.partialLocalPath}, error: ${_this.error}, errorCode: ${_this.errorCode}, exportReason: ${_this.exportReason}, saveMode: ${_this.saveMode}, cleanupPending: ${_this.cleanupPending}, historyHidden: ${_this.historyHidden}, partialDestinationPossible: ${_this.partialDestinationPossible}, treeVerified: ${_this.treeVerified}, treeComplete: ${_this.treeComplete}, cacheEvicted: ${_this.cacheEvicted}, canResume: ${_this.canResume}, canRestart: ${_this.canRestart}, canCancel: ${_this.canCancel}, canExport: ${_this.canExport}, canExportPartial: ${_this.canExportPartial}, restartFromBeginning: ${_this.restartFromBeginning}, restartRequiresSourceCheck: ${_this.restartRequiresSourceCheck}, items: ${_this.items}, batch: ${_this.batch})';
}


}

/// @nodoc
abstract mixin class $FileTransferSnapshotCopyWith<$Res>  {
  factory $FileTransferSnapshotCopyWith(FileTransferSnapshot value, $Res Function(FileTransferSnapshot) _then) = _$FileTransferSnapshotCopyWithImpl;
@useResult
$Res call({
 String id, String deviceId, String? batchId, String? parentId, String name, String source, String destination, FileTransferDirection direction, FileTransferDestination destinationScope, FileTransferKind kind, FileTransferStatus status, FileTransferConflict policy, int generation, int itemIndex, int itemCount, int transferred, int? total, int? completedBytes, int? totalBytes, int? endedAt, String? deviceName, String? sourceLabel, String? destinationLabel, String? localPath, String? partialLocalPath, String? error, String? errorCode, String? exportReason, String? saveMode, bool cleanupPending, bool historyHidden, bool partialDestinationPossible, bool treeVerified, bool treeComplete, bool cacheEvicted, bool canResume, bool canRestart, bool canCancel, bool canExport, bool canExportPartial, bool restartFromBeginning, bool restartRequiresSourceCheck, List<FileTransferSnapshot> items, FileTransferBatch? batch
});


$FileTransferBatchCopyWith<$Res>? get batch;

}
/// @nodoc
class _$FileTransferSnapshotCopyWithImpl<$Res>
    implements $FileTransferSnapshotCopyWith<$Res> {
  _$FileTransferSnapshotCopyWithImpl(this._self, this._then);

  final FileTransferSnapshot _self;
  final $Res Function(FileTransferSnapshot) _then;

/// Create a copy of FileTransferSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? deviceId = null,Object? batchId = freezed,Object? parentId = freezed,Object? name = null,Object? source = null,Object? destination = null,Object? direction = null,Object? destinationScope = null,Object? kind = null,Object? status = null,Object? policy = null,Object? generation = null,Object? itemIndex = null,Object? itemCount = null,Object? transferred = null,Object? total = freezed,Object? completedBytes = freezed,Object? totalBytes = freezed,Object? endedAt = freezed,Object? deviceName = freezed,Object? sourceLabel = freezed,Object? destinationLabel = freezed,Object? localPath = freezed,Object? partialLocalPath = freezed,Object? error = freezed,Object? errorCode = freezed,Object? exportReason = freezed,Object? saveMode = freezed,Object? cleanupPending = null,Object? historyHidden = null,Object? partialDestinationPossible = null,Object? treeVerified = null,Object? treeComplete = null,Object? cacheEvicted = null,Object? canResume = null,Object? canRestart = null,Object? canCancel = null,Object? canExport = null,Object? canExportPartial = null,Object? restartFromBeginning = null,Object? restartRequiresSourceCheck = null,Object? items = null,Object? batch = freezed,}) {
  return _then(FileTransferSnapshot(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,batchId: freezed == batchId ? _self.batchId : batchId // ignore: cast_nullable_to_non_nullable
as String?,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,destination: null == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as FileTransferDirection,destinationScope: null == destinationScope ? _self.destinationScope : destinationScope // ignore: cast_nullable_to_non_nullable
as FileTransferDestination,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as FileTransferKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as FileTransferStatus,policy: null == policy ? _self.policy : policy // ignore: cast_nullable_to_non_nullable
as FileTransferConflict,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,itemIndex: null == itemIndex ? _self.itemIndex : itemIndex // ignore: cast_nullable_to_non_nullable
as int,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,transferred: null == transferred ? _self.transferred : transferred // ignore: cast_nullable_to_non_nullable
as int,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int?,completedBytes: freezed == completedBytes ? _self.completedBytes : completedBytes // ignore: cast_nullable_to_non_nullable
as int?,totalBytes: freezed == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int?,endedAt: freezed == endedAt ? _self.endedAt : endedAt // ignore: cast_nullable_to_non_nullable
as int?,deviceName: freezed == deviceName ? _self.deviceName : deviceName // ignore: cast_nullable_to_non_nullable
as String?,sourceLabel: freezed == sourceLabel ? _self.sourceLabel : sourceLabel // ignore: cast_nullable_to_non_nullable
as String?,destinationLabel: freezed == destinationLabel ? _self.destinationLabel : destinationLabel // ignore: cast_nullable_to_non_nullable
as String?,localPath: freezed == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String?,partialLocalPath: freezed == partialLocalPath ? _self.partialLocalPath : partialLocalPath // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,exportReason: freezed == exportReason ? _self.exportReason : exportReason // ignore: cast_nullable_to_non_nullable
as String?,saveMode: freezed == saveMode ? _self.saveMode : saveMode // ignore: cast_nullable_to_non_nullable
as String?,cleanupPending: null == cleanupPending ? _self.cleanupPending : cleanupPending // ignore: cast_nullable_to_non_nullable
as bool,historyHidden: null == historyHidden ? _self.historyHidden : historyHidden // ignore: cast_nullable_to_non_nullable
as bool,partialDestinationPossible: null == partialDestinationPossible ? _self.partialDestinationPossible : partialDestinationPossible // ignore: cast_nullable_to_non_nullable
as bool,treeVerified: null == treeVerified ? _self.treeVerified : treeVerified // ignore: cast_nullable_to_non_nullable
as bool,treeComplete: null == treeComplete ? _self.treeComplete : treeComplete // ignore: cast_nullable_to_non_nullable
as bool,cacheEvicted: null == cacheEvicted ? _self.cacheEvicted : cacheEvicted // ignore: cast_nullable_to_non_nullable
as bool,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,canRestart: null == canRestart ? _self.canRestart : canRestart // ignore: cast_nullable_to_non_nullable
as bool,canCancel: null == canCancel ? _self.canCancel : canCancel // ignore: cast_nullable_to_non_nullable
as bool,canExport: null == canExport ? _self.canExport : canExport // ignore: cast_nullable_to_non_nullable
as bool,canExportPartial: null == canExportPartial ? _self.canExportPartial : canExportPartial // ignore: cast_nullable_to_non_nullable
as bool,restartFromBeginning: null == restartFromBeginning ? _self.restartFromBeginning : restartFromBeginning // ignore: cast_nullable_to_non_nullable
as bool,restartRequiresSourceCheck: null == restartRequiresSourceCheck ? _self.restartRequiresSourceCheck : restartRequiresSourceCheck // ignore: cast_nullable_to_non_nullable
as bool,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<FileTransferSnapshot>,batch: freezed == batch ? _self.batch : batch // ignore: cast_nullable_to_non_nullable
as FileTransferBatch?,
  ));
}
/// Create a copy of FileTransferSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FileTransferBatchCopyWith<$Res>? get batch {
    if (_self.batch == null) {
    return null;
  }

  return $FileTransferBatchCopyWith<$Res>(_self.batch!, (value) {
    return _then(_self.copyWith(batch: value));
  });
}
}


/// Adds pattern-matching-related methods to [FileTransferSnapshot].
extension FileTransferSnapshotPatterns on FileTransferSnapshot {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileTransferSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileTransferSnapshot() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileTransferSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _FileTransferSnapshot():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileTransferSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _FileTransferSnapshot() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String deviceId,  String? batchId,  String? parentId,  String name,  String source,  String destination,  FileTransferDirection direction,  FileTransferDestination destinationScope,  FileTransferKind kind,  FileTransferStatus status,  FileTransferConflict policy,  int generation,  int itemIndex,  int itemCount,  int transferred,  int? total,  int? completedBytes,  int? totalBytes,  int? endedAt,  String? deviceName,  String? sourceLabel,  String? destinationLabel,  String? localPath,  String? partialLocalPath,  String? error,  String? errorCode,  String? exportReason,  String? saveMode,  bool cleanupPending,  bool historyHidden,  bool partialDestinationPossible,  bool treeVerified,  bool treeComplete,  bool cacheEvicted,  bool canResume,  bool canRestart,  bool canCancel,  bool canExport,  bool canExportPartial,  bool restartFromBeginning,  bool restartRequiresSourceCheck,  List<FileTransferSnapshot> items,  FileTransferBatch? batch)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileTransferSnapshot() when $default != null:
return $default(_that.id,_that.deviceId,_that.batchId,_that.parentId,_that.name,_that.source,_that.destination,_that.direction,_that.destinationScope,_that.kind,_that.status,_that.policy,_that.generation,_that.itemIndex,_that.itemCount,_that.transferred,_that.total,_that.completedBytes,_that.totalBytes,_that.endedAt,_that.deviceName,_that.sourceLabel,_that.destinationLabel,_that.localPath,_that.partialLocalPath,_that.error,_that.errorCode,_that.exportReason,_that.saveMode,_that.cleanupPending,_that.historyHidden,_that.partialDestinationPossible,_that.treeVerified,_that.treeComplete,_that.cacheEvicted,_that.canResume,_that.canRestart,_that.canCancel,_that.canExport,_that.canExportPartial,_that.restartFromBeginning,_that.restartRequiresSourceCheck,_that.items,_that.batch);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String deviceId,  String? batchId,  String? parentId,  String name,  String source,  String destination,  FileTransferDirection direction,  FileTransferDestination destinationScope,  FileTransferKind kind,  FileTransferStatus status,  FileTransferConflict policy,  int generation,  int itemIndex,  int itemCount,  int transferred,  int? total,  int? completedBytes,  int? totalBytes,  int? endedAt,  String? deviceName,  String? sourceLabel,  String? destinationLabel,  String? localPath,  String? partialLocalPath,  String? error,  String? errorCode,  String? exportReason,  String? saveMode,  bool cleanupPending,  bool historyHidden,  bool partialDestinationPossible,  bool treeVerified,  bool treeComplete,  bool cacheEvicted,  bool canResume,  bool canRestart,  bool canCancel,  bool canExport,  bool canExportPartial,  bool restartFromBeginning,  bool restartRequiresSourceCheck,  List<FileTransferSnapshot> items,  FileTransferBatch? batch)  $default,) {final _that = this;
switch (_that) {
case _FileTransferSnapshot():
return $default(_that.id,_that.deviceId,_that.batchId,_that.parentId,_that.name,_that.source,_that.destination,_that.direction,_that.destinationScope,_that.kind,_that.status,_that.policy,_that.generation,_that.itemIndex,_that.itemCount,_that.transferred,_that.total,_that.completedBytes,_that.totalBytes,_that.endedAt,_that.deviceName,_that.sourceLabel,_that.destinationLabel,_that.localPath,_that.partialLocalPath,_that.error,_that.errorCode,_that.exportReason,_that.saveMode,_that.cleanupPending,_that.historyHidden,_that.partialDestinationPossible,_that.treeVerified,_that.treeComplete,_that.cacheEvicted,_that.canResume,_that.canRestart,_that.canCancel,_that.canExport,_that.canExportPartial,_that.restartFromBeginning,_that.restartRequiresSourceCheck,_that.items,_that.batch);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String deviceId,  String? batchId,  String? parentId,  String name,  String source,  String destination,  FileTransferDirection direction,  FileTransferDestination destinationScope,  FileTransferKind kind,  FileTransferStatus status,  FileTransferConflict policy,  int generation,  int itemIndex,  int itemCount,  int transferred,  int? total,  int? completedBytes,  int? totalBytes,  int? endedAt,  String? deviceName,  String? sourceLabel,  String? destinationLabel,  String? localPath,  String? partialLocalPath,  String? error,  String? errorCode,  String? exportReason,  String? saveMode,  bool cleanupPending,  bool historyHidden,  bool partialDestinationPossible,  bool treeVerified,  bool treeComplete,  bool cacheEvicted,  bool canResume,  bool canRestart,  bool canCancel,  bool canExport,  bool canExportPartial,  bool restartFromBeginning,  bool restartRequiresSourceCheck,  List<FileTransferSnapshot> items,  FileTransferBatch? batch)?  $default,) {final _that = this;
switch (_that) {
case _FileTransferSnapshot() when $default != null:
return $default(_that.id,_that.deviceId,_that.batchId,_that.parentId,_that.name,_that.source,_that.destination,_that.direction,_that.destinationScope,_that.kind,_that.status,_that.policy,_that.generation,_that.itemIndex,_that.itemCount,_that.transferred,_that.total,_that.completedBytes,_that.totalBytes,_that.endedAt,_that.deviceName,_that.sourceLabel,_that.destinationLabel,_that.localPath,_that.partialLocalPath,_that.error,_that.errorCode,_that.exportReason,_that.saveMode,_that.cleanupPending,_that.historyHidden,_that.partialDestinationPossible,_that.treeVerified,_that.treeComplete,_that.cacheEvicted,_that.canResume,_that.canRestart,_that.canCancel,_that.canExport,_that.canExportPartial,_that.restartFromBeginning,_that.restartRequiresSourceCheck,_that.items,_that.batch);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true)
class _FileTransferSnapshot extends FileTransferSnapshot {
  const _FileTransferSnapshot({required this.id, this.deviceId = '', this.batchId, this.parentId, this.name = '文件传输', this.source = '', this.destination = '', this.direction = FileTransferDirection.pull, this.destinationScope = FileTransferDestination.localPath, this.kind = FileTransferKind.file, this.status = FileTransferStatus.unknown, this.policy = FileTransferConflict.ask, this.generation = 0, this.itemIndex = 0, this.itemCount = 1, this.transferred = 0, this.total, this.completedBytes, this.totalBytes, this.endedAt, this.deviceName, this.sourceLabel, this.destinationLabel, this.localPath, this.partialLocalPath, this.error, this.errorCode, this.exportReason, this.saveMode, this.cleanupPending = false, this.historyHidden = false, this.partialDestinationPossible = false, this.treeVerified = false, this.treeComplete = false, this.cacheEvicted = false, this.canResume = false, this.canRestart = false, this.canCancel = false, this.canExport = false, this.canExportPartial = false, this.restartFromBeginning = true, this.restartRequiresSourceCheck = true,  List<FileTransferSnapshot> items = const [], this.batch}): _items = items,super._();
  factory _FileTransferSnapshot.fromJson(Map<String, dynamic> json) => _$FileTransferSnapshotFromJson(json);

@override final  String id;
@override@JsonKey() final  String deviceId;
@override final  String? batchId;
@override final  String? parentId;
@override@JsonKey() final  String name;
@override@JsonKey() final  String source;
@override@JsonKey() final  String destination;
@override@JsonKey() final  FileTransferDirection direction;
@override@JsonKey() final  FileTransferDestination destinationScope;
@override@JsonKey() final  FileTransferKind kind;
@override@JsonKey() final  FileTransferStatus status;
@override@JsonKey() final  FileTransferConflict policy;
@override@JsonKey() final  int generation;
@override@JsonKey() final  int itemIndex;
@override@JsonKey() final  int itemCount;
@override@JsonKey() final  int transferred;
@override final  int? total;
@override final  int? completedBytes;
@override final  int? totalBytes;
@override final  int? endedAt;
@override final  String? deviceName;
@override final  String? sourceLabel;
@override final  String? destinationLabel;
@override final  String? localPath;
@override final  String? partialLocalPath;
@override final  String? error;
@override final  String? errorCode;
@override final  String? exportReason;
@override final  String? saveMode;
@override@JsonKey() final  bool cleanupPending;
@override@JsonKey() final  bool historyHidden;
@override@JsonKey() final  bool partialDestinationPossible;
@override@JsonKey() final  bool treeVerified;
@override@JsonKey() final  bool treeComplete;
@override@JsonKey() final  bool cacheEvicted;
@override@JsonKey() final  bool canResume;
@override@JsonKey() final  bool canRestart;
@override@JsonKey() final  bool canCancel;
@override@JsonKey() final  bool canExport;
@override@JsonKey() final  bool canExportPartial;
@override@JsonKey() final  bool restartFromBeginning;
@override@JsonKey() final  bool restartRequiresSourceCheck;
 final  List<FileTransferSnapshot> _items;
@override@JsonKey() List<FileTransferSnapshot> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  FileTransferBatch? batch;

/// Create a copy of FileTransferSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileTransferSnapshotCopyWith<_FileTransferSnapshot> get copyWith => __$FileTransferSnapshotCopyWithImpl<_FileTransferSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FileTransferSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileTransferSnapshot&&(identical(other.id, id) || other.id == id)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.batchId, batchId) || other.batchId == batchId)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.name, name) || other.name == name)&&(identical(other.source, source) || other.source == source)&&(identical(other.destination, destination) || other.destination == destination)&&(identical(other.direction, direction) || other.direction == direction)&&(identical(other.destinationScope, destinationScope) || other.destinationScope == destinationScope)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&(identical(other.policy, policy) || other.policy == policy)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.itemIndex, itemIndex) || other.itemIndex == itemIndex)&&(identical(other.itemCount, itemCount) || other.itemCount == itemCount)&&(identical(other.transferred, transferred) || other.transferred == transferred)&&(identical(other.total, total) || other.total == total)&&(identical(other.completedBytes, completedBytes) || other.completedBytes == completedBytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.endedAt, endedAt) || other.endedAt == endedAt)&&(identical(other.deviceName, deviceName) || other.deviceName == deviceName)&&(identical(other.sourceLabel, sourceLabel) || other.sourceLabel == sourceLabel)&&(identical(other.destinationLabel, destinationLabel) || other.destinationLabel == destinationLabel)&&(identical(other.localPath, localPath) || other.localPath == localPath)&&(identical(other.partialLocalPath, partialLocalPath) || other.partialLocalPath == partialLocalPath)&&(identical(other.error, error) || other.error == error)&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode)&&(identical(other.exportReason, exportReason) || other.exportReason == exportReason)&&(identical(other.saveMode, saveMode) || other.saveMode == saveMode)&&(identical(other.cleanupPending, cleanupPending) || other.cleanupPending == cleanupPending)&&(identical(other.historyHidden, historyHidden) || other.historyHidden == historyHidden)&&(identical(other.partialDestinationPossible, partialDestinationPossible) || other.partialDestinationPossible == partialDestinationPossible)&&(identical(other.treeVerified, treeVerified) || other.treeVerified == treeVerified)&&(identical(other.treeComplete, treeComplete) || other.treeComplete == treeComplete)&&(identical(other.cacheEvicted, cacheEvicted) || other.cacheEvicted == cacheEvicted)&&(identical(other.canResume, canResume) || other.canResume == canResume)&&(identical(other.canRestart, canRestart) || other.canRestart == canRestart)&&(identical(other.canCancel, canCancel) || other.canCancel == canCancel)&&(identical(other.canExport, canExport) || other.canExport == canExport)&&(identical(other.canExportPartial, canExportPartial) || other.canExportPartial == canExportPartial)&&(identical(other.restartFromBeginning, restartFromBeginning) || other.restartFromBeginning == restartFromBeginning)&&(identical(other.restartRequiresSourceCheck, restartRequiresSourceCheck) || other.restartRequiresSourceCheck == restartRequiresSourceCheck)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.batch, batch) || other.batch == batch));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,deviceId,batchId,parentId,name,source,destination,direction,destinationScope,kind,status,policy,generation,itemIndex,itemCount,transferred,total,completedBytes,totalBytes,endedAt,deviceName,sourceLabel,destinationLabel,localPath,partialLocalPath,error,errorCode,exportReason,saveMode,cleanupPending,historyHidden,partialDestinationPossible,treeVerified,treeComplete,cacheEvicted,canResume,canRestart,canCancel,canExport,canExportPartial,restartFromBeginning,restartRequiresSourceCheck,const DeepCollectionEquality().hash(_items),batch]);
}

@override
String toString() {
    return 'FileTransferSnapshot(id: $id, deviceId: $deviceId, batchId: $batchId, parentId: $parentId, name: $name, source: $source, destination: $destination, direction: $direction, destinationScope: $destinationScope, kind: $kind, status: $status, policy: $policy, generation: $generation, itemIndex: $itemIndex, itemCount: $itemCount, transferred: $transferred, total: $total, completedBytes: $completedBytes, totalBytes: $totalBytes, endedAt: $endedAt, deviceName: $deviceName, sourceLabel: $sourceLabel, destinationLabel: $destinationLabel, localPath: $localPath, partialLocalPath: $partialLocalPath, error: $error, errorCode: $errorCode, exportReason: $exportReason, saveMode: $saveMode, cleanupPending: $cleanupPending, historyHidden: $historyHidden, partialDestinationPossible: $partialDestinationPossible, treeVerified: $treeVerified, treeComplete: $treeComplete, cacheEvicted: $cacheEvicted, canResume: $canResume, canRestart: $canRestart, canCancel: $canCancel, canExport: $canExport, canExportPartial: $canExportPartial, restartFromBeginning: $restartFromBeginning, restartRequiresSourceCheck: $restartRequiresSourceCheck, items: $items, batch: $batch)';
}


}

/// @nodoc
abstract mixin class _$FileTransferSnapshotCopyWith<$Res> implements $FileTransferSnapshotCopyWith<$Res> {
  factory _$FileTransferSnapshotCopyWith(_FileTransferSnapshot value, $Res Function(_FileTransferSnapshot) _then) = __$FileTransferSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String id, String deviceId, String? batchId, String? parentId, String name, String source, String destination, FileTransferDirection direction, FileTransferDestination destinationScope, FileTransferKind kind, FileTransferStatus status, FileTransferConflict policy, int generation, int itemIndex, int itemCount, int transferred, int? total, int? completedBytes, int? totalBytes, int? endedAt, String? deviceName, String? sourceLabel, String? destinationLabel, String? localPath, String? partialLocalPath, String? error, String? errorCode, String? exportReason, String? saveMode, bool cleanupPending, bool historyHidden, bool partialDestinationPossible, bool treeVerified, bool treeComplete, bool cacheEvicted, bool canResume, bool canRestart, bool canCancel, bool canExport, bool canExportPartial, bool restartFromBeginning, bool restartRequiresSourceCheck, List<FileTransferSnapshot> items, FileTransferBatch? batch
});


@override $FileTransferBatchCopyWith<$Res>? get batch;

}
/// @nodoc
class __$FileTransferSnapshotCopyWithImpl<$Res>
    implements _$FileTransferSnapshotCopyWith<$Res> {
  __$FileTransferSnapshotCopyWithImpl(this._self, this._then);

  final _FileTransferSnapshot _self;
  final $Res Function(_FileTransferSnapshot) _then;

/// Create a copy of FileTransferSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? deviceId = null,Object? batchId = freezed,Object? parentId = freezed,Object? name = null,Object? source = null,Object? destination = null,Object? direction = null,Object? destinationScope = null,Object? kind = null,Object? status = null,Object? policy = null,Object? generation = null,Object? itemIndex = null,Object? itemCount = null,Object? transferred = null,Object? total = freezed,Object? completedBytes = freezed,Object? totalBytes = freezed,Object? endedAt = freezed,Object? deviceName = freezed,Object? sourceLabel = freezed,Object? destinationLabel = freezed,Object? localPath = freezed,Object? partialLocalPath = freezed,Object? error = freezed,Object? errorCode = freezed,Object? exportReason = freezed,Object? saveMode = freezed,Object? cleanupPending = null,Object? historyHidden = null,Object? partialDestinationPossible = null,Object? treeVerified = null,Object? treeComplete = null,Object? cacheEvicted = null,Object? canResume = null,Object? canRestart = null,Object? canCancel = null,Object? canExport = null,Object? canExportPartial = null,Object? restartFromBeginning = null,Object? restartRequiresSourceCheck = null,Object? items = null,Object? batch = freezed,}) {
  return _then(_FileTransferSnapshot(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,batchId: freezed == batchId ? _self.batchId : batchId // ignore: cast_nullable_to_non_nullable
as String?,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,destination: null == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as FileTransferDirection,destinationScope: null == destinationScope ? _self.destinationScope : destinationScope // ignore: cast_nullable_to_non_nullable
as FileTransferDestination,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as FileTransferKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as FileTransferStatus,policy: null == policy ? _self.policy : policy // ignore: cast_nullable_to_non_nullable
as FileTransferConflict,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,itemIndex: null == itemIndex ? _self.itemIndex : itemIndex // ignore: cast_nullable_to_non_nullable
as int,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,transferred: null == transferred ? _self.transferred : transferred // ignore: cast_nullable_to_non_nullable
as int,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int?,completedBytes: freezed == completedBytes ? _self.completedBytes : completedBytes // ignore: cast_nullable_to_non_nullable
as int?,totalBytes: freezed == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int?,endedAt: freezed == endedAt ? _self.endedAt : endedAt // ignore: cast_nullable_to_non_nullable
as int?,deviceName: freezed == deviceName ? _self.deviceName : deviceName // ignore: cast_nullable_to_non_nullable
as String?,sourceLabel: freezed == sourceLabel ? _self.sourceLabel : sourceLabel // ignore: cast_nullable_to_non_nullable
as String?,destinationLabel: freezed == destinationLabel ? _self.destinationLabel : destinationLabel // ignore: cast_nullable_to_non_nullable
as String?,localPath: freezed == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String?,partialLocalPath: freezed == partialLocalPath ? _self.partialLocalPath : partialLocalPath // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,exportReason: freezed == exportReason ? _self.exportReason : exportReason // ignore: cast_nullable_to_non_nullable
as String?,saveMode: freezed == saveMode ? _self.saveMode : saveMode // ignore: cast_nullable_to_non_nullable
as String?,cleanupPending: null == cleanupPending ? _self.cleanupPending : cleanupPending // ignore: cast_nullable_to_non_nullable
as bool,historyHidden: null == historyHidden ? _self.historyHidden : historyHidden // ignore: cast_nullable_to_non_nullable
as bool,partialDestinationPossible: null == partialDestinationPossible ? _self.partialDestinationPossible : partialDestinationPossible // ignore: cast_nullable_to_non_nullable
as bool,treeVerified: null == treeVerified ? _self.treeVerified : treeVerified // ignore: cast_nullable_to_non_nullable
as bool,treeComplete: null == treeComplete ? _self.treeComplete : treeComplete // ignore: cast_nullable_to_non_nullable
as bool,cacheEvicted: null == cacheEvicted ? _self.cacheEvicted : cacheEvicted // ignore: cast_nullable_to_non_nullable
as bool,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,canRestart: null == canRestart ? _self.canRestart : canRestart // ignore: cast_nullable_to_non_nullable
as bool,canCancel: null == canCancel ? _self.canCancel : canCancel // ignore: cast_nullable_to_non_nullable
as bool,canExport: null == canExport ? _self.canExport : canExport // ignore: cast_nullable_to_non_nullable
as bool,canExportPartial: null == canExportPartial ? _self.canExportPartial : canExportPartial // ignore: cast_nullable_to_non_nullable
as bool,restartFromBeginning: null == restartFromBeginning ? _self.restartFromBeginning : restartFromBeginning // ignore: cast_nullable_to_non_nullable
as bool,restartRequiresSourceCheck: null == restartRequiresSourceCheck ? _self.restartRequiresSourceCheck : restartRequiresSourceCheck // ignore: cast_nullable_to_non_nullable
as bool,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<FileTransferSnapshot>,batch: freezed == batch ? _self.batch : batch // ignore: cast_nullable_to_non_nullable
as FileTransferBatch?,
  ));
}

/// Create a copy of FileTransferSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FileTransferBatchCopyWith<$Res>? get batch {
    if (_self.batch == null) {
    return null;
  }

  return $FileTransferBatchCopyWith<$Res>(_self.batch!, (value) {
    return _then(_self.copyWith(batch: value));
  });
}
}


/// @nodoc
mixin _$FileTransferBatch {

 String get batchId; String get deviceId; FileTransferDirection get direction; FileTransferDestination get destinationScope; FileTransferStatus get status; int get itemCount; int get fileCount; int get directoryCount; int get completed; int get failed; int get cancelled; int get skipped; int get interrupted; int get transferred; int get total; bool get canCancel; int get selectedRootCount; bool get canResume; bool get canRestart; bool get selectionSnapshot;
/// Create a copy of FileTransferBatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileTransferBatchCopyWith<FileTransferBatch> get copyWith => _$FileTransferBatchCopyWithImpl<FileTransferBatch>(this as FileTransferBatch, _$identity);

  /// Serializes this FileTransferBatch to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FileTransferBatch;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileTransferBatch&&(identical(other.batchId, _this.batchId) || other.batchId == _this.batchId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.direction, _this.direction) || other.direction == _this.direction)&&(identical(other.destinationScope, _this.destinationScope) || other.destinationScope == _this.destinationScope)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.itemCount, _this.itemCount) || other.itemCount == _this.itemCount)&&(identical(other.fileCount, _this.fileCount) || other.fileCount == _this.fileCount)&&(identical(other.directoryCount, _this.directoryCount) || other.directoryCount == _this.directoryCount)&&(identical(other.completed, _this.completed) || other.completed == _this.completed)&&(identical(other.failed, _this.failed) || other.failed == _this.failed)&&(identical(other.cancelled, _this.cancelled) || other.cancelled == _this.cancelled)&&(identical(other.skipped, _this.skipped) || other.skipped == _this.skipped)&&(identical(other.interrupted, _this.interrupted) || other.interrupted == _this.interrupted)&&(identical(other.transferred, _this.transferred) || other.transferred == _this.transferred)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.canCancel, _this.canCancel) || other.canCancel == _this.canCancel)&&(identical(other.selectedRootCount, _this.selectedRootCount) || other.selectedRootCount == _this.selectedRootCount)&&(identical(other.canResume, _this.canResume) || other.canResume == _this.canResume)&&(identical(other.canRestart, _this.canRestart) || other.canRestart == _this.canRestart)&&(identical(other.selectionSnapshot, _this.selectionSnapshot) || other.selectionSnapshot == _this.selectionSnapshot));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FileTransferBatch;
  return Object.hashAll([runtimeType,_this.batchId,_this.deviceId,_this.direction,_this.destinationScope,_this.status,_this.itemCount,_this.fileCount,_this.directoryCount,_this.completed,_this.failed,_this.cancelled,_this.skipped,_this.interrupted,_this.transferred,_this.total,_this.canCancel,_this.selectedRootCount,_this.canResume,_this.canRestart,_this.selectionSnapshot]);
}

@override
String toString() {
  final _this = this as FileTransferBatch;
  return 'FileTransferBatch(batchId: ${_this.batchId}, deviceId: ${_this.deviceId}, direction: ${_this.direction}, destinationScope: ${_this.destinationScope}, status: ${_this.status}, itemCount: ${_this.itemCount}, fileCount: ${_this.fileCount}, directoryCount: ${_this.directoryCount}, completed: ${_this.completed}, failed: ${_this.failed}, cancelled: ${_this.cancelled}, skipped: ${_this.skipped}, interrupted: ${_this.interrupted}, transferred: ${_this.transferred}, total: ${_this.total}, canCancel: ${_this.canCancel}, selectedRootCount: ${_this.selectedRootCount}, canResume: ${_this.canResume}, canRestart: ${_this.canRestart}, selectionSnapshot: ${_this.selectionSnapshot})';
}


}

/// @nodoc
abstract mixin class $FileTransferBatchCopyWith<$Res>  {
  factory $FileTransferBatchCopyWith(FileTransferBatch value, $Res Function(FileTransferBatch) _then) = _$FileTransferBatchCopyWithImpl;
@useResult
$Res call({
 String batchId, String deviceId, FileTransferDirection direction, FileTransferDestination destinationScope, FileTransferStatus status, int itemCount, int fileCount, int directoryCount, int completed, int failed, int cancelled, int skipped, int interrupted, int transferred, int total, bool canCancel, int selectedRootCount, bool canResume, bool canRestart, bool selectionSnapshot
});




}
/// @nodoc
class _$FileTransferBatchCopyWithImpl<$Res>
    implements $FileTransferBatchCopyWith<$Res> {
  _$FileTransferBatchCopyWithImpl(this._self, this._then);

  final FileTransferBatch _self;
  final $Res Function(FileTransferBatch) _then;

/// Create a copy of FileTransferBatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? batchId = null,Object? deviceId = null,Object? direction = null,Object? destinationScope = null,Object? status = null,Object? itemCount = null,Object? fileCount = null,Object? directoryCount = null,Object? completed = null,Object? failed = null,Object? cancelled = null,Object? skipped = null,Object? interrupted = null,Object? transferred = null,Object? total = null,Object? canCancel = null,Object? selectedRootCount = null,Object? canResume = null,Object? canRestart = null,Object? selectionSnapshot = null,}) {
  return _then(FileTransferBatch(
batchId: null == batchId ? _self.batchId : batchId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as FileTransferDirection,destinationScope: null == destinationScope ? _self.destinationScope : destinationScope // ignore: cast_nullable_to_non_nullable
as FileTransferDestination,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as FileTransferStatus,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,fileCount: null == fileCount ? _self.fileCount : fileCount // ignore: cast_nullable_to_non_nullable
as int,directoryCount: null == directoryCount ? _self.directoryCount : directoryCount // ignore: cast_nullable_to_non_nullable
as int,completed: null == completed ? _self.completed : completed // ignore: cast_nullable_to_non_nullable
as int,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as int,cancelled: null == cancelled ? _self.cancelled : cancelled // ignore: cast_nullable_to_non_nullable
as int,skipped: null == skipped ? _self.skipped : skipped // ignore: cast_nullable_to_non_nullable
as int,interrupted: null == interrupted ? _self.interrupted : interrupted // ignore: cast_nullable_to_non_nullable
as int,transferred: null == transferred ? _self.transferred : transferred // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,canCancel: null == canCancel ? _self.canCancel : canCancel // ignore: cast_nullable_to_non_nullable
as bool,selectedRootCount: null == selectedRootCount ? _self.selectedRootCount : selectedRootCount // ignore: cast_nullable_to_non_nullable
as int,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,canRestart: null == canRestart ? _self.canRestart : canRestart // ignore: cast_nullable_to_non_nullable
as bool,selectionSnapshot: null == selectionSnapshot ? _self.selectionSnapshot : selectionSnapshot // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [FileTransferBatch].
extension FileTransferBatchPatterns on FileTransferBatch {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileTransferBatch value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileTransferBatch() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileTransferBatch value)  $default,){
final _that = this;
switch (_that) {
case _FileTransferBatch():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileTransferBatch value)?  $default,){
final _that = this;
switch (_that) {
case _FileTransferBatch() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String batchId,  String deviceId,  FileTransferDirection direction,  FileTransferDestination destinationScope,  FileTransferStatus status,  int itemCount,  int fileCount,  int directoryCount,  int completed,  int failed,  int cancelled,  int skipped,  int interrupted,  int transferred,  int total,  bool canCancel,  int selectedRootCount,  bool canResume,  bool canRestart,  bool selectionSnapshot)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileTransferBatch() when $default != null:
return $default(_that.batchId,_that.deviceId,_that.direction,_that.destinationScope,_that.status,_that.itemCount,_that.fileCount,_that.directoryCount,_that.completed,_that.failed,_that.cancelled,_that.skipped,_that.interrupted,_that.transferred,_that.total,_that.canCancel,_that.selectedRootCount,_that.canResume,_that.canRestart,_that.selectionSnapshot);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String batchId,  String deviceId,  FileTransferDirection direction,  FileTransferDestination destinationScope,  FileTransferStatus status,  int itemCount,  int fileCount,  int directoryCount,  int completed,  int failed,  int cancelled,  int skipped,  int interrupted,  int transferred,  int total,  bool canCancel,  int selectedRootCount,  bool canResume,  bool canRestart,  bool selectionSnapshot)  $default,) {final _that = this;
switch (_that) {
case _FileTransferBatch():
return $default(_that.batchId,_that.deviceId,_that.direction,_that.destinationScope,_that.status,_that.itemCount,_that.fileCount,_that.directoryCount,_that.completed,_that.failed,_that.cancelled,_that.skipped,_that.interrupted,_that.transferred,_that.total,_that.canCancel,_that.selectedRootCount,_that.canResume,_that.canRestart,_that.selectionSnapshot);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String batchId,  String deviceId,  FileTransferDirection direction,  FileTransferDestination destinationScope,  FileTransferStatus status,  int itemCount,  int fileCount,  int directoryCount,  int completed,  int failed,  int cancelled,  int skipped,  int interrupted,  int transferred,  int total,  bool canCancel,  int selectedRootCount,  bool canResume,  bool canRestart,  bool selectionSnapshot)?  $default,) {final _that = this;
switch (_that) {
case _FileTransferBatch() when $default != null:
return $default(_that.batchId,_that.deviceId,_that.direction,_that.destinationScope,_that.status,_that.itemCount,_that.fileCount,_that.directoryCount,_that.completed,_that.failed,_that.cancelled,_that.skipped,_that.interrupted,_that.transferred,_that.total,_that.canCancel,_that.selectedRootCount,_that.canResume,_that.canRestart,_that.selectionSnapshot);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FileTransferBatch implements FileTransferBatch {
  const _FileTransferBatch({required this.batchId, this.deviceId = '', this.direction = FileTransferDirection.pull, this.destinationScope = FileTransferDestination.localPath, this.status = FileTransferStatus.unknown, this.itemCount = 0, this.fileCount = 0, this.directoryCount = 0, this.completed = 0, this.failed = 0, this.cancelled = 0, this.skipped = 0, this.interrupted = 0, this.transferred = 0, this.total = 0, this.canCancel = false, this.selectedRootCount = 0, this.canResume = false, this.canRestart = false, this.selectionSnapshot = true});
  factory _FileTransferBatch.fromJson(Map<String, dynamic> json) => _$FileTransferBatchFromJson(json);

@override final  String batchId;
@override@JsonKey() final  String deviceId;
@override@JsonKey() final  FileTransferDirection direction;
@override@JsonKey() final  FileTransferDestination destinationScope;
@override@JsonKey() final  FileTransferStatus status;
@override@JsonKey() final  int itemCount;
@override@JsonKey() final  int fileCount;
@override@JsonKey() final  int directoryCount;
@override@JsonKey() final  int completed;
@override@JsonKey() final  int failed;
@override@JsonKey() final  int cancelled;
@override@JsonKey() final  int skipped;
@override@JsonKey() final  int interrupted;
@override@JsonKey() final  int transferred;
@override@JsonKey() final  int total;
@override@JsonKey() final  bool canCancel;
@override@JsonKey() final  int selectedRootCount;
@override@JsonKey() final  bool canResume;
@override@JsonKey() final  bool canRestart;
@override@JsonKey() final  bool selectionSnapshot;

/// Create a copy of FileTransferBatch
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileTransferBatchCopyWith<_FileTransferBatch> get copyWith => __$FileTransferBatchCopyWithImpl<_FileTransferBatch>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FileTransferBatchToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileTransferBatch&&(identical(other.batchId, batchId) || other.batchId == batchId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.direction, direction) || other.direction == direction)&&(identical(other.destinationScope, destinationScope) || other.destinationScope == destinationScope)&&(identical(other.status, status) || other.status == status)&&(identical(other.itemCount, itemCount) || other.itemCount == itemCount)&&(identical(other.fileCount, fileCount) || other.fileCount == fileCount)&&(identical(other.directoryCount, directoryCount) || other.directoryCount == directoryCount)&&(identical(other.completed, completed) || other.completed == completed)&&(identical(other.failed, failed) || other.failed == failed)&&(identical(other.cancelled, cancelled) || other.cancelled == cancelled)&&(identical(other.skipped, skipped) || other.skipped == skipped)&&(identical(other.interrupted, interrupted) || other.interrupted == interrupted)&&(identical(other.transferred, transferred) || other.transferred == transferred)&&(identical(other.total, total) || other.total == total)&&(identical(other.canCancel, canCancel) || other.canCancel == canCancel)&&(identical(other.selectedRootCount, selectedRootCount) || other.selectedRootCount == selectedRootCount)&&(identical(other.canResume, canResume) || other.canResume == canResume)&&(identical(other.canRestart, canRestart) || other.canRestart == canRestart)&&(identical(other.selectionSnapshot, selectionSnapshot) || other.selectionSnapshot == selectionSnapshot));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,batchId,deviceId,direction,destinationScope,status,itemCount,fileCount,directoryCount,completed,failed,cancelled,skipped,interrupted,transferred,total,canCancel,selectedRootCount,canResume,canRestart,selectionSnapshot]);
}

@override
String toString() {
    return 'FileTransferBatch(batchId: $batchId, deviceId: $deviceId, direction: $direction, destinationScope: $destinationScope, status: $status, itemCount: $itemCount, fileCount: $fileCount, directoryCount: $directoryCount, completed: $completed, failed: $failed, cancelled: $cancelled, skipped: $skipped, interrupted: $interrupted, transferred: $transferred, total: $total, canCancel: $canCancel, selectedRootCount: $selectedRootCount, canResume: $canResume, canRestart: $canRestart, selectionSnapshot: $selectionSnapshot)';
}


}

/// @nodoc
abstract mixin class _$FileTransferBatchCopyWith<$Res> implements $FileTransferBatchCopyWith<$Res> {
  factory _$FileTransferBatchCopyWith(_FileTransferBatch value, $Res Function(_FileTransferBatch) _then) = __$FileTransferBatchCopyWithImpl;
@override @useResult
$Res call({
 String batchId, String deviceId, FileTransferDirection direction, FileTransferDestination destinationScope, FileTransferStatus status, int itemCount, int fileCount, int directoryCount, int completed, int failed, int cancelled, int skipped, int interrupted, int transferred, int total, bool canCancel, int selectedRootCount, bool canResume, bool canRestart, bool selectionSnapshot
});




}
/// @nodoc
class __$FileTransferBatchCopyWithImpl<$Res>
    implements _$FileTransferBatchCopyWith<$Res> {
  __$FileTransferBatchCopyWithImpl(this._self, this._then);

  final _FileTransferBatch _self;
  final $Res Function(_FileTransferBatch) _then;

/// Create a copy of FileTransferBatch
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? batchId = null,Object? deviceId = null,Object? direction = null,Object? destinationScope = null,Object? status = null,Object? itemCount = null,Object? fileCount = null,Object? directoryCount = null,Object? completed = null,Object? failed = null,Object? cancelled = null,Object? skipped = null,Object? interrupted = null,Object? transferred = null,Object? total = null,Object? canCancel = null,Object? selectedRootCount = null,Object? canResume = null,Object? canRestart = null,Object? selectionSnapshot = null,}) {
  return _then(_FileTransferBatch(
batchId: null == batchId ? _self.batchId : batchId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as FileTransferDirection,destinationScope: null == destinationScope ? _self.destinationScope : destinationScope // ignore: cast_nullable_to_non_nullable
as FileTransferDestination,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as FileTransferStatus,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,fileCount: null == fileCount ? _self.fileCount : fileCount // ignore: cast_nullable_to_non_nullable
as int,directoryCount: null == directoryCount ? _self.directoryCount : directoryCount // ignore: cast_nullable_to_non_nullable
as int,completed: null == completed ? _self.completed : completed // ignore: cast_nullable_to_non_nullable
as int,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as int,cancelled: null == cancelled ? _self.cancelled : cancelled // ignore: cast_nullable_to_non_nullable
as int,skipped: null == skipped ? _self.skipped : skipped // ignore: cast_nullable_to_non_nullable
as int,interrupted: null == interrupted ? _self.interrupted : interrupted // ignore: cast_nullable_to_non_nullable
as int,transferred: null == transferred ? _self.transferred : transferred // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,canCancel: null == canCancel ? _self.canCancel : canCancel // ignore: cast_nullable_to_non_nullable
as bool,selectedRootCount: null == selectedRootCount ? _self.selectedRootCount : selectedRootCount // ignore: cast_nullable_to_non_nullable
as int,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,canRestart: null == canRestart ? _self.canRestart : canRestart // ignore: cast_nullable_to_non_nullable
as bool,selectionSnapshot: null == selectionSnapshot ? _self.selectionSnapshot : selectionSnapshot // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$FileTransferCollection {

 List<FileTransferSnapshot> get transfers; List<FileTransferBatch> get batches;
/// Create a copy of FileTransferCollection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileTransferCollectionCopyWith<FileTransferCollection> get copyWith => _$FileTransferCollectionCopyWithImpl<FileTransferCollection>(this as FileTransferCollection, _$identity);

  /// Serializes this FileTransferCollection to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FileTransferCollection;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileTransferCollection&&const DeepCollectionEquality().equals(other.transfers, _this.transfers)&&const DeepCollectionEquality().equals(other.batches, _this.batches));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FileTransferCollection;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.transfers),const DeepCollectionEquality().hash(_this.batches));
}

@override
String toString() {
  final _this = this as FileTransferCollection;
  return 'FileTransferCollection(transfers: ${_this.transfers}, batches: ${_this.batches})';
}


}

/// @nodoc
abstract mixin class $FileTransferCollectionCopyWith<$Res>  {
  factory $FileTransferCollectionCopyWith(FileTransferCollection value, $Res Function(FileTransferCollection) _then) = _$FileTransferCollectionCopyWithImpl;
@useResult
$Res call({
 List<FileTransferSnapshot> transfers, List<FileTransferBatch> batches
});




}
/// @nodoc
class _$FileTransferCollectionCopyWithImpl<$Res>
    implements $FileTransferCollectionCopyWith<$Res> {
  _$FileTransferCollectionCopyWithImpl(this._self, this._then);

  final FileTransferCollection _self;
  final $Res Function(FileTransferCollection) _then;

/// Create a copy of FileTransferCollection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? transfers = null,Object? batches = null,}) {
  return _then(FileTransferCollection(
transfers: null == transfers ? _self.transfers : transfers // ignore: cast_nullable_to_non_nullable
as List<FileTransferSnapshot>,batches: null == batches ? _self.batches : batches // ignore: cast_nullable_to_non_nullable
as List<FileTransferBatch>,
  ));
}

}


/// Adds pattern-matching-related methods to [FileTransferCollection].
extension FileTransferCollectionPatterns on FileTransferCollection {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileTransferCollection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileTransferCollection() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileTransferCollection value)  $default,){
final _that = this;
switch (_that) {
case _FileTransferCollection():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileTransferCollection value)?  $default,){
final _that = this;
switch (_that) {
case _FileTransferCollection() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<FileTransferSnapshot> transfers,  List<FileTransferBatch> batches)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileTransferCollection() when $default != null:
return $default(_that.transfers,_that.batches);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<FileTransferSnapshot> transfers,  List<FileTransferBatch> batches)  $default,) {final _that = this;
switch (_that) {
case _FileTransferCollection():
return $default(_that.transfers,_that.batches);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<FileTransferSnapshot> transfers,  List<FileTransferBatch> batches)?  $default,) {final _that = this;
switch (_that) {
case _FileTransferCollection() when $default != null:
return $default(_that.transfers,_that.batches);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true)
class _FileTransferCollection implements FileTransferCollection {
  const _FileTransferCollection({ List<FileTransferSnapshot> transfers = const [],  List<FileTransferBatch> batches = const []}): _transfers = transfers,_batches = batches;
  factory _FileTransferCollection.fromJson(Map<String, dynamic> json) => _$FileTransferCollectionFromJson(json);

 final  List<FileTransferSnapshot> _transfers;
@override@JsonKey() List<FileTransferSnapshot> get transfers {
  if (_transfers is EqualUnmodifiableListView) return _transfers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_transfers);
}

 final  List<FileTransferBatch> _batches;
@override@JsonKey() List<FileTransferBatch> get batches {
  if (_batches is EqualUnmodifiableListView) return _batches;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_batches);
}


/// Create a copy of FileTransferCollection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileTransferCollectionCopyWith<_FileTransferCollection> get copyWith => __$FileTransferCollectionCopyWithImpl<_FileTransferCollection>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FileTransferCollectionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileTransferCollection&&const DeepCollectionEquality().equals(other.transfers, _transfers)&&const DeepCollectionEquality().equals(other.batches, _batches));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_transfers),const DeepCollectionEquality().hash(_batches));
}

@override
String toString() {
    return 'FileTransferCollection(transfers: $transfers, batches: $batches)';
}


}

/// @nodoc
abstract mixin class _$FileTransferCollectionCopyWith<$Res> implements $FileTransferCollectionCopyWith<$Res> {
  factory _$FileTransferCollectionCopyWith(_FileTransferCollection value, $Res Function(_FileTransferCollection) _then) = __$FileTransferCollectionCopyWithImpl;
@override @useResult
$Res call({
 List<FileTransferSnapshot> transfers, List<FileTransferBatch> batches
});




}
/// @nodoc
class __$FileTransferCollectionCopyWithImpl<$Res>
    implements _$FileTransferCollectionCopyWith<$Res> {
  __$FileTransferCollectionCopyWithImpl(this._self, this._then);

  final _FileTransferCollection _self;
  final $Res Function(_FileTransferCollection) _then;

/// Create a copy of FileTransferCollection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transfers = null,Object? batches = null,}) {
  return _then(_FileTransferCollection(
transfers: null == transfers ? _self._transfers : transfers // ignore: cast_nullable_to_non_nullable
as List<FileTransferSnapshot>,batches: null == batches ? _self._batches : batches // ignore: cast_nullable_to_non_nullable
as List<FileTransferBatch>,
  ));
}


}

// dart format on
