// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'gallery_scan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$GalleryScanScope {

 List<String> get roots; List<String> get excluded;
/// Create a copy of GalleryScanScope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GalleryScanScopeCopyWith<GalleryScanScope> get copyWith => _$GalleryScanScopeCopyWithImpl<GalleryScanScope>(this as GalleryScanScope, _$identity);

  /// Serializes this GalleryScanScope to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as GalleryScanScope;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryScanScope&&const DeepCollectionEquality().equals(other.roots, _this.roots)&&const DeepCollectionEquality().equals(other.excluded, _this.excluded));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as GalleryScanScope;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.roots),const DeepCollectionEquality().hash(_this.excluded));
}

@override
String toString() {
  final _this = this as GalleryScanScope;
  return 'GalleryScanScope(roots: ${_this.roots}, excluded: ${_this.excluded})';
}


}

/// @nodoc
abstract mixin class $GalleryScanScopeCopyWith<$Res>  {
  factory $GalleryScanScopeCopyWith(GalleryScanScope value, $Res Function(GalleryScanScope) _then) = _$GalleryScanScopeCopyWithImpl;
@useResult
$Res call({
 List<String> roots, List<String> excluded
});




}
/// @nodoc
class _$GalleryScanScopeCopyWithImpl<$Res>
    implements $GalleryScanScopeCopyWith<$Res> {
  _$GalleryScanScopeCopyWithImpl(this._self, this._then);

  final GalleryScanScope _self;
  final $Res Function(GalleryScanScope) _then;

/// Create a copy of GalleryScanScope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roots = null,Object? excluded = null,}) {
  return _then(GalleryScanScope(
roots: null == roots ? _self.roots : roots // ignore: cast_nullable_to_non_nullable
as List<String>,excluded: null == excluded ? _self.excluded : excluded // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [GalleryScanScope].
extension GalleryScanScopePatterns on GalleryScanScope {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GalleryScanScope value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GalleryScanScope() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GalleryScanScope value)  $default,){
final _that = this;
switch (_that) {
case _GalleryScanScope():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GalleryScanScope value)?  $default,){
final _that = this;
switch (_that) {
case _GalleryScanScope() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<String> roots,  List<String> excluded)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GalleryScanScope() when $default != null:
return $default(_that.roots,_that.excluded);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<String> roots,  List<String> excluded)  $default,) {final _that = this;
switch (_that) {
case _GalleryScanScope():
return $default(_that.roots,_that.excluded);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<String> roots,  List<String> excluded)?  $default,) {final _that = this;
switch (_that) {
case _GalleryScanScope() when $default != null:
return $default(_that.roots,_that.excluded);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GalleryScanScope implements GalleryScanScope {
  const _GalleryScanScope({ List<String> roots = const [],  List<String> excluded = const []}): _roots = roots,_excluded = excluded;
  factory _GalleryScanScope.fromJson(Map<String, dynamic> json) => _$GalleryScanScopeFromJson(json);

 final  List<String> _roots;
@override@JsonKey() List<String> get roots {
  if (_roots is EqualUnmodifiableListView) return _roots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_roots);
}

 final  List<String> _excluded;
@override@JsonKey() List<String> get excluded {
  if (_excluded is EqualUnmodifiableListView) return _excluded;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_excluded);
}


/// Create a copy of GalleryScanScope
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GalleryScanScopeCopyWith<_GalleryScanScope> get copyWith => __$GalleryScanScopeCopyWithImpl<_GalleryScanScope>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GalleryScanScopeToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GalleryScanScope&&const DeepCollectionEquality().equals(other.roots, _roots)&&const DeepCollectionEquality().equals(other.excluded, _excluded));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_roots),const DeepCollectionEquality().hash(_excluded));
}

@override
String toString() {
    return 'GalleryScanScope(roots: $roots, excluded: $excluded)';
}


}

/// @nodoc
abstract mixin class _$GalleryScanScopeCopyWith<$Res> implements $GalleryScanScopeCopyWith<$Res> {
  factory _$GalleryScanScopeCopyWith(_GalleryScanScope value, $Res Function(_GalleryScanScope) _then) = __$GalleryScanScopeCopyWithImpl;
@override @useResult
$Res call({
 List<String> roots, List<String> excluded
});




}
/// @nodoc
class __$GalleryScanScopeCopyWithImpl<$Res>
    implements _$GalleryScanScopeCopyWith<$Res> {
  __$GalleryScanScopeCopyWithImpl(this._self, this._then);

  final _GalleryScanScope _self;
  final $Res Function(_GalleryScanScope) _then;

/// Create a copy of GalleryScanScope
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roots = null,Object? excluded = null,}) {
  return _then(_GalleryScanScope(
roots: null == roots ? _self._roots : roots // ignore: cast_nullable_to_non_nullable
as List<String>,excluded: null == excluded ? _self._excluded : excluded // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}


/// @nodoc
mixin _$GalleryScanSnapshot {

 String get deviceId; String get scanId;@JsonKey(unknownEnumValue: GalleryScanStatus.unknown) GalleryScanStatus get status; DateTime? get startedAt; DateTime? get checkedAt; List<FileCatalogEntry> get items; List<FileCatalogIssue> get issues; GalleryScanScope get scope; int get total; int get offset; int? get nextOffset; int get visitedEntries; int get visitedDirectories; String get currentDirectory; bool get limited;
/// Create a copy of GalleryScanSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GalleryScanSnapshotCopyWith<GalleryScanSnapshot> get copyWith => _$GalleryScanSnapshotCopyWithImpl<GalleryScanSnapshot>(this as GalleryScanSnapshot, _$identity);

  /// Serializes this GalleryScanSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as GalleryScanSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryScanSnapshot&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.scanId, _this.scanId) || other.scanId == _this.scanId)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.checkedAt, _this.checkedAt) || other.checkedAt == _this.checkedAt)&&const DeepCollectionEquality().equals(other.items, _this.items)&&const DeepCollectionEquality().equals(other.issues, _this.issues)&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset)&&(identical(other.visitedEntries, _this.visitedEntries) || other.visitedEntries == _this.visitedEntries)&&(identical(other.visitedDirectories, _this.visitedDirectories) || other.visitedDirectories == _this.visitedDirectories)&&(identical(other.currentDirectory, _this.currentDirectory) || other.currentDirectory == _this.currentDirectory)&&(identical(other.limited, _this.limited) || other.limited == _this.limited));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as GalleryScanSnapshot;
  return Object.hash(runtimeType,_this.deviceId,_this.scanId,_this.status,_this.startedAt,_this.checkedAt,const DeepCollectionEquality().hash(_this.items),const DeepCollectionEquality().hash(_this.issues),_this.scope,_this.total,_this.offset,_this.nextOffset,_this.visitedEntries,_this.visitedDirectories,_this.currentDirectory,_this.limited);
}

@override
String toString() {
  final _this = this as GalleryScanSnapshot;
  return 'GalleryScanSnapshot(deviceId: ${_this.deviceId}, scanId: ${_this.scanId}, status: ${_this.status}, startedAt: ${_this.startedAt}, checkedAt: ${_this.checkedAt}, items: ${_this.items}, issues: ${_this.issues}, scope: ${_this.scope}, total: ${_this.total}, offset: ${_this.offset}, nextOffset: ${_this.nextOffset}, visitedEntries: ${_this.visitedEntries}, visitedDirectories: ${_this.visitedDirectories}, currentDirectory: ${_this.currentDirectory}, limited: ${_this.limited})';
}


}

/// @nodoc
abstract mixin class $GalleryScanSnapshotCopyWith<$Res>  {
  factory $GalleryScanSnapshotCopyWith(GalleryScanSnapshot value, $Res Function(GalleryScanSnapshot) _then) = _$GalleryScanSnapshotCopyWithImpl;
@useResult
$Res call({
 String deviceId, String scanId,@JsonKey(unknownEnumValue: GalleryScanStatus.unknown) GalleryScanStatus status, DateTime? startedAt, DateTime? checkedAt, List<FileCatalogEntry> items, List<FileCatalogIssue> issues, GalleryScanScope scope, int total, int offset, int? nextOffset, int visitedEntries, int visitedDirectories, String currentDirectory, bool limited
});


$GalleryScanScopeCopyWith<$Res> get scope;

}
/// @nodoc
class _$GalleryScanSnapshotCopyWithImpl<$Res>
    implements $GalleryScanSnapshotCopyWith<$Res> {
  _$GalleryScanSnapshotCopyWithImpl(this._self, this._then);

  final GalleryScanSnapshot _self;
  final $Res Function(GalleryScanSnapshot) _then;

/// Create a copy of GalleryScanSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? scanId = null,Object? status = null,Object? startedAt = freezed,Object? checkedAt = freezed,Object? items = null,Object? issues = null,Object? scope = null,Object? total = null,Object? offset = null,Object? nextOffset = freezed,Object? visitedEntries = null,Object? visitedDirectories = null,Object? currentDirectory = null,Object? limited = null,}) {
  return _then(GalleryScanSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,scanId: null == scanId ? _self.scanId : scanId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as GalleryScanStatus,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,checkedAt: freezed == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as List<FileCatalogIssue>,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as GalleryScanScope,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,visitedEntries: null == visitedEntries ? _self.visitedEntries : visitedEntries // ignore: cast_nullable_to_non_nullable
as int,visitedDirectories: null == visitedDirectories ? _self.visitedDirectories : visitedDirectories // ignore: cast_nullable_to_non_nullable
as int,currentDirectory: null == currentDirectory ? _self.currentDirectory : currentDirectory // ignore: cast_nullable_to_non_nullable
as String,limited: null == limited ? _self.limited : limited // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of GalleryScanSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryScanScopeCopyWith<$Res> get scope {
  
  return $GalleryScanScopeCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [GalleryScanSnapshot].
extension GalleryScanSnapshotPatterns on GalleryScanSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GalleryScanSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GalleryScanSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GalleryScanSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _GalleryScanSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GalleryScanSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _GalleryScanSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  String scanId, @JsonKey(unknownEnumValue: GalleryScanStatus.unknown)  GalleryScanStatus status,  DateTime? startedAt,  DateTime? checkedAt,  List<FileCatalogEntry> items,  List<FileCatalogIssue> issues,  GalleryScanScope scope,  int total,  int offset,  int? nextOffset,  int visitedEntries,  int visitedDirectories,  String currentDirectory,  bool limited)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GalleryScanSnapshot() when $default != null:
return $default(_that.deviceId,_that.scanId,_that.status,_that.startedAt,_that.checkedAt,_that.items,_that.issues,_that.scope,_that.total,_that.offset,_that.nextOffset,_that.visitedEntries,_that.visitedDirectories,_that.currentDirectory,_that.limited);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  String scanId, @JsonKey(unknownEnumValue: GalleryScanStatus.unknown)  GalleryScanStatus status,  DateTime? startedAt,  DateTime? checkedAt,  List<FileCatalogEntry> items,  List<FileCatalogIssue> issues,  GalleryScanScope scope,  int total,  int offset,  int? nextOffset,  int visitedEntries,  int visitedDirectories,  String currentDirectory,  bool limited)  $default,) {final _that = this;
switch (_that) {
case _GalleryScanSnapshot():
return $default(_that.deviceId,_that.scanId,_that.status,_that.startedAt,_that.checkedAt,_that.items,_that.issues,_that.scope,_that.total,_that.offset,_that.nextOffset,_that.visitedEntries,_that.visitedDirectories,_that.currentDirectory,_that.limited);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  String scanId, @JsonKey(unknownEnumValue: GalleryScanStatus.unknown)  GalleryScanStatus status,  DateTime? startedAt,  DateTime? checkedAt,  List<FileCatalogEntry> items,  List<FileCatalogIssue> issues,  GalleryScanScope scope,  int total,  int offset,  int? nextOffset,  int visitedEntries,  int visitedDirectories,  String currentDirectory,  bool limited)?  $default,) {final _that = this;
switch (_that) {
case _GalleryScanSnapshot() when $default != null:
return $default(_that.deviceId,_that.scanId,_that.status,_that.startedAt,_that.checkedAt,_that.items,_that.issues,_that.scope,_that.total,_that.offset,_that.nextOffset,_that.visitedEntries,_that.visitedDirectories,_that.currentDirectory,_that.limited);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GalleryScanSnapshot extends GalleryScanSnapshot {
  const _GalleryScanSnapshot({required this.deviceId, required this.scanId, @JsonKey(unknownEnumValue: GalleryScanStatus.unknown) this.status = GalleryScanStatus.unknown, this.startedAt, this.checkedAt,  List<FileCatalogEntry> items = const [],  List<FileCatalogIssue> issues = const [], this.scope = const GalleryScanScope(), this.total = 0, this.offset = 0, this.nextOffset, this.visitedEntries = 0, this.visitedDirectories = 0, this.currentDirectory = '', this.limited = false}): _items = items,_issues = issues,super._();
  factory _GalleryScanSnapshot.fromJson(Map<String, dynamic> json) => _$GalleryScanSnapshotFromJson(json);

@override final  String deviceId;
@override final  String scanId;
@override@JsonKey(unknownEnumValue: GalleryScanStatus.unknown) final  GalleryScanStatus status;
@override final  DateTime? startedAt;
@override final  DateTime? checkedAt;
 final  List<FileCatalogEntry> _items;
@override@JsonKey() List<FileCatalogEntry> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

 final  List<FileCatalogIssue> _issues;
@override@JsonKey() List<FileCatalogIssue> get issues {
  if (_issues is EqualUnmodifiableListView) return _issues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_issues);
}

@override@JsonKey() final  GalleryScanScope scope;
@override@JsonKey() final  int total;
@override@JsonKey() final  int offset;
@override final  int? nextOffset;
@override@JsonKey() final  int visitedEntries;
@override@JsonKey() final  int visitedDirectories;
@override@JsonKey() final  String currentDirectory;
@override@JsonKey() final  bool limited;

/// Create a copy of GalleryScanSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GalleryScanSnapshotCopyWith<_GalleryScanSnapshot> get copyWith => __$GalleryScanSnapshotCopyWithImpl<_GalleryScanSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GalleryScanSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GalleryScanSnapshot&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.scanId, scanId) || other.scanId == scanId)&&(identical(other.status, status) || other.status == status)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&const DeepCollectionEquality().equals(other.items, _items)&&const DeepCollectionEquality().equals(other.issues, _issues)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.total, total) || other.total == total)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset)&&(identical(other.visitedEntries, visitedEntries) || other.visitedEntries == visitedEntries)&&(identical(other.visitedDirectories, visitedDirectories) || other.visitedDirectories == visitedDirectories)&&(identical(other.currentDirectory, currentDirectory) || other.currentDirectory == currentDirectory)&&(identical(other.limited, limited) || other.limited == limited));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,scanId,status,startedAt,checkedAt,const DeepCollectionEquality().hash(_items),const DeepCollectionEquality().hash(_issues),scope,total,offset,nextOffset,visitedEntries,visitedDirectories,currentDirectory,limited);
}

@override
String toString() {
    return 'GalleryScanSnapshot(deviceId: $deviceId, scanId: $scanId, status: $status, startedAt: $startedAt, checkedAt: $checkedAt, items: $items, issues: $issues, scope: $scope, total: $total, offset: $offset, nextOffset: $nextOffset, visitedEntries: $visitedEntries, visitedDirectories: $visitedDirectories, currentDirectory: $currentDirectory, limited: $limited)';
}


}

/// @nodoc
abstract mixin class _$GalleryScanSnapshotCopyWith<$Res> implements $GalleryScanSnapshotCopyWith<$Res> {
  factory _$GalleryScanSnapshotCopyWith(_GalleryScanSnapshot value, $Res Function(_GalleryScanSnapshot) _then) = __$GalleryScanSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, String scanId,@JsonKey(unknownEnumValue: GalleryScanStatus.unknown) GalleryScanStatus status, DateTime? startedAt, DateTime? checkedAt, List<FileCatalogEntry> items, List<FileCatalogIssue> issues, GalleryScanScope scope, int total, int offset, int? nextOffset, int visitedEntries, int visitedDirectories, String currentDirectory, bool limited
});


@override $GalleryScanScopeCopyWith<$Res> get scope;

}
/// @nodoc
class __$GalleryScanSnapshotCopyWithImpl<$Res>
    implements _$GalleryScanSnapshotCopyWith<$Res> {
  __$GalleryScanSnapshotCopyWithImpl(this._self, this._then);

  final _GalleryScanSnapshot _self;
  final $Res Function(_GalleryScanSnapshot) _then;

/// Create a copy of GalleryScanSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? scanId = null,Object? status = null,Object? startedAt = freezed,Object? checkedAt = freezed,Object? items = null,Object? issues = null,Object? scope = null,Object? total = null,Object? offset = null,Object? nextOffset = freezed,Object? visitedEntries = null,Object? visitedDirectories = null,Object? currentDirectory = null,Object? limited = null,}) {
  return _then(_GalleryScanSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,scanId: null == scanId ? _self.scanId : scanId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as GalleryScanStatus,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,checkedAt: freezed == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,issues: null == issues ? _self._issues : issues // ignore: cast_nullable_to_non_nullable
as List<FileCatalogIssue>,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as GalleryScanScope,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,visitedEntries: null == visitedEntries ? _self.visitedEntries : visitedEntries // ignore: cast_nullable_to_non_nullable
as int,visitedDirectories: null == visitedDirectories ? _self.visitedDirectories : visitedDirectories // ignore: cast_nullable_to_non_nullable
as int,currentDirectory: null == currentDirectory ? _self.currentDirectory : currentDirectory // ignore: cast_nullable_to_non_nullable
as String,limited: null == limited ? _self.limited : limited // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of GalleryScanSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryScanScopeCopyWith<$Res> get scope {
  
  return $GalleryScanScopeCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}

// dart format on
