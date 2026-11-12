// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'file_directory_notifier.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FileDirectoryState {

 FileDirectorySnapshot? get data; bool get loading; Object? get error; int get revision;
/// Create a copy of FileDirectoryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileDirectoryStateCopyWith<FileDirectoryState> get copyWith => _$FileDirectoryStateCopyWithImpl<FileDirectoryState>(this as FileDirectoryState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FileDirectoryState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileDirectoryState&&(identical(other.data, _this.data) || other.data == _this.data)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&const DeepCollectionEquality().equals(other.error, _this.error)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as FileDirectoryState;
  return Object.hash(runtimeType,_this.data,_this.loading,const DeepCollectionEquality().hash(_this.error),_this.revision);
}

@override
String toString() {
  final _this = this as FileDirectoryState;
  return 'FileDirectoryState(data: ${_this.data}, loading: ${_this.loading}, error: ${_this.error}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $FileDirectoryStateCopyWith<$Res>  {
  factory $FileDirectoryStateCopyWith(FileDirectoryState value, $Res Function(FileDirectoryState) _then) = _$FileDirectoryStateCopyWithImpl;
@useResult
$Res call({
 FileDirectorySnapshot? data, bool loading, Object? error, int revision
});


$FileDirectorySnapshotCopyWith<$Res>? get data;

}
/// @nodoc
class _$FileDirectoryStateCopyWithImpl<$Res>
    implements $FileDirectoryStateCopyWith<$Res> {
  _$FileDirectoryStateCopyWithImpl(this._self, this._then);

  final FileDirectoryState _self;
  final $Res Function(FileDirectoryState) _then;

/// Create a copy of FileDirectoryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? data = freezed,Object? loading = null,Object? error = freezed,Object? revision = null,}) {
  return _then(FileDirectoryState(
data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as FileDirectorySnapshot?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error ,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of FileDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FileDirectorySnapshotCopyWith<$Res>? get data {
    if (_self.data == null) {
    return null;
  }

  return $FileDirectorySnapshotCopyWith<$Res>(_self.data!, (value) {
    return _then(_self.copyWith(data: value));
  });
}
}


/// Adds pattern-matching-related methods to [FileDirectoryState].
extension FileDirectoryStatePatterns on FileDirectoryState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileDirectoryState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileDirectoryState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileDirectoryState value)  $default,){
final _that = this;
switch (_that) {
case _FileDirectoryState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileDirectoryState value)?  $default,){
final _that = this;
switch (_that) {
case _FileDirectoryState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( FileDirectorySnapshot? data,  bool loading,  Object? error,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileDirectoryState() when $default != null:
return $default(_that.data,_that.loading,_that.error,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( FileDirectorySnapshot? data,  bool loading,  Object? error,  int revision)  $default,) {final _that = this;
switch (_that) {
case _FileDirectoryState():
return $default(_that.data,_that.loading,_that.error,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( FileDirectorySnapshot? data,  bool loading,  Object? error,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _FileDirectoryState() when $default != null:
return $default(_that.data,_that.loading,_that.error,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _FileDirectoryState extends FileDirectoryState {
  const _FileDirectoryState({this.data, this.loading = true, this.error, this.revision = 0}): super._();
  

@override final  FileDirectorySnapshot? data;
@override@JsonKey() final  bool loading;
@override final  Object? error;
@override@JsonKey() final  int revision;

/// Create a copy of FileDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileDirectoryStateCopyWith<_FileDirectoryState> get copyWith => __$FileDirectoryStateCopyWithImpl<_FileDirectoryState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileDirectoryState&&(identical(other.data, data) || other.data == data)&&(identical(other.loading, loading) || other.loading == loading)&&const DeepCollectionEquality().equals(other.error, error)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,data,loading,const DeepCollectionEquality().hash(error),revision);
}

@override
String toString() {
    return 'FileDirectoryState(data: $data, loading: $loading, error: $error, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$FileDirectoryStateCopyWith<$Res> implements $FileDirectoryStateCopyWith<$Res> {
  factory _$FileDirectoryStateCopyWith(_FileDirectoryState value, $Res Function(_FileDirectoryState) _then) = __$FileDirectoryStateCopyWithImpl;
@override @useResult
$Res call({
 FileDirectorySnapshot? data, bool loading, Object? error, int revision
});


@override $FileDirectorySnapshotCopyWith<$Res>? get data;

}
/// @nodoc
class __$FileDirectoryStateCopyWithImpl<$Res>
    implements _$FileDirectoryStateCopyWith<$Res> {
  __$FileDirectoryStateCopyWithImpl(this._self, this._then);

  final _FileDirectoryState _self;
  final $Res Function(_FileDirectoryState) _then;

/// Create a copy of FileDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? data = freezed,Object? loading = null,Object? error = freezed,Object? revision = null,}) {
  return _then(_FileDirectoryState(
data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as FileDirectorySnapshot?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error ,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of FileDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FileDirectorySnapshotCopyWith<$Res>? get data {
    if (_self.data == null) {
    return null;
  }

  return $FileDirectorySnapshotCopyWith<$Res>(_self.data!, (value) {
    return _then(_self.copyWith(data: value));
  });
}
}

// dart format on
