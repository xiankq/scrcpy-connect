// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thumbnail_job.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThumbnailJob {


/// Create a copy of ThumbnailJob
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThumbnailJobCopyWith<ThumbnailJob> get copyWith => _$ThumbnailJobCopyWithImpl<ThumbnailJob>(this as ThumbnailJob, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThumbnailJob;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThumbnailJob&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.ownerOperationId, _this.ownerOperationId) || other.ownerOperationId == _this.ownerOperationId)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.maxSize, _this.maxSize) || other.maxSize == _this.maxSize)&&(identical(other.allowStart, _this.allowStart) || other.allowStart == _this.allowStart));
}


@override
int get hashCode {
  final _this = this as ThumbnailJob;
  return Object.hash(runtimeType,_this.deviceId,_this.operationId,_this.ownerOperationId,_this.path,_this.kind,_this.maxSize,_this.allowStart);
}

@override
String toString() {
  final _this = this as ThumbnailJob;
  return 'ThumbnailJob(deviceId: ${_this.deviceId}, operationId: ${_this.operationId}, ownerOperationId: ${_this.ownerOperationId}, path: ${_this.path}, kind: ${_this.kind}, maxSize: ${_this.maxSize}, allowStart: ${_this.allowStart})';
}


}

/// @nodoc
abstract mixin class $ThumbnailJobCopyWith<$Res>  {
  factory $ThumbnailJobCopyWith(ThumbnailJob value, $Res Function(ThumbnailJob) _then) = _$ThumbnailJobCopyWithImpl;
@useResult
$Res call({
 String deviceId, String operationId, String ownerOperationId, String path, ThumbnailKind kind, int maxSize, bool allowStart
});




}
/// @nodoc
class _$ThumbnailJobCopyWithImpl<$Res>
    implements $ThumbnailJobCopyWith<$Res> {
  _$ThumbnailJobCopyWithImpl(this._self, this._then);

  final ThumbnailJob _self;
  final $Res Function(ThumbnailJob) _then;

/// Create a copy of ThumbnailJob
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? operationId = null,Object? ownerOperationId = null,Object? path = null,Object? kind = null,Object? maxSize = null,Object? allowStart = null,}) {
  return _then(ThumbnailJob(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,ownerOperationId: null == ownerOperationId ? _self.ownerOperationId : ownerOperationId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ThumbnailKind,maxSize: null == maxSize ? _self.maxSize : maxSize // ignore: cast_nullable_to_non_nullable
as int,allowStart: null == allowStart ? _self.allowStart : allowStart // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ThumbnailJob].
extension ThumbnailJobPatterns on ThumbnailJob {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

// dart format on
