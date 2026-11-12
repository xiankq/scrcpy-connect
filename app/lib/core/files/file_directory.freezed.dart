// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'file_directory.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FileDirectorySnapshot {

 String get deviceId; String get path; List<FileCatalogEntry> get entries; int? get total; int get offset; bool get hasMore; bool get truncated;
/// Create a copy of FileDirectorySnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileDirectorySnapshotCopyWith<FileDirectorySnapshot> get copyWith => _$FileDirectorySnapshotCopyWithImpl<FileDirectorySnapshot>(this as FileDirectorySnapshot, _$identity);

  /// Serializes this FileDirectorySnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FileDirectorySnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileDirectorySnapshot&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.path, _this.path) || other.path == _this.path)&&const DeepCollectionEquality().equals(other.entries, _this.entries)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.hasMore, _this.hasMore) || other.hasMore == _this.hasMore)&&(identical(other.truncated, _this.truncated) || other.truncated == _this.truncated));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FileDirectorySnapshot;
  return Object.hash(runtimeType,_this.deviceId,_this.path,const DeepCollectionEquality().hash(_this.entries),_this.total,_this.offset,_this.hasMore,_this.truncated);
}

@override
String toString() {
  final _this = this as FileDirectorySnapshot;
  return 'FileDirectorySnapshot(deviceId: ${_this.deviceId}, path: ${_this.path}, entries: ${_this.entries}, total: ${_this.total}, offset: ${_this.offset}, hasMore: ${_this.hasMore}, truncated: ${_this.truncated})';
}


}

/// @nodoc
abstract mixin class $FileDirectorySnapshotCopyWith<$Res>  {
  factory $FileDirectorySnapshotCopyWith(FileDirectorySnapshot value, $Res Function(FileDirectorySnapshot) _then) = _$FileDirectorySnapshotCopyWithImpl;
@useResult
$Res call({
 String deviceId, String path, List<FileCatalogEntry> entries, int? total, int offset, bool hasMore, bool truncated
});




}
/// @nodoc
class _$FileDirectorySnapshotCopyWithImpl<$Res>
    implements $FileDirectorySnapshotCopyWith<$Res> {
  _$FileDirectorySnapshotCopyWithImpl(this._self, this._then);

  final FileDirectorySnapshot _self;
  final $Res Function(FileDirectorySnapshot) _then;

/// Create a copy of FileDirectorySnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? path = null,Object? entries = null,Object? total = freezed,Object? offset = null,Object? hasMore = null,Object? truncated = null,}) {
  return _then(FileDirectorySnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int?,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,truncated: null == truncated ? _self.truncated : truncated // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [FileDirectorySnapshot].
extension FileDirectorySnapshotPatterns on FileDirectorySnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileDirectorySnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileDirectorySnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileDirectorySnapshot value)  $default,){
final _that = this;
switch (_that) {
case _FileDirectorySnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileDirectorySnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _FileDirectorySnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  String path,  List<FileCatalogEntry> entries,  int? total,  int offset,  bool hasMore,  bool truncated)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileDirectorySnapshot() when $default != null:
return $default(_that.deviceId,_that.path,_that.entries,_that.total,_that.offset,_that.hasMore,_that.truncated);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  String path,  List<FileCatalogEntry> entries,  int? total,  int offset,  bool hasMore,  bool truncated)  $default,) {final _that = this;
switch (_that) {
case _FileDirectorySnapshot():
return $default(_that.deviceId,_that.path,_that.entries,_that.total,_that.offset,_that.hasMore,_that.truncated);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  String path,  List<FileCatalogEntry> entries,  int? total,  int offset,  bool hasMore,  bool truncated)?  $default,) {final _that = this;
switch (_that) {
case _FileDirectorySnapshot() when $default != null:
return $default(_that.deviceId,_that.path,_that.entries,_that.total,_that.offset,_that.hasMore,_that.truncated);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FileDirectorySnapshot implements FileDirectorySnapshot {
  const _FileDirectorySnapshot({required this.deviceId, required this.path,  List<FileCatalogEntry> entries = const [], this.total, this.offset = 0, this.hasMore = false, this.truncated = false}): _entries = entries;
  factory _FileDirectorySnapshot.fromJson(Map<String, dynamic> json) => _$FileDirectorySnapshotFromJson(json);

@override final  String deviceId;
@override final  String path;
 final  List<FileCatalogEntry> _entries;
@override@JsonKey() List<FileCatalogEntry> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}

@override final  int? total;
@override@JsonKey() final  int offset;
@override@JsonKey() final  bool hasMore;
@override@JsonKey() final  bool truncated;

/// Create a copy of FileDirectorySnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileDirectorySnapshotCopyWith<_FileDirectorySnapshot> get copyWith => __$FileDirectorySnapshotCopyWithImpl<_FileDirectorySnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FileDirectorySnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileDirectorySnapshot&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.path, path) || other.path == path)&&const DeepCollectionEquality().equals(other.entries, _entries)&&(identical(other.total, total) || other.total == total)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore)&&(identical(other.truncated, truncated) || other.truncated == truncated));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,path,const DeepCollectionEquality().hash(_entries),total,offset,hasMore,truncated);
}

@override
String toString() {
    return 'FileDirectorySnapshot(deviceId: $deviceId, path: $path, entries: $entries, total: $total, offset: $offset, hasMore: $hasMore, truncated: $truncated)';
}


}

/// @nodoc
abstract mixin class _$FileDirectorySnapshotCopyWith<$Res> implements $FileDirectorySnapshotCopyWith<$Res> {
  factory _$FileDirectorySnapshotCopyWith(_FileDirectorySnapshot value, $Res Function(_FileDirectorySnapshot) _then) = __$FileDirectorySnapshotCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, String path, List<FileCatalogEntry> entries, int? total, int offset, bool hasMore, bool truncated
});




}
/// @nodoc
class __$FileDirectorySnapshotCopyWithImpl<$Res>
    implements _$FileDirectorySnapshotCopyWith<$Res> {
  __$FileDirectorySnapshotCopyWithImpl(this._self, this._then);

  final _FileDirectorySnapshot _self;
  final $Res Function(_FileDirectorySnapshot) _then;

/// Create a copy of FileDirectorySnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? path = null,Object? entries = null,Object? total = freezed,Object? offset = null,Object? hasMore = null,Object? truncated = null,}) {
  return _then(_FileDirectorySnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int?,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,truncated: null == truncated ? _self.truncated : truncated // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
