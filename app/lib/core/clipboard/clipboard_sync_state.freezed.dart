// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'clipboard_sync_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ClipboardSyncState {

 ClipboardSyncStatus get status; String? get error; int get readCount; int get writeCount; int get sendCount;
/// Create a copy of ClipboardSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClipboardSyncStateCopyWith<ClipboardSyncState> get copyWith => _$ClipboardSyncStateCopyWithImpl<ClipboardSyncState>(this as ClipboardSyncState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ClipboardSyncState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClipboardSyncState&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.readCount, _this.readCount) || other.readCount == _this.readCount)&&(identical(other.writeCount, _this.writeCount) || other.writeCount == _this.writeCount)&&(identical(other.sendCount, _this.sendCount) || other.sendCount == _this.sendCount));
}


@override
int get hashCode {
  final _this = this as ClipboardSyncState;
  return Object.hash(runtimeType,_this.status,_this.error,_this.readCount,_this.writeCount,_this.sendCount);
}

@override
String toString() {
  final _this = this as ClipboardSyncState;
  return 'ClipboardSyncState(status: ${_this.status}, error: ${_this.error}, readCount: ${_this.readCount}, writeCount: ${_this.writeCount}, sendCount: ${_this.sendCount})';
}


}

/// @nodoc
abstract mixin class $ClipboardSyncStateCopyWith<$Res>  {
  factory $ClipboardSyncStateCopyWith(ClipboardSyncState value, $Res Function(ClipboardSyncState) _then) = _$ClipboardSyncStateCopyWithImpl;
@useResult
$Res call({
 ClipboardSyncStatus status, String? error, int readCount, int writeCount, int sendCount
});




}
/// @nodoc
class _$ClipboardSyncStateCopyWithImpl<$Res>
    implements $ClipboardSyncStateCopyWith<$Res> {
  _$ClipboardSyncStateCopyWithImpl(this._self, this._then);

  final ClipboardSyncState _self;
  final $Res Function(ClipboardSyncState) _then;

/// Create a copy of ClipboardSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? error = freezed,Object? readCount = null,Object? writeCount = null,Object? sendCount = null,}) {
  return _then(ClipboardSyncState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ClipboardSyncStatus,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,readCount: null == readCount ? _self.readCount : readCount // ignore: cast_nullable_to_non_nullable
as int,writeCount: null == writeCount ? _self.writeCount : writeCount // ignore: cast_nullable_to_non_nullable
as int,sendCount: null == sendCount ? _self.sendCount : sendCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ClipboardSyncState].
extension ClipboardSyncStatePatterns on ClipboardSyncState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ClipboardSyncState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ClipboardSyncState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ClipboardSyncState value)  $default,){
final _that = this;
switch (_that) {
case _ClipboardSyncState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ClipboardSyncState value)?  $default,){
final _that = this;
switch (_that) {
case _ClipboardSyncState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ClipboardSyncStatus status,  String? error,  int readCount,  int writeCount,  int sendCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ClipboardSyncState() when $default != null:
return $default(_that.status,_that.error,_that.readCount,_that.writeCount,_that.sendCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ClipboardSyncStatus status,  String? error,  int readCount,  int writeCount,  int sendCount)  $default,) {final _that = this;
switch (_that) {
case _ClipboardSyncState():
return $default(_that.status,_that.error,_that.readCount,_that.writeCount,_that.sendCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ClipboardSyncStatus status,  String? error,  int readCount,  int writeCount,  int sendCount)?  $default,) {final _that = this;
switch (_that) {
case _ClipboardSyncState() when $default != null:
return $default(_that.status,_that.error,_that.readCount,_that.writeCount,_that.sendCount);case _:
  return null;

}
}

}

/// @nodoc


class _ClipboardSyncState implements ClipboardSyncState {
  const _ClipboardSyncState({this.status = ClipboardSyncStatus.disabled, this.error, this.readCount = 0, this.writeCount = 0, this.sendCount = 0});
  

@override@JsonKey() final  ClipboardSyncStatus status;
@override final  String? error;
@override@JsonKey() final  int readCount;
@override@JsonKey() final  int writeCount;
@override@JsonKey() final  int sendCount;

/// Create a copy of ClipboardSyncState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ClipboardSyncStateCopyWith<_ClipboardSyncState> get copyWith => __$ClipboardSyncStateCopyWithImpl<_ClipboardSyncState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ClipboardSyncState&&(identical(other.status, status) || other.status == status)&&(identical(other.error, error) || other.error == error)&&(identical(other.readCount, readCount) || other.readCount == readCount)&&(identical(other.writeCount, writeCount) || other.writeCount == writeCount)&&(identical(other.sendCount, sendCount) || other.sendCount == sendCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status,error,readCount,writeCount,sendCount);
}

@override
String toString() {
    return 'ClipboardSyncState(status: $status, error: $error, readCount: $readCount, writeCount: $writeCount, sendCount: $sendCount)';
}


}

/// @nodoc
abstract mixin class _$ClipboardSyncStateCopyWith<$Res> implements $ClipboardSyncStateCopyWith<$Res> {
  factory _$ClipboardSyncStateCopyWith(_ClipboardSyncState value, $Res Function(_ClipboardSyncState) _then) = __$ClipboardSyncStateCopyWithImpl;
@override @useResult
$Res call({
 ClipboardSyncStatus status, String? error, int readCount, int writeCount, int sendCount
});




}
/// @nodoc
class __$ClipboardSyncStateCopyWithImpl<$Res>
    implements _$ClipboardSyncStateCopyWith<$Res> {
  __$ClipboardSyncStateCopyWithImpl(this._self, this._then);

  final _ClipboardSyncState _self;
  final $Res Function(_ClipboardSyncState) _then;

/// Create a copy of ClipboardSyncState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? error = freezed,Object? readCount = null,Object? writeCount = null,Object? sendCount = null,}) {
  return _then(_ClipboardSyncState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ClipboardSyncStatus,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,readCount: null == readCount ? _self.readCount : readCount // ignore: cast_nullable_to_non_nullable
as int,writeCount: null == writeCount ? _self.writeCount : writeCount // ignore: cast_nullable_to_non_nullable
as int,sendCount: null == sendCount ? _self.sendCount : sendCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
