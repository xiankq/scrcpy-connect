// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'file_transfer_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FileTransferRecord {

 String get id; String get deviceId; String get batchId; FileTransferDirection get direction; String get source; String get destination; String get name; String? get shareId; String? get parentId; FileStamp? get sourceStamp;@JsonKey(unknownEnumValue: FileTransferKind.unsupported) FileTransferKind get kind;@JsonKey(unknownEnumValue: FileTransferStatus.unknown) FileTransferStatus get status; FileTransferConflict get policy; FileTransferDestination get destinationScope; int get createdAt; int? get endedAt; int get generation; int get itemIndex; int get itemCount; int get transferred; int? get total; String? get temporaryPath; String? get saveMode; String? get errorCode; String? get error; bool get treeVerified; bool get treeComplete; bool get partialDestinationPossible; bool get cleanupPending; bool get historyHidden; String? get cleanupScopeId; String? get cleanupScopeKey;
/// Create a copy of FileTransferRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileTransferRecordCopyWith<FileTransferRecord> get copyWith => _$FileTransferRecordCopyWithImpl<FileTransferRecord>(this as FileTransferRecord, _$identity);

  /// Serializes this FileTransferRecord to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FileTransferRecord;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileTransferRecord&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.batchId, _this.batchId) || other.batchId == _this.batchId)&&(identical(other.direction, _this.direction) || other.direction == _this.direction)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.destination, _this.destination) || other.destination == _this.destination)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.shareId, _this.shareId) || other.shareId == _this.shareId)&&(identical(other.parentId, _this.parentId) || other.parentId == _this.parentId)&&(identical(other.sourceStamp, _this.sourceStamp) || other.sourceStamp == _this.sourceStamp)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.policy, _this.policy) || other.policy == _this.policy)&&(identical(other.destinationScope, _this.destinationScope) || other.destinationScope == _this.destinationScope)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.endedAt, _this.endedAt) || other.endedAt == _this.endedAt)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.itemIndex, _this.itemIndex) || other.itemIndex == _this.itemIndex)&&(identical(other.itemCount, _this.itemCount) || other.itemCount == _this.itemCount)&&(identical(other.transferred, _this.transferred) || other.transferred == _this.transferred)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.temporaryPath, _this.temporaryPath) || other.temporaryPath == _this.temporaryPath)&&(identical(other.saveMode, _this.saveMode) || other.saveMode == _this.saveMode)&&(identical(other.errorCode, _this.errorCode) || other.errorCode == _this.errorCode)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.treeVerified, _this.treeVerified) || other.treeVerified == _this.treeVerified)&&(identical(other.treeComplete, _this.treeComplete) || other.treeComplete == _this.treeComplete)&&(identical(other.partialDestinationPossible, _this.partialDestinationPossible) || other.partialDestinationPossible == _this.partialDestinationPossible)&&(identical(other.cleanupPending, _this.cleanupPending) || other.cleanupPending == _this.cleanupPending)&&(identical(other.historyHidden, _this.historyHidden) || other.historyHidden == _this.historyHidden)&&(identical(other.cleanupScopeId, _this.cleanupScopeId) || other.cleanupScopeId == _this.cleanupScopeId)&&(identical(other.cleanupScopeKey, _this.cleanupScopeKey) || other.cleanupScopeKey == _this.cleanupScopeKey));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FileTransferRecord;
  return Object.hashAll([runtimeType,_this.id,_this.deviceId,_this.batchId,_this.direction,_this.source,_this.destination,_this.name,_this.shareId,_this.parentId,_this.sourceStamp,_this.kind,_this.status,_this.policy,_this.destinationScope,_this.createdAt,_this.endedAt,_this.generation,_this.itemIndex,_this.itemCount,_this.transferred,_this.total,_this.temporaryPath,_this.saveMode,_this.errorCode,_this.error,_this.treeVerified,_this.treeComplete,_this.partialDestinationPossible,_this.cleanupPending,_this.historyHidden,_this.cleanupScopeId,_this.cleanupScopeKey]);
}

@override
String toString() {
  final _this = this as FileTransferRecord;
  return 'FileTransferRecord(id: ${_this.id}, deviceId: ${_this.deviceId}, batchId: ${_this.batchId}, direction: ${_this.direction}, source: ${_this.source}, destination: ${_this.destination}, name: ${_this.name}, shareId: ${_this.shareId}, parentId: ${_this.parentId}, sourceStamp: ${_this.sourceStamp}, kind: ${_this.kind}, status: ${_this.status}, policy: ${_this.policy}, destinationScope: ${_this.destinationScope}, createdAt: ${_this.createdAt}, endedAt: ${_this.endedAt}, generation: ${_this.generation}, itemIndex: ${_this.itemIndex}, itemCount: ${_this.itemCount}, transferred: ${_this.transferred}, total: ${_this.total}, temporaryPath: ${_this.temporaryPath}, saveMode: ${_this.saveMode}, errorCode: ${_this.errorCode}, error: ${_this.error}, treeVerified: ${_this.treeVerified}, treeComplete: ${_this.treeComplete}, partialDestinationPossible: ${_this.partialDestinationPossible}, cleanupPending: ${_this.cleanupPending}, historyHidden: ${_this.historyHidden}, cleanupScopeId: ${_this.cleanupScopeId}, cleanupScopeKey: ${_this.cleanupScopeKey})';
}


}

/// @nodoc
abstract mixin class $FileTransferRecordCopyWith<$Res>  {
  factory $FileTransferRecordCopyWith(FileTransferRecord value, $Res Function(FileTransferRecord) _then) = _$FileTransferRecordCopyWithImpl;
@useResult
$Res call({
 String id, String deviceId, String batchId, FileTransferDirection direction, String source, String destination, String name, String? shareId, String? parentId, FileStamp? sourceStamp,@JsonKey(unknownEnumValue: FileTransferKind.unsupported) FileTransferKind kind,@JsonKey(unknownEnumValue: FileTransferStatus.unknown) FileTransferStatus status, FileTransferConflict policy, FileTransferDestination destinationScope, int createdAt, int? endedAt, int generation, int itemIndex, int itemCount, int transferred, int? total, String? temporaryPath, String? saveMode, String? errorCode, String? error, bool treeVerified, bool treeComplete, bool partialDestinationPossible, bool cleanupPending, bool historyHidden, String? cleanupScopeId, String? cleanupScopeKey
});




}
/// @nodoc
class _$FileTransferRecordCopyWithImpl<$Res>
    implements $FileTransferRecordCopyWith<$Res> {
  _$FileTransferRecordCopyWithImpl(this._self, this._then);

  final FileTransferRecord _self;
  final $Res Function(FileTransferRecord) _then;

/// Create a copy of FileTransferRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? deviceId = null,Object? batchId = null,Object? direction = null,Object? source = null,Object? destination = null,Object? name = null,Object? shareId = freezed,Object? parentId = freezed,Object? sourceStamp = freezed,Object? kind = null,Object? status = null,Object? policy = null,Object? destinationScope = null,Object? createdAt = null,Object? endedAt = freezed,Object? generation = null,Object? itemIndex = null,Object? itemCount = null,Object? transferred = null,Object? total = freezed,Object? temporaryPath = freezed,Object? saveMode = freezed,Object? errorCode = freezed,Object? error = freezed,Object? treeVerified = null,Object? treeComplete = null,Object? partialDestinationPossible = null,Object? cleanupPending = null,Object? historyHidden = null,Object? cleanupScopeId = freezed,Object? cleanupScopeKey = freezed,}) {
  return _then(FileTransferRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,batchId: null == batchId ? _self.batchId : batchId // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as FileTransferDirection,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,destination: null == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,shareId: freezed == shareId ? _self.shareId : shareId // ignore: cast_nullable_to_non_nullable
as String?,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,sourceStamp: freezed == sourceStamp ? _self.sourceStamp : sourceStamp // ignore: cast_nullable_to_non_nullable
as FileStamp?,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as FileTransferKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as FileTransferStatus,policy: null == policy ? _self.policy : policy // ignore: cast_nullable_to_non_nullable
as FileTransferConflict,destinationScope: null == destinationScope ? _self.destinationScope : destinationScope // ignore: cast_nullable_to_non_nullable
as FileTransferDestination,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,endedAt: freezed == endedAt ? _self.endedAt : endedAt // ignore: cast_nullable_to_non_nullable
as int?,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,itemIndex: null == itemIndex ? _self.itemIndex : itemIndex // ignore: cast_nullable_to_non_nullable
as int,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,transferred: null == transferred ? _self.transferred : transferred // ignore: cast_nullable_to_non_nullable
as int,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int?,temporaryPath: freezed == temporaryPath ? _self.temporaryPath : temporaryPath // ignore: cast_nullable_to_non_nullable
as String?,saveMode: freezed == saveMode ? _self.saveMode : saveMode // ignore: cast_nullable_to_non_nullable
as String?,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,treeVerified: null == treeVerified ? _self.treeVerified : treeVerified // ignore: cast_nullable_to_non_nullable
as bool,treeComplete: null == treeComplete ? _self.treeComplete : treeComplete // ignore: cast_nullable_to_non_nullable
as bool,partialDestinationPossible: null == partialDestinationPossible ? _self.partialDestinationPossible : partialDestinationPossible // ignore: cast_nullable_to_non_nullable
as bool,cleanupPending: null == cleanupPending ? _self.cleanupPending : cleanupPending // ignore: cast_nullable_to_non_nullable
as bool,historyHidden: null == historyHidden ? _self.historyHidden : historyHidden // ignore: cast_nullable_to_non_nullable
as bool,cleanupScopeId: freezed == cleanupScopeId ? _self.cleanupScopeId : cleanupScopeId // ignore: cast_nullable_to_non_nullable
as String?,cleanupScopeKey: freezed == cleanupScopeKey ? _self.cleanupScopeKey : cleanupScopeKey // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [FileTransferRecord].
extension FileTransferRecordPatterns on FileTransferRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileTransferRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileTransferRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileTransferRecord value)  $default,){
final _that = this;
switch (_that) {
case _FileTransferRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileTransferRecord value)?  $default,){
final _that = this;
switch (_that) {
case _FileTransferRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String deviceId,  String batchId,  FileTransferDirection direction,  String source,  String destination,  String name,  String? shareId,  String? parentId,  FileStamp? sourceStamp, @JsonKey(unknownEnumValue: FileTransferKind.unsupported)  FileTransferKind kind, @JsonKey(unknownEnumValue: FileTransferStatus.unknown)  FileTransferStatus status,  FileTransferConflict policy,  FileTransferDestination destinationScope,  int createdAt,  int? endedAt,  int generation,  int itemIndex,  int itemCount,  int transferred,  int? total,  String? temporaryPath,  String? saveMode,  String? errorCode,  String? error,  bool treeVerified,  bool treeComplete,  bool partialDestinationPossible,  bool cleanupPending,  bool historyHidden,  String? cleanupScopeId,  String? cleanupScopeKey)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileTransferRecord() when $default != null:
return $default(_that.id,_that.deviceId,_that.batchId,_that.direction,_that.source,_that.destination,_that.name,_that.shareId,_that.parentId,_that.sourceStamp,_that.kind,_that.status,_that.policy,_that.destinationScope,_that.createdAt,_that.endedAt,_that.generation,_that.itemIndex,_that.itemCount,_that.transferred,_that.total,_that.temporaryPath,_that.saveMode,_that.errorCode,_that.error,_that.treeVerified,_that.treeComplete,_that.partialDestinationPossible,_that.cleanupPending,_that.historyHidden,_that.cleanupScopeId,_that.cleanupScopeKey);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String deviceId,  String batchId,  FileTransferDirection direction,  String source,  String destination,  String name,  String? shareId,  String? parentId,  FileStamp? sourceStamp, @JsonKey(unknownEnumValue: FileTransferKind.unsupported)  FileTransferKind kind, @JsonKey(unknownEnumValue: FileTransferStatus.unknown)  FileTransferStatus status,  FileTransferConflict policy,  FileTransferDestination destinationScope,  int createdAt,  int? endedAt,  int generation,  int itemIndex,  int itemCount,  int transferred,  int? total,  String? temporaryPath,  String? saveMode,  String? errorCode,  String? error,  bool treeVerified,  bool treeComplete,  bool partialDestinationPossible,  bool cleanupPending,  bool historyHidden,  String? cleanupScopeId,  String? cleanupScopeKey)  $default,) {final _that = this;
switch (_that) {
case _FileTransferRecord():
return $default(_that.id,_that.deviceId,_that.batchId,_that.direction,_that.source,_that.destination,_that.name,_that.shareId,_that.parentId,_that.sourceStamp,_that.kind,_that.status,_that.policy,_that.destinationScope,_that.createdAt,_that.endedAt,_that.generation,_that.itemIndex,_that.itemCount,_that.transferred,_that.total,_that.temporaryPath,_that.saveMode,_that.errorCode,_that.error,_that.treeVerified,_that.treeComplete,_that.partialDestinationPossible,_that.cleanupPending,_that.historyHidden,_that.cleanupScopeId,_that.cleanupScopeKey);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String deviceId,  String batchId,  FileTransferDirection direction,  String source,  String destination,  String name,  String? shareId,  String? parentId,  FileStamp? sourceStamp, @JsonKey(unknownEnumValue: FileTransferKind.unsupported)  FileTransferKind kind, @JsonKey(unknownEnumValue: FileTransferStatus.unknown)  FileTransferStatus status,  FileTransferConflict policy,  FileTransferDestination destinationScope,  int createdAt,  int? endedAt,  int generation,  int itemIndex,  int itemCount,  int transferred,  int? total,  String? temporaryPath,  String? saveMode,  String? errorCode,  String? error,  bool treeVerified,  bool treeComplete,  bool partialDestinationPossible,  bool cleanupPending,  bool historyHidden,  String? cleanupScopeId,  String? cleanupScopeKey)?  $default,) {final _that = this;
switch (_that) {
case _FileTransferRecord() when $default != null:
return $default(_that.id,_that.deviceId,_that.batchId,_that.direction,_that.source,_that.destination,_that.name,_that.shareId,_that.parentId,_that.sourceStamp,_that.kind,_that.status,_that.policy,_that.destinationScope,_that.createdAt,_that.endedAt,_that.generation,_that.itemIndex,_that.itemCount,_that.transferred,_that.total,_that.temporaryPath,_that.saveMode,_that.errorCode,_that.error,_that.treeVerified,_that.treeComplete,_that.partialDestinationPossible,_that.cleanupPending,_that.historyHidden,_that.cleanupScopeId,_that.cleanupScopeKey);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class _FileTransferRecord extends FileTransferRecord {
  const _FileTransferRecord({required this.id, required this.deviceId, required this.batchId, required this.direction, required this.source, required this.destination, this.name = '文件传输', this.shareId, this.parentId, this.sourceStamp, @JsonKey(unknownEnumValue: FileTransferKind.unsupported) this.kind = FileTransferKind.file, @JsonKey(unknownEnumValue: FileTransferStatus.unknown) this.status = FileTransferStatus.unknown, this.policy = FileTransferConflict.ask, this.destinationScope = FileTransferDestination.localPath, this.createdAt = 0, this.endedAt, this.generation = 0, this.itemIndex = 0, this.itemCount = 1, this.transferred = 0, this.total, this.temporaryPath, this.saveMode, this.errorCode, this.error, this.treeVerified = false, this.treeComplete = false, this.partialDestinationPossible = false, this.cleanupPending = false, this.historyHidden = false, this.cleanupScopeId, this.cleanupScopeKey}): super._();
  factory _FileTransferRecord.fromJson(Map<String, dynamic> json) => _$FileTransferRecordFromJson(json);

@override final  String id;
@override final  String deviceId;
@override final  String batchId;
@override final  FileTransferDirection direction;
@override final  String source;
@override final  String destination;
@override@JsonKey() final  String name;
@override final  String? shareId;
@override final  String? parentId;
@override final  FileStamp? sourceStamp;
@override@JsonKey(unknownEnumValue: FileTransferKind.unsupported) final  FileTransferKind kind;
@override@JsonKey(unknownEnumValue: FileTransferStatus.unknown) final  FileTransferStatus status;
@override@JsonKey() final  FileTransferConflict policy;
@override@JsonKey() final  FileTransferDestination destinationScope;
@override@JsonKey() final  int createdAt;
@override final  int? endedAt;
@override@JsonKey() final  int generation;
@override@JsonKey() final  int itemIndex;
@override@JsonKey() final  int itemCount;
@override@JsonKey() final  int transferred;
@override final  int? total;
@override final  String? temporaryPath;
@override final  String? saveMode;
@override final  String? errorCode;
@override final  String? error;
@override@JsonKey() final  bool treeVerified;
@override@JsonKey() final  bool treeComplete;
@override@JsonKey() final  bool partialDestinationPossible;
@override@JsonKey() final  bool cleanupPending;
@override@JsonKey() final  bool historyHidden;
@override final  String? cleanupScopeId;
@override final  String? cleanupScopeKey;

/// Create a copy of FileTransferRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileTransferRecordCopyWith<_FileTransferRecord> get copyWith => __$FileTransferRecordCopyWithImpl<_FileTransferRecord>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FileTransferRecordToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileTransferRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.batchId, batchId) || other.batchId == batchId)&&(identical(other.direction, direction) || other.direction == direction)&&(identical(other.source, source) || other.source == source)&&(identical(other.destination, destination) || other.destination == destination)&&(identical(other.name, name) || other.name == name)&&(identical(other.shareId, shareId) || other.shareId == shareId)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.sourceStamp, sourceStamp) || other.sourceStamp == sourceStamp)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&(identical(other.policy, policy) || other.policy == policy)&&(identical(other.destinationScope, destinationScope) || other.destinationScope == destinationScope)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.endedAt, endedAt) || other.endedAt == endedAt)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.itemIndex, itemIndex) || other.itemIndex == itemIndex)&&(identical(other.itemCount, itemCount) || other.itemCount == itemCount)&&(identical(other.transferred, transferred) || other.transferred == transferred)&&(identical(other.total, total) || other.total == total)&&(identical(other.temporaryPath, temporaryPath) || other.temporaryPath == temporaryPath)&&(identical(other.saveMode, saveMode) || other.saveMode == saveMode)&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode)&&(identical(other.error, error) || other.error == error)&&(identical(other.treeVerified, treeVerified) || other.treeVerified == treeVerified)&&(identical(other.treeComplete, treeComplete) || other.treeComplete == treeComplete)&&(identical(other.partialDestinationPossible, partialDestinationPossible) || other.partialDestinationPossible == partialDestinationPossible)&&(identical(other.cleanupPending, cleanupPending) || other.cleanupPending == cleanupPending)&&(identical(other.historyHidden, historyHidden) || other.historyHidden == historyHidden)&&(identical(other.cleanupScopeId, cleanupScopeId) || other.cleanupScopeId == cleanupScopeId)&&(identical(other.cleanupScopeKey, cleanupScopeKey) || other.cleanupScopeKey == cleanupScopeKey));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,deviceId,batchId,direction,source,destination,name,shareId,parentId,sourceStamp,kind,status,policy,destinationScope,createdAt,endedAt,generation,itemIndex,itemCount,transferred,total,temporaryPath,saveMode,errorCode,error,treeVerified,treeComplete,partialDestinationPossible,cleanupPending,historyHidden,cleanupScopeId,cleanupScopeKey]);
}

@override
String toString() {
    return 'FileTransferRecord(id: $id, deviceId: $deviceId, batchId: $batchId, direction: $direction, source: $source, destination: $destination, name: $name, shareId: $shareId, parentId: $parentId, sourceStamp: $sourceStamp, kind: $kind, status: $status, policy: $policy, destinationScope: $destinationScope, createdAt: $createdAt, endedAt: $endedAt, generation: $generation, itemIndex: $itemIndex, itemCount: $itemCount, transferred: $transferred, total: $total, temporaryPath: $temporaryPath, saveMode: $saveMode, errorCode: $errorCode, error: $error, treeVerified: $treeVerified, treeComplete: $treeComplete, partialDestinationPossible: $partialDestinationPossible, cleanupPending: $cleanupPending, historyHidden: $historyHidden, cleanupScopeId: $cleanupScopeId, cleanupScopeKey: $cleanupScopeKey)';
}


}

/// @nodoc
abstract mixin class _$FileTransferRecordCopyWith<$Res> implements $FileTransferRecordCopyWith<$Res> {
  factory _$FileTransferRecordCopyWith(_FileTransferRecord value, $Res Function(_FileTransferRecord) _then) = __$FileTransferRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, String deviceId, String batchId, FileTransferDirection direction, String source, String destination, String name, String? shareId, String? parentId, FileStamp? sourceStamp,@JsonKey(unknownEnumValue: FileTransferKind.unsupported) FileTransferKind kind,@JsonKey(unknownEnumValue: FileTransferStatus.unknown) FileTransferStatus status, FileTransferConflict policy, FileTransferDestination destinationScope, int createdAt, int? endedAt, int generation, int itemIndex, int itemCount, int transferred, int? total, String? temporaryPath, String? saveMode, String? errorCode, String? error, bool treeVerified, bool treeComplete, bool partialDestinationPossible, bool cleanupPending, bool historyHidden, String? cleanupScopeId, String? cleanupScopeKey
});




}
/// @nodoc
class __$FileTransferRecordCopyWithImpl<$Res>
    implements _$FileTransferRecordCopyWith<$Res> {
  __$FileTransferRecordCopyWithImpl(this._self, this._then);

  final _FileTransferRecord _self;
  final $Res Function(_FileTransferRecord) _then;

/// Create a copy of FileTransferRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? deviceId = null,Object? batchId = null,Object? direction = null,Object? source = null,Object? destination = null,Object? name = null,Object? shareId = freezed,Object? parentId = freezed,Object? sourceStamp = freezed,Object? kind = null,Object? status = null,Object? policy = null,Object? destinationScope = null,Object? createdAt = null,Object? endedAt = freezed,Object? generation = null,Object? itemIndex = null,Object? itemCount = null,Object? transferred = null,Object? total = freezed,Object? temporaryPath = freezed,Object? saveMode = freezed,Object? errorCode = freezed,Object? error = freezed,Object? treeVerified = null,Object? treeComplete = null,Object? partialDestinationPossible = null,Object? cleanupPending = null,Object? historyHidden = null,Object? cleanupScopeId = freezed,Object? cleanupScopeKey = freezed,}) {
  return _then(_FileTransferRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,batchId: null == batchId ? _self.batchId : batchId // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as FileTransferDirection,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,destination: null == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,shareId: freezed == shareId ? _self.shareId : shareId // ignore: cast_nullable_to_non_nullable
as String?,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,sourceStamp: freezed == sourceStamp ? _self.sourceStamp : sourceStamp // ignore: cast_nullable_to_non_nullable
as FileStamp?,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as FileTransferKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as FileTransferStatus,policy: null == policy ? _self.policy : policy // ignore: cast_nullable_to_non_nullable
as FileTransferConflict,destinationScope: null == destinationScope ? _self.destinationScope : destinationScope // ignore: cast_nullable_to_non_nullable
as FileTransferDestination,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,endedAt: freezed == endedAt ? _self.endedAt : endedAt // ignore: cast_nullable_to_non_nullable
as int?,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,itemIndex: null == itemIndex ? _self.itemIndex : itemIndex // ignore: cast_nullable_to_non_nullable
as int,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,transferred: null == transferred ? _self.transferred : transferred // ignore: cast_nullable_to_non_nullable
as int,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int?,temporaryPath: freezed == temporaryPath ? _self.temporaryPath : temporaryPath // ignore: cast_nullable_to_non_nullable
as String?,saveMode: freezed == saveMode ? _self.saveMode : saveMode // ignore: cast_nullable_to_non_nullable
as String?,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,treeVerified: null == treeVerified ? _self.treeVerified : treeVerified // ignore: cast_nullable_to_non_nullable
as bool,treeComplete: null == treeComplete ? _self.treeComplete : treeComplete // ignore: cast_nullable_to_non_nullable
as bool,partialDestinationPossible: null == partialDestinationPossible ? _self.partialDestinationPossible : partialDestinationPossible // ignore: cast_nullable_to_non_nullable
as bool,cleanupPending: null == cleanupPending ? _self.cleanupPending : cleanupPending // ignore: cast_nullable_to_non_nullable
as bool,historyHidden: null == historyHidden ? _self.historyHidden : historyHidden // ignore: cast_nullable_to_non_nullable
as bool,cleanupScopeId: freezed == cleanupScopeId ? _self.cleanupScopeId : cleanupScopeId // ignore: cast_nullable_to_non_nullable
as String?,cleanupScopeKey: freezed == cleanupScopeKey ? _self.cleanupScopeKey : cleanupScopeKey // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
