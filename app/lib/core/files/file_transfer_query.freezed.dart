// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'file_transfer_query.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FileTransferQueryState<T> {

 T? get data; bool get loading; Object? get error;
/// Create a copy of FileTransferQueryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileTransferQueryStateCopyWith<T, FileTransferQueryState<T>> get copyWith => _$FileTransferQueryStateCopyWithImpl<T, FileTransferQueryState<T>>(this as FileTransferQueryState<T>, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FileTransferQueryState<T>;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileTransferQueryState<T>&&const DeepCollectionEquality().equals(other.data, _this.data)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&const DeepCollectionEquality().equals(other.error, _this.error));
}


@override
int get hashCode {
  final _this = this as FileTransferQueryState<T>;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.data),_this.loading,const DeepCollectionEquality().hash(_this.error));
}

@override
String toString() {
  final _this = this as FileTransferQueryState<T>;
  return 'FileTransferQueryState<$T>(data: ${_this.data}, loading: ${_this.loading}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $FileTransferQueryStateCopyWith<T,$Res>  {
  factory $FileTransferQueryStateCopyWith(FileTransferQueryState<T> value, $Res Function(FileTransferQueryState<T>) _then) = _$FileTransferQueryStateCopyWithImpl;
@useResult
$Res call({
 T? data, bool loading, Object? error
});




}
/// @nodoc
class _$FileTransferQueryStateCopyWithImpl<T,$Res>
    implements $FileTransferQueryStateCopyWith<T, $Res> {
  _$FileTransferQueryStateCopyWithImpl(this._self, this._then);

  final FileTransferQueryState<T> _self;
  final $Res Function(FileTransferQueryState<T>) _then;

/// Create a copy of FileTransferQueryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? data = freezed,Object? loading = null,Object? error = freezed,}) {
  return _then(FileTransferQueryState(
data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as T?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error ,
  ));
}

}


/// Adds pattern-matching-related methods to [FileTransferQueryState].
extension FileTransferQueryStatePatterns<T> on FileTransferQueryState<T> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileTransferQueryState<T> value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileTransferQueryState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileTransferQueryState<T> value)  $default,){
final _that = this;
switch (_that) {
case _FileTransferQueryState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileTransferQueryState<T> value)?  $default,){
final _that = this;
switch (_that) {
case _FileTransferQueryState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( T? data,  bool loading,  Object? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileTransferQueryState() when $default != null:
return $default(_that.data,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( T? data,  bool loading,  Object? error)  $default,) {final _that = this;
switch (_that) {
case _FileTransferQueryState():
return $default(_that.data,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( T? data,  bool loading,  Object? error)?  $default,) {final _that = this;
switch (_that) {
case _FileTransferQueryState() when $default != null:
return $default(_that.data,_that.loading,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _FileTransferQueryState<T> extends FileTransferQueryState<T> {
  const _FileTransferQueryState({this.data, this.loading = true, this.error}): super._();
  

@override final  T? data;
@override@JsonKey() final  bool loading;
@override final  Object? error;

/// Create a copy of FileTransferQueryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileTransferQueryStateCopyWith<T, _FileTransferQueryState<T>> get copyWith => __$FileTransferQueryStateCopyWithImpl<T, _FileTransferQueryState<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileTransferQueryState<T>&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.loading, loading) || other.loading == loading)&&const DeepCollectionEquality().equals(other.error, error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(data),loading,const DeepCollectionEquality().hash(error));
}

@override
String toString() {
    return 'FileTransferQueryState<$T>(data: $data, loading: $loading, error: $error)';
}


}

/// @nodoc
abstract mixin class _$FileTransferQueryStateCopyWith<T,$Res> implements $FileTransferQueryStateCopyWith<T, $Res> {
  factory _$FileTransferQueryStateCopyWith(_FileTransferQueryState<T> value, $Res Function(_FileTransferQueryState<T>) _then) = __$FileTransferQueryStateCopyWithImpl;
@override @useResult
$Res call({
 T? data, bool loading, Object? error
});




}
/// @nodoc
class __$FileTransferQueryStateCopyWithImpl<T,$Res>
    implements _$FileTransferQueryStateCopyWith<T, $Res> {
  __$FileTransferQueryStateCopyWithImpl(this._self, this._then);

  final _FileTransferQueryState<T> _self;
  final $Res Function(_FileTransferQueryState<T>) _then;

/// Create a copy of FileTransferQueryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? data = freezed,Object? loading = null,Object? error = freezed,}) {
  return _then(_FileTransferQueryState<T>(
data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as T?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error ,
  ));
}


}

// dart format on
