// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'file_transfer_submission.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FileTransferTarget {

 String get id;
/// Create a copy of FileTransferTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileTransferTargetCopyWith<FileTransferTarget> get copyWith => _$FileTransferTargetCopyWithImpl<FileTransferTarget>(this as FileTransferTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FileTransferTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileTransferTarget&&(identical(other.id, _this.id) || other.id == _this.id));
}


@override
int get hashCode {
  final _this = this as FileTransferTarget;
  return Object.hash(runtimeType,_this.id);
}

@override
String toString() {
  final _this = this as FileTransferTarget;
  return 'FileTransferTarget(id: ${_this.id})';
}


}

/// @nodoc
abstract mixin class $FileTransferTargetCopyWith<$Res>  {
  factory $FileTransferTargetCopyWith(FileTransferTarget value, $Res Function(FileTransferTarget) _then) = _$FileTransferTargetCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$FileTransferTargetCopyWithImpl<$Res>
    implements $FileTransferTargetCopyWith<$Res> {
  _$FileTransferTargetCopyWithImpl(this._self, this._then);

  final FileTransferTarget _self;
  final $Res Function(FileTransferTarget) _then;

/// Create a copy of FileTransferTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FileTransferTarget].
extension FileTransferTargetPatterns on FileTransferTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FileTransferTaskTarget value)?  task,TResult Function( FileTransferBatchTarget value)?  batch,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FileTransferTaskTarget() when task != null:
return task(_that);case FileTransferBatchTarget() when batch != null:
return batch(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FileTransferTaskTarget value)  task,required TResult Function( FileTransferBatchTarget value)  batch,}){
final _that = this;
switch (_that) {
case FileTransferTaskTarget():
return task(_that);case FileTransferBatchTarget():
return batch(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FileTransferTaskTarget value)?  task,TResult? Function( FileTransferBatchTarget value)?  batch,}){
final _that = this;
switch (_that) {
case FileTransferTaskTarget() when task != null:
return task(_that);case FileTransferBatchTarget() when batch != null:
return batch(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id)?  task,TResult Function( String id)?  batch,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FileTransferTaskTarget() when task != null:
return task(_that.id);case FileTransferBatchTarget() when batch != null:
return batch(_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id)  task,required TResult Function( String id)  batch,}) {final _that = this;
switch (_that) {
case FileTransferTaskTarget():
return task(_that.id);case FileTransferBatchTarget():
return batch(_that.id);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id)?  task,TResult? Function( String id)?  batch,}) {final _that = this;
switch (_that) {
case FileTransferTaskTarget() when task != null:
return task(_that.id);case FileTransferBatchTarget() when batch != null:
return batch(_that.id);case _:
  return null;

}
}

}

/// @nodoc


class FileTransferTaskTarget implements FileTransferTarget {
  const FileTransferTaskTarget(this.id);
  

@override final  String id;

/// Create a copy of FileTransferTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileTransferTaskTargetCopyWith<FileTransferTaskTarget> get copyWith => _$FileTransferTaskTargetCopyWithImpl<FileTransferTaskTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FileTransferTaskTarget&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id);
}

@override
String toString() {
    return 'FileTransferTarget.task(id: $id)';
}


}

/// @nodoc
abstract mixin class $FileTransferTaskTargetCopyWith<$Res> implements $FileTransferTargetCopyWith<$Res> {
  factory $FileTransferTaskTargetCopyWith(FileTransferTaskTarget value, $Res Function(FileTransferTaskTarget) _then) = _$FileTransferTaskTargetCopyWithImpl;
@override @useResult
$Res call({
 String id
});




}
/// @nodoc
class _$FileTransferTaskTargetCopyWithImpl<$Res>
    implements $FileTransferTaskTargetCopyWith<$Res> {
  _$FileTransferTaskTargetCopyWithImpl(this._self, this._then);

  final FileTransferTaskTarget _self;
  final $Res Function(FileTransferTaskTarget) _then;

/// Create a copy of FileTransferTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(FileTransferTaskTarget(
null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FileTransferBatchTarget implements FileTransferTarget {
  const FileTransferBatchTarget(this.id);
  

@override final  String id;

/// Create a copy of FileTransferTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileTransferBatchTargetCopyWith<FileTransferBatchTarget> get copyWith => _$FileTransferBatchTargetCopyWithImpl<FileTransferBatchTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FileTransferBatchTarget&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id);
}

@override
String toString() {
    return 'FileTransferTarget.batch(id: $id)';
}


}

/// @nodoc
abstract mixin class $FileTransferBatchTargetCopyWith<$Res> implements $FileTransferTargetCopyWith<$Res> {
  factory $FileTransferBatchTargetCopyWith(FileTransferBatchTarget value, $Res Function(FileTransferBatchTarget) _then) = _$FileTransferBatchTargetCopyWithImpl;
@override @useResult
$Res call({
 String id
});




}
/// @nodoc
class _$FileTransferBatchTargetCopyWithImpl<$Res>
    implements $FileTransferBatchTargetCopyWith<$Res> {
  _$FileTransferBatchTargetCopyWithImpl(this._self, this._then);

  final FileTransferBatchTarget _self;
  final $Res Function(FileTransferBatchTarget) _then;

/// Create a copy of FileTransferTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(FileTransferBatchTarget(
null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$FileTransferSubmission {

 String get batchId; String? get transferId; int get itemCount; FileTransferAdmission get status; bool get reusedTransfer; bool get sourceLeaseReconciliationPending;
/// Create a copy of FileTransferSubmission
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileTransferSubmissionCopyWith<FileTransferSubmission> get copyWith => _$FileTransferSubmissionCopyWithImpl<FileTransferSubmission>(this as FileTransferSubmission, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FileTransferSubmission;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileTransferSubmission&&(identical(other.batchId, _this.batchId) || other.batchId == _this.batchId)&&(identical(other.transferId, _this.transferId) || other.transferId == _this.transferId)&&(identical(other.itemCount, _this.itemCount) || other.itemCount == _this.itemCount)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.reusedTransfer, _this.reusedTransfer) || other.reusedTransfer == _this.reusedTransfer)&&(identical(other.sourceLeaseReconciliationPending, _this.sourceLeaseReconciliationPending) || other.sourceLeaseReconciliationPending == _this.sourceLeaseReconciliationPending));
}


@override
int get hashCode {
  final _this = this as FileTransferSubmission;
  return Object.hash(runtimeType,_this.batchId,_this.transferId,_this.itemCount,_this.status,_this.reusedTransfer,_this.sourceLeaseReconciliationPending);
}

@override
String toString() {
  final _this = this as FileTransferSubmission;
  return 'FileTransferSubmission(batchId: ${_this.batchId}, transferId: ${_this.transferId}, itemCount: ${_this.itemCount}, status: ${_this.status}, reusedTransfer: ${_this.reusedTransfer}, sourceLeaseReconciliationPending: ${_this.sourceLeaseReconciliationPending})';
}


}

/// @nodoc
abstract mixin class $FileTransferSubmissionCopyWith<$Res>  {
  factory $FileTransferSubmissionCopyWith(FileTransferSubmission value, $Res Function(FileTransferSubmission) _then) = _$FileTransferSubmissionCopyWithImpl;
@useResult
$Res call({
 String batchId, String? transferId, int itemCount, FileTransferAdmission status, bool reusedTransfer, bool sourceLeaseReconciliationPending
});




}
/// @nodoc
class _$FileTransferSubmissionCopyWithImpl<$Res>
    implements $FileTransferSubmissionCopyWith<$Res> {
  _$FileTransferSubmissionCopyWithImpl(this._self, this._then);

  final FileTransferSubmission _self;
  final $Res Function(FileTransferSubmission) _then;

/// Create a copy of FileTransferSubmission
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? batchId = null,Object? transferId = freezed,Object? itemCount = null,Object? status = null,Object? reusedTransfer = null,Object? sourceLeaseReconciliationPending = null,}) {
  return _then(FileTransferSubmission(
batchId: null == batchId ? _self.batchId : batchId // ignore: cast_nullable_to_non_nullable
as String,transferId: freezed == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String?,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as FileTransferAdmission,reusedTransfer: null == reusedTransfer ? _self.reusedTransfer : reusedTransfer // ignore: cast_nullable_to_non_nullable
as bool,sourceLeaseReconciliationPending: null == sourceLeaseReconciliationPending ? _self.sourceLeaseReconciliationPending : sourceLeaseReconciliationPending // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [FileTransferSubmission].
extension FileTransferSubmissionPatterns on FileTransferSubmission {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileTransferSubmission value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileTransferSubmission() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileTransferSubmission value)  $default,){
final _that = this;
switch (_that) {
case _FileTransferSubmission():
return $default(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileTransferSubmission value)?  $default,){
final _that = this;
switch (_that) {
case _FileTransferSubmission() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String batchId,  String? transferId,  int itemCount,  FileTransferAdmission status,  bool reusedTransfer,  bool sourceLeaseReconciliationPending)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileTransferSubmission() when $default != null:
return $default(_that.batchId,_that.transferId,_that.itemCount,_that.status,_that.reusedTransfer,_that.sourceLeaseReconciliationPending);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String batchId,  String? transferId,  int itemCount,  FileTransferAdmission status,  bool reusedTransfer,  bool sourceLeaseReconciliationPending)  $default,) {final _that = this;
switch (_that) {
case _FileTransferSubmission():
return $default(_that.batchId,_that.transferId,_that.itemCount,_that.status,_that.reusedTransfer,_that.sourceLeaseReconciliationPending);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String batchId,  String? transferId,  int itemCount,  FileTransferAdmission status,  bool reusedTransfer,  bool sourceLeaseReconciliationPending)?  $default,) {final _that = this;
switch (_that) {
case _FileTransferSubmission() when $default != null:
return $default(_that.batchId,_that.transferId,_that.itemCount,_that.status,_that.reusedTransfer,_that.sourceLeaseReconciliationPending);case _:
  return null;

}
}

}

/// @nodoc


class _FileTransferSubmission implements FileTransferSubmission {
  const _FileTransferSubmission({required this.batchId, required this.transferId, required this.itemCount, required this.status, this.reusedTransfer = false, this.sourceLeaseReconciliationPending = false});
  

@override final  String batchId;
@override final  String? transferId;
@override final  int itemCount;
@override final  FileTransferAdmission status;
@override@JsonKey() final  bool reusedTransfer;
@override@JsonKey() final  bool sourceLeaseReconciliationPending;

/// Create a copy of FileTransferSubmission
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileTransferSubmissionCopyWith<_FileTransferSubmission> get copyWith => __$FileTransferSubmissionCopyWithImpl<_FileTransferSubmission>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileTransferSubmission&&(identical(other.batchId, batchId) || other.batchId == batchId)&&(identical(other.transferId, transferId) || other.transferId == transferId)&&(identical(other.itemCount, itemCount) || other.itemCount == itemCount)&&(identical(other.status, status) || other.status == status)&&(identical(other.reusedTransfer, reusedTransfer) || other.reusedTransfer == reusedTransfer)&&(identical(other.sourceLeaseReconciliationPending, sourceLeaseReconciliationPending) || other.sourceLeaseReconciliationPending == sourceLeaseReconciliationPending));
}


@override
int get hashCode {
    return Object.hash(runtimeType,batchId,transferId,itemCount,status,reusedTransfer,sourceLeaseReconciliationPending);
}

@override
String toString() {
    return 'FileTransferSubmission(batchId: $batchId, transferId: $transferId, itemCount: $itemCount, status: $status, reusedTransfer: $reusedTransfer, sourceLeaseReconciliationPending: $sourceLeaseReconciliationPending)';
}


}

/// @nodoc
abstract mixin class _$FileTransferSubmissionCopyWith<$Res> implements $FileTransferSubmissionCopyWith<$Res> {
  factory _$FileTransferSubmissionCopyWith(_FileTransferSubmission value, $Res Function(_FileTransferSubmission) _then) = __$FileTransferSubmissionCopyWithImpl;
@override @useResult
$Res call({
 String batchId, String? transferId, int itemCount, FileTransferAdmission status, bool reusedTransfer, bool sourceLeaseReconciliationPending
});




}
/// @nodoc
class __$FileTransferSubmissionCopyWithImpl<$Res>
    implements _$FileTransferSubmissionCopyWith<$Res> {
  __$FileTransferSubmissionCopyWithImpl(this._self, this._then);

  final _FileTransferSubmission _self;
  final $Res Function(_FileTransferSubmission) _then;

/// Create a copy of FileTransferSubmission
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? batchId = null,Object? transferId = freezed,Object? itemCount = null,Object? status = null,Object? reusedTransfer = null,Object? sourceLeaseReconciliationPending = null,}) {
  return _then(_FileTransferSubmission(
batchId: null == batchId ? _self.batchId : batchId // ignore: cast_nullable_to_non_nullable
as String,transferId: freezed == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String?,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as FileTransferAdmission,reusedTransfer: null == reusedTransfer ? _self.reusedTransfer : reusedTransfer // ignore: cast_nullable_to_non_nullable
as bool,sourceLeaseReconciliationPending: null == sourceLeaseReconciliationPending ? _self.sourceLeaseReconciliationPending : sourceLeaseReconciliationPending // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
