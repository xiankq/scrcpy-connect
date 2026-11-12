// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'file_search_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FileSearchState {

 FileSearchSnapshot? get result; String? get error; bool get starting; bool get stopping;
/// Create a copy of FileSearchState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileSearchStateCopyWith<FileSearchState> get copyWith => _$FileSearchStateCopyWithImpl<FileSearchState>(this as FileSearchState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FileSearchState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileSearchState&&(identical(other.result, _this.result) || other.result == _this.result)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.starting, _this.starting) || other.starting == _this.starting)&&(identical(other.stopping, _this.stopping) || other.stopping == _this.stopping));
}


@override
int get hashCode {
  final _this = this as FileSearchState;
  return Object.hash(runtimeType,_this.result,_this.error,_this.starting,_this.stopping);
}

@override
String toString() {
  final _this = this as FileSearchState;
  return 'FileSearchState(result: ${_this.result}, error: ${_this.error}, starting: ${_this.starting}, stopping: ${_this.stopping})';
}


}

/// @nodoc
abstract mixin class $FileSearchStateCopyWith<$Res>  {
  factory $FileSearchStateCopyWith(FileSearchState value, $Res Function(FileSearchState) _then) = _$FileSearchStateCopyWithImpl;
@useResult
$Res call({
 FileSearchSnapshot? result, String? error, bool starting, bool stopping
});


$FileSearchSnapshotCopyWith<$Res>? get result;

}
/// @nodoc
class _$FileSearchStateCopyWithImpl<$Res>
    implements $FileSearchStateCopyWith<$Res> {
  _$FileSearchStateCopyWithImpl(this._self, this._then);

  final FileSearchState _self;
  final $Res Function(FileSearchState) _then;

/// Create a copy of FileSearchState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? result = freezed,Object? error = freezed,Object? starting = null,Object? stopping = null,}) {
  return _then(FileSearchState(
result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as FileSearchSnapshot?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,starting: null == starting ? _self.starting : starting // ignore: cast_nullable_to_non_nullable
as bool,stopping: null == stopping ? _self.stopping : stopping // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of FileSearchState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FileSearchSnapshotCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $FileSearchSnapshotCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}


/// Adds pattern-matching-related methods to [FileSearchState].
extension FileSearchStatePatterns on FileSearchState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileSearchState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileSearchState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileSearchState value)  $default,){
final _that = this;
switch (_that) {
case _FileSearchState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileSearchState value)?  $default,){
final _that = this;
switch (_that) {
case _FileSearchState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( FileSearchSnapshot? result,  String? error,  bool starting,  bool stopping)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileSearchState() when $default != null:
return $default(_that.result,_that.error,_that.starting,_that.stopping);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( FileSearchSnapshot? result,  String? error,  bool starting,  bool stopping)  $default,) {final _that = this;
switch (_that) {
case _FileSearchState():
return $default(_that.result,_that.error,_that.starting,_that.stopping);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( FileSearchSnapshot? result,  String? error,  bool starting,  bool stopping)?  $default,) {final _that = this;
switch (_that) {
case _FileSearchState() when $default != null:
return $default(_that.result,_that.error,_that.starting,_that.stopping);case _:
  return null;

}
}

}

/// @nodoc


class _FileSearchState extends FileSearchState {
  const _FileSearchState({this.result, this.error, this.starting = false, this.stopping = false}): super._();
  

@override final  FileSearchSnapshot? result;
@override final  String? error;
@override@JsonKey() final  bool starting;
@override@JsonKey() final  bool stopping;

/// Create a copy of FileSearchState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileSearchStateCopyWith<_FileSearchState> get copyWith => __$FileSearchStateCopyWithImpl<_FileSearchState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileSearchState&&(identical(other.result, result) || other.result == result)&&(identical(other.error, error) || other.error == error)&&(identical(other.starting, starting) || other.starting == starting)&&(identical(other.stopping, stopping) || other.stopping == stopping));
}


@override
int get hashCode {
    return Object.hash(runtimeType,result,error,starting,stopping);
}

@override
String toString() {
    return 'FileSearchState(result: $result, error: $error, starting: $starting, stopping: $stopping)';
}


}

/// @nodoc
abstract mixin class _$FileSearchStateCopyWith<$Res> implements $FileSearchStateCopyWith<$Res> {
  factory _$FileSearchStateCopyWith(_FileSearchState value, $Res Function(_FileSearchState) _then) = __$FileSearchStateCopyWithImpl;
@override @useResult
$Res call({
 FileSearchSnapshot? result, String? error, bool starting, bool stopping
});


@override $FileSearchSnapshotCopyWith<$Res>? get result;

}
/// @nodoc
class __$FileSearchStateCopyWithImpl<$Res>
    implements _$FileSearchStateCopyWith<$Res> {
  __$FileSearchStateCopyWithImpl(this._self, this._then);

  final _FileSearchState _self;
  final $Res Function(_FileSearchState) _then;

/// Create a copy of FileSearchState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? result = freezed,Object? error = freezed,Object? starting = null,Object? stopping = null,}) {
  return _then(_FileSearchState(
result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as FileSearchSnapshot?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,starting: null == starting ? _self.starting : starting // ignore: cast_nullable_to_non_nullable
as bool,stopping: null == stopping ? _self.stopping : stopping // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of FileSearchState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FileSearchSnapshotCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $FileSearchSnapshotCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

// dart format on
