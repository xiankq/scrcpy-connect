// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'file_search.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FileSearchSnapshot {

 String get deviceId; String get searchId; String get path; DateTime? get startedAt; DateTime? get checkedAt; String get query; FileCatalogFilter get filter;@JsonKey(unknownEnumValue: FileSearchStatus.unknown) FileSearchStatus get status; List<FileCatalogEntry> get entries; List<FileCatalogIssue> get issues; int get visitedEntries; int get visitedDirectories; String get currentDirectory; int get total; bool get hasMore; bool get limited;
/// Create a copy of FileSearchSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileSearchSnapshotCopyWith<FileSearchSnapshot> get copyWith => _$FileSearchSnapshotCopyWithImpl<FileSearchSnapshot>(this as FileSearchSnapshot, _$identity);

  /// Serializes this FileSearchSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FileSearchSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileSearchSnapshot&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.searchId, _this.searchId) || other.searchId == _this.searchId)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.checkedAt, _this.checkedAt) || other.checkedAt == _this.checkedAt)&&(identical(other.query, _this.query) || other.query == _this.query)&&(identical(other.filter, _this.filter) || other.filter == _this.filter)&&(identical(other.status, _this.status) || other.status == _this.status)&&const DeepCollectionEquality().equals(other.entries, _this.entries)&&const DeepCollectionEquality().equals(other.issues, _this.issues)&&(identical(other.visitedEntries, _this.visitedEntries) || other.visitedEntries == _this.visitedEntries)&&(identical(other.visitedDirectories, _this.visitedDirectories) || other.visitedDirectories == _this.visitedDirectories)&&(identical(other.currentDirectory, _this.currentDirectory) || other.currentDirectory == _this.currentDirectory)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.hasMore, _this.hasMore) || other.hasMore == _this.hasMore)&&(identical(other.limited, _this.limited) || other.limited == _this.limited));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FileSearchSnapshot;
  return Object.hash(runtimeType,_this.deviceId,_this.searchId,_this.path,_this.startedAt,_this.checkedAt,_this.query,_this.filter,_this.status,const DeepCollectionEquality().hash(_this.entries),const DeepCollectionEquality().hash(_this.issues),_this.visitedEntries,_this.visitedDirectories,_this.currentDirectory,_this.total,_this.hasMore,_this.limited);
}

@override
String toString() {
  final _this = this as FileSearchSnapshot;
  return 'FileSearchSnapshot(deviceId: ${_this.deviceId}, searchId: ${_this.searchId}, path: ${_this.path}, startedAt: ${_this.startedAt}, checkedAt: ${_this.checkedAt}, query: ${_this.query}, filter: ${_this.filter}, status: ${_this.status}, entries: ${_this.entries}, issues: ${_this.issues}, visitedEntries: ${_this.visitedEntries}, visitedDirectories: ${_this.visitedDirectories}, currentDirectory: ${_this.currentDirectory}, total: ${_this.total}, hasMore: ${_this.hasMore}, limited: ${_this.limited})';
}


}

/// @nodoc
abstract mixin class $FileSearchSnapshotCopyWith<$Res>  {
  factory $FileSearchSnapshotCopyWith(FileSearchSnapshot value, $Res Function(FileSearchSnapshot) _then) = _$FileSearchSnapshotCopyWithImpl;
@useResult
$Res call({
 String deviceId, String searchId, String path, DateTime? startedAt, DateTime? checkedAt, String query, FileCatalogFilter filter,@JsonKey(unknownEnumValue: FileSearchStatus.unknown) FileSearchStatus status, List<FileCatalogEntry> entries, List<FileCatalogIssue> issues, int visitedEntries, int visitedDirectories, String currentDirectory, int total, bool hasMore, bool limited
});




}
/// @nodoc
class _$FileSearchSnapshotCopyWithImpl<$Res>
    implements $FileSearchSnapshotCopyWith<$Res> {
  _$FileSearchSnapshotCopyWithImpl(this._self, this._then);

  final FileSearchSnapshot _self;
  final $Res Function(FileSearchSnapshot) _then;

/// Create a copy of FileSearchSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? searchId = null,Object? path = null,Object? startedAt = freezed,Object? checkedAt = freezed,Object? query = null,Object? filter = null,Object? status = null,Object? entries = null,Object? issues = null,Object? visitedEntries = null,Object? visitedDirectories = null,Object? currentDirectory = null,Object? total = null,Object? hasMore = null,Object? limited = null,}) {
  return _then(FileSearchSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,searchId: null == searchId ? _self.searchId : searchId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,checkedAt: freezed == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as FileCatalogFilter,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as FileSearchStatus,entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as List<FileCatalogIssue>,visitedEntries: null == visitedEntries ? _self.visitedEntries : visitedEntries // ignore: cast_nullable_to_non_nullable
as int,visitedDirectories: null == visitedDirectories ? _self.visitedDirectories : visitedDirectories // ignore: cast_nullable_to_non_nullable
as int,currentDirectory: null == currentDirectory ? _self.currentDirectory : currentDirectory // ignore: cast_nullable_to_non_nullable
as String,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,limited: null == limited ? _self.limited : limited // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [FileSearchSnapshot].
extension FileSearchSnapshotPatterns on FileSearchSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileSearchSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileSearchSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileSearchSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _FileSearchSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileSearchSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _FileSearchSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  String searchId,  String path,  DateTime? startedAt,  DateTime? checkedAt,  String query,  FileCatalogFilter filter, @JsonKey(unknownEnumValue: FileSearchStatus.unknown)  FileSearchStatus status,  List<FileCatalogEntry> entries,  List<FileCatalogIssue> issues,  int visitedEntries,  int visitedDirectories,  String currentDirectory,  int total,  bool hasMore,  bool limited)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileSearchSnapshot() when $default != null:
return $default(_that.deviceId,_that.searchId,_that.path,_that.startedAt,_that.checkedAt,_that.query,_that.filter,_that.status,_that.entries,_that.issues,_that.visitedEntries,_that.visitedDirectories,_that.currentDirectory,_that.total,_that.hasMore,_that.limited);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  String searchId,  String path,  DateTime? startedAt,  DateTime? checkedAt,  String query,  FileCatalogFilter filter, @JsonKey(unknownEnumValue: FileSearchStatus.unknown)  FileSearchStatus status,  List<FileCatalogEntry> entries,  List<FileCatalogIssue> issues,  int visitedEntries,  int visitedDirectories,  String currentDirectory,  int total,  bool hasMore,  bool limited)  $default,) {final _that = this;
switch (_that) {
case _FileSearchSnapshot():
return $default(_that.deviceId,_that.searchId,_that.path,_that.startedAt,_that.checkedAt,_that.query,_that.filter,_that.status,_that.entries,_that.issues,_that.visitedEntries,_that.visitedDirectories,_that.currentDirectory,_that.total,_that.hasMore,_that.limited);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  String searchId,  String path,  DateTime? startedAt,  DateTime? checkedAt,  String query,  FileCatalogFilter filter, @JsonKey(unknownEnumValue: FileSearchStatus.unknown)  FileSearchStatus status,  List<FileCatalogEntry> entries,  List<FileCatalogIssue> issues,  int visitedEntries,  int visitedDirectories,  String currentDirectory,  int total,  bool hasMore,  bool limited)?  $default,) {final _that = this;
switch (_that) {
case _FileSearchSnapshot() when $default != null:
return $default(_that.deviceId,_that.searchId,_that.path,_that.startedAt,_that.checkedAt,_that.query,_that.filter,_that.status,_that.entries,_that.issues,_that.visitedEntries,_that.visitedDirectories,_that.currentDirectory,_that.total,_that.hasMore,_that.limited);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FileSearchSnapshot extends FileSearchSnapshot {
  const _FileSearchSnapshot({required this.deviceId, required this.searchId, required this.path, this.startedAt, this.checkedAt, this.query = '', this.filter = FileCatalogFilter.all, @JsonKey(unknownEnumValue: FileSearchStatus.unknown) this.status = FileSearchStatus.unknown,  List<FileCatalogEntry> entries = const [],  List<FileCatalogIssue> issues = const [], this.visitedEntries = 0, this.visitedDirectories = 0, this.currentDirectory = '', this.total = 0, this.hasMore = false, this.limited = false}): _entries = entries,_issues = issues,super._();
  factory _FileSearchSnapshot.fromJson(Map<String, dynamic> json) => _$FileSearchSnapshotFromJson(json);

@override final  String deviceId;
@override final  String searchId;
@override final  String path;
@override final  DateTime? startedAt;
@override final  DateTime? checkedAt;
@override@JsonKey() final  String query;
@override@JsonKey() final  FileCatalogFilter filter;
@override@JsonKey(unknownEnumValue: FileSearchStatus.unknown) final  FileSearchStatus status;
 final  List<FileCatalogEntry> _entries;
@override@JsonKey() List<FileCatalogEntry> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}

 final  List<FileCatalogIssue> _issues;
@override@JsonKey() List<FileCatalogIssue> get issues {
  if (_issues is EqualUnmodifiableListView) return _issues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_issues);
}

@override@JsonKey() final  int visitedEntries;
@override@JsonKey() final  int visitedDirectories;
@override@JsonKey() final  String currentDirectory;
@override@JsonKey() final  int total;
@override@JsonKey() final  bool hasMore;
@override@JsonKey() final  bool limited;

/// Create a copy of FileSearchSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileSearchSnapshotCopyWith<_FileSearchSnapshot> get copyWith => __$FileSearchSnapshotCopyWithImpl<_FileSearchSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FileSearchSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileSearchSnapshot&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.searchId, searchId) || other.searchId == searchId)&&(identical(other.path, path) || other.path == path)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.query, query) || other.query == query)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.entries, _entries)&&const DeepCollectionEquality().equals(other.issues, _issues)&&(identical(other.visitedEntries, visitedEntries) || other.visitedEntries == visitedEntries)&&(identical(other.visitedDirectories, visitedDirectories) || other.visitedDirectories == visitedDirectories)&&(identical(other.currentDirectory, currentDirectory) || other.currentDirectory == currentDirectory)&&(identical(other.total, total) || other.total == total)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore)&&(identical(other.limited, limited) || other.limited == limited));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,searchId,path,startedAt,checkedAt,query,filter,status,const DeepCollectionEquality().hash(_entries),const DeepCollectionEquality().hash(_issues),visitedEntries,visitedDirectories,currentDirectory,total,hasMore,limited);
}

@override
String toString() {
    return 'FileSearchSnapshot(deviceId: $deviceId, searchId: $searchId, path: $path, startedAt: $startedAt, checkedAt: $checkedAt, query: $query, filter: $filter, status: $status, entries: $entries, issues: $issues, visitedEntries: $visitedEntries, visitedDirectories: $visitedDirectories, currentDirectory: $currentDirectory, total: $total, hasMore: $hasMore, limited: $limited)';
}


}

/// @nodoc
abstract mixin class _$FileSearchSnapshotCopyWith<$Res> implements $FileSearchSnapshotCopyWith<$Res> {
  factory _$FileSearchSnapshotCopyWith(_FileSearchSnapshot value, $Res Function(_FileSearchSnapshot) _then) = __$FileSearchSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, String searchId, String path, DateTime? startedAt, DateTime? checkedAt, String query, FileCatalogFilter filter,@JsonKey(unknownEnumValue: FileSearchStatus.unknown) FileSearchStatus status, List<FileCatalogEntry> entries, List<FileCatalogIssue> issues, int visitedEntries, int visitedDirectories, String currentDirectory, int total, bool hasMore, bool limited
});




}
/// @nodoc
class __$FileSearchSnapshotCopyWithImpl<$Res>
    implements _$FileSearchSnapshotCopyWith<$Res> {
  __$FileSearchSnapshotCopyWithImpl(this._self, this._then);

  final _FileSearchSnapshot _self;
  final $Res Function(_FileSearchSnapshot) _then;

/// Create a copy of FileSearchSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? searchId = null,Object? path = null,Object? startedAt = freezed,Object? checkedAt = freezed,Object? query = null,Object? filter = null,Object? status = null,Object? entries = null,Object? issues = null,Object? visitedEntries = null,Object? visitedDirectories = null,Object? currentDirectory = null,Object? total = null,Object? hasMore = null,Object? limited = null,}) {
  return _then(_FileSearchSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,searchId: null == searchId ? _self.searchId : searchId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,checkedAt: freezed == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as FileCatalogFilter,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as FileSearchStatus,entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,issues: null == issues ? _self._issues : issues // ignore: cast_nullable_to_non_nullable
as List<FileCatalogIssue>,visitedEntries: null == visitedEntries ? _self.visitedEntries : visitedEntries // ignore: cast_nullable_to_non_nullable
as int,visitedDirectories: null == visitedDirectories ? _self.visitedDirectories : visitedDirectories // ignore: cast_nullable_to_non_nullable
as int,currentDirectory: null == currentDirectory ? _self.currentDirectory : currentDirectory // ignore: cast_nullable_to_non_nullable
as String,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,limited: null == limited ? _self.limited : limited // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
