// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'file_catalog_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FileCatalogEntry {

 String get name; String? get path; String get kind; bool get isDirectory; bool get isSymlink; bool get nameIsUtf8; bool get canOpen; bool get canManage; int? get size; int? get modified; int get modifiedSeconds; String get mime; int get mode; String? get sourceIdentity;@JsonKey(fromJson: _readStamp, toJson: _writeStamp, includeIfNull: false) FileStamp? get sourceStamp; bool get selectable;@JsonKey(includeIfNull: false) String? get errorCode;@JsonKey(includeIfNull: false) String? get reason;
/// Create a copy of FileCatalogEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileCatalogEntryCopyWith<FileCatalogEntry> get copyWith => _$FileCatalogEntryCopyWithImpl<FileCatalogEntry>(this as FileCatalogEntry, _$identity);

  /// Serializes this FileCatalogEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FileCatalogEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileCatalogEntry&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.isDirectory, _this.isDirectory) || other.isDirectory == _this.isDirectory)&&(identical(other.isSymlink, _this.isSymlink) || other.isSymlink == _this.isSymlink)&&(identical(other.nameIsUtf8, _this.nameIsUtf8) || other.nameIsUtf8 == _this.nameIsUtf8)&&(identical(other.canOpen, _this.canOpen) || other.canOpen == _this.canOpen)&&(identical(other.canManage, _this.canManage) || other.canManage == _this.canManage)&&(identical(other.size, _this.size) || other.size == _this.size)&&(identical(other.modified, _this.modified) || other.modified == _this.modified)&&(identical(other.modifiedSeconds, _this.modifiedSeconds) || other.modifiedSeconds == _this.modifiedSeconds)&&(identical(other.mime, _this.mime) || other.mime == _this.mime)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.sourceIdentity, _this.sourceIdentity) || other.sourceIdentity == _this.sourceIdentity)&&(identical(other.sourceStamp, _this.sourceStamp) || other.sourceStamp == _this.sourceStamp)&&(identical(other.selectable, _this.selectable) || other.selectable == _this.selectable)&&(identical(other.errorCode, _this.errorCode) || other.errorCode == _this.errorCode)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FileCatalogEntry;
  return Object.hash(runtimeType,_this.name,_this.path,_this.kind,_this.isDirectory,_this.isSymlink,_this.nameIsUtf8,_this.canOpen,_this.canManage,_this.size,_this.modified,_this.modifiedSeconds,_this.mime,_this.mode,_this.sourceIdentity,_this.sourceStamp,_this.selectable,_this.errorCode,_this.reason);
}

@override
String toString() {
  final _this = this as FileCatalogEntry;
  return 'FileCatalogEntry(name: ${_this.name}, path: ${_this.path}, kind: ${_this.kind}, isDirectory: ${_this.isDirectory}, isSymlink: ${_this.isSymlink}, nameIsUtf8: ${_this.nameIsUtf8}, canOpen: ${_this.canOpen}, canManage: ${_this.canManage}, size: ${_this.size}, modified: ${_this.modified}, modifiedSeconds: ${_this.modifiedSeconds}, mime: ${_this.mime}, mode: ${_this.mode}, sourceIdentity: ${_this.sourceIdentity}, sourceStamp: ${_this.sourceStamp}, selectable: ${_this.selectable}, errorCode: ${_this.errorCode}, reason: ${_this.reason})';
}


}

/// @nodoc
abstract mixin class $FileCatalogEntryCopyWith<$Res>  {
  factory $FileCatalogEntryCopyWith(FileCatalogEntry value, $Res Function(FileCatalogEntry) _then) = _$FileCatalogEntryCopyWithImpl;
@useResult
$Res call({
 String name, String? path, String kind, bool isDirectory, bool isSymlink, bool nameIsUtf8, bool canOpen, bool canManage, int? size, int? modified, int modifiedSeconds, String mime, int mode, String? sourceIdentity,@JsonKey(fromJson: _readStamp, toJson: _writeStamp, includeIfNull: false) FileStamp? sourceStamp, bool selectable,@JsonKey(includeIfNull: false) String? errorCode,@JsonKey(includeIfNull: false) String? reason
});




}
/// @nodoc
class _$FileCatalogEntryCopyWithImpl<$Res>
    implements $FileCatalogEntryCopyWith<$Res> {
  _$FileCatalogEntryCopyWithImpl(this._self, this._then);

  final FileCatalogEntry _self;
  final $Res Function(FileCatalogEntry) _then;

/// Create a copy of FileCatalogEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? path = freezed,Object? kind = null,Object? isDirectory = null,Object? isSymlink = null,Object? nameIsUtf8 = null,Object? canOpen = null,Object? canManage = null,Object? size = freezed,Object? modified = freezed,Object? modifiedSeconds = null,Object? mime = null,Object? mode = null,Object? sourceIdentity = freezed,Object? sourceStamp = freezed,Object? selectable = null,Object? errorCode = freezed,Object? reason = freezed,}) {
  return _then(FileCatalogEntry(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: freezed == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String?,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,isDirectory: null == isDirectory ? _self.isDirectory : isDirectory // ignore: cast_nullable_to_non_nullable
as bool,isSymlink: null == isSymlink ? _self.isSymlink : isSymlink // ignore: cast_nullable_to_non_nullable
as bool,nameIsUtf8: null == nameIsUtf8 ? _self.nameIsUtf8 : nameIsUtf8 // ignore: cast_nullable_to_non_nullable
as bool,canOpen: null == canOpen ? _self.canOpen : canOpen // ignore: cast_nullable_to_non_nullable
as bool,canManage: null == canManage ? _self.canManage : canManage // ignore: cast_nullable_to_non_nullable
as bool,size: freezed == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int?,modified: freezed == modified ? _self.modified : modified // ignore: cast_nullable_to_non_nullable
as int?,modifiedSeconds: null == modifiedSeconds ? _self.modifiedSeconds : modifiedSeconds // ignore: cast_nullable_to_non_nullable
as int,mime: null == mime ? _self.mime : mime // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as int,sourceIdentity: freezed == sourceIdentity ? _self.sourceIdentity : sourceIdentity // ignore: cast_nullable_to_non_nullable
as String?,sourceStamp: freezed == sourceStamp ? _self.sourceStamp : sourceStamp // ignore: cast_nullable_to_non_nullable
as FileStamp?,selectable: null == selectable ? _self.selectable : selectable // ignore: cast_nullable_to_non_nullable
as bool,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [FileCatalogEntry].
extension FileCatalogEntryPatterns on FileCatalogEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileCatalogEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileCatalogEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileCatalogEntry value)  $default,){
final _that = this;
switch (_that) {
case _FileCatalogEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileCatalogEntry value)?  $default,){
final _that = this;
switch (_that) {
case _FileCatalogEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String? path,  String kind,  bool isDirectory,  bool isSymlink,  bool nameIsUtf8,  bool canOpen,  bool canManage,  int? size,  int? modified,  int modifiedSeconds,  String mime,  int mode,  String? sourceIdentity, @JsonKey(fromJson: _readStamp, toJson: _writeStamp, includeIfNull: false)  FileStamp? sourceStamp,  bool selectable, @JsonKey(includeIfNull: false)  String? errorCode, @JsonKey(includeIfNull: false)  String? reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileCatalogEntry() when $default != null:
return $default(_that.name,_that.path,_that.kind,_that.isDirectory,_that.isSymlink,_that.nameIsUtf8,_that.canOpen,_that.canManage,_that.size,_that.modified,_that.modifiedSeconds,_that.mime,_that.mode,_that.sourceIdentity,_that.sourceStamp,_that.selectable,_that.errorCode,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String? path,  String kind,  bool isDirectory,  bool isSymlink,  bool nameIsUtf8,  bool canOpen,  bool canManage,  int? size,  int? modified,  int modifiedSeconds,  String mime,  int mode,  String? sourceIdentity, @JsonKey(fromJson: _readStamp, toJson: _writeStamp, includeIfNull: false)  FileStamp? sourceStamp,  bool selectable, @JsonKey(includeIfNull: false)  String? errorCode, @JsonKey(includeIfNull: false)  String? reason)  $default,) {final _that = this;
switch (_that) {
case _FileCatalogEntry():
return $default(_that.name,_that.path,_that.kind,_that.isDirectory,_that.isSymlink,_that.nameIsUtf8,_that.canOpen,_that.canManage,_that.size,_that.modified,_that.modifiedSeconds,_that.mime,_that.mode,_that.sourceIdentity,_that.sourceStamp,_that.selectable,_that.errorCode,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String? path,  String kind,  bool isDirectory,  bool isSymlink,  bool nameIsUtf8,  bool canOpen,  bool canManage,  int? size,  int? modified,  int modifiedSeconds,  String mime,  int mode,  String? sourceIdentity, @JsonKey(fromJson: _readStamp, toJson: _writeStamp, includeIfNull: false)  FileStamp? sourceStamp,  bool selectable, @JsonKey(includeIfNull: false)  String? errorCode, @JsonKey(includeIfNull: false)  String? reason)?  $default,) {final _that = this;
switch (_that) {
case _FileCatalogEntry() when $default != null:
return $default(_that.name,_that.path,_that.kind,_that.isDirectory,_that.isSymlink,_that.nameIsUtf8,_that.canOpen,_that.canManage,_that.size,_that.modified,_that.modifiedSeconds,_that.mime,_that.mode,_that.sourceIdentity,_that.sourceStamp,_that.selectable,_that.errorCode,_that.reason);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FileCatalogEntry implements FileCatalogEntry {
  const _FileCatalogEntry({this.name = '', this.path, this.kind = 'file', this.isDirectory = false, this.isSymlink = false, this.nameIsUtf8 = true, this.canOpen = true, this.canManage = true, this.size, this.modified, this.modifiedSeconds = 0, this.mime = 'application/octet-stream', this.mode = 0, this.sourceIdentity, @JsonKey(fromJson: _readStamp, toJson: _writeStamp, includeIfNull: false) this.sourceStamp, this.selectable = false, @JsonKey(includeIfNull: false) this.errorCode, @JsonKey(includeIfNull: false) this.reason});
  factory _FileCatalogEntry.fromJson(Map<String, dynamic> json) => _$FileCatalogEntryFromJson(json);

@override@JsonKey() final  String name;
@override final  String? path;
@override@JsonKey() final  String kind;
@override@JsonKey() final  bool isDirectory;
@override@JsonKey() final  bool isSymlink;
@override@JsonKey() final  bool nameIsUtf8;
@override@JsonKey() final  bool canOpen;
@override@JsonKey() final  bool canManage;
@override final  int? size;
@override final  int? modified;
@override@JsonKey() final  int modifiedSeconds;
@override@JsonKey() final  String mime;
@override@JsonKey() final  int mode;
@override final  String? sourceIdentity;
@override@JsonKey(fromJson: _readStamp, toJson: _writeStamp, includeIfNull: false) final  FileStamp? sourceStamp;
@override@JsonKey() final  bool selectable;
@override@JsonKey(includeIfNull: false) final  String? errorCode;
@override@JsonKey(includeIfNull: false) final  String? reason;

/// Create a copy of FileCatalogEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileCatalogEntryCopyWith<_FileCatalogEntry> get copyWith => __$FileCatalogEntryCopyWithImpl<_FileCatalogEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FileCatalogEntryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileCatalogEntry&&(identical(other.name, name) || other.name == name)&&(identical(other.path, path) || other.path == path)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.isDirectory, isDirectory) || other.isDirectory == isDirectory)&&(identical(other.isSymlink, isSymlink) || other.isSymlink == isSymlink)&&(identical(other.nameIsUtf8, nameIsUtf8) || other.nameIsUtf8 == nameIsUtf8)&&(identical(other.canOpen, canOpen) || other.canOpen == canOpen)&&(identical(other.canManage, canManage) || other.canManage == canManage)&&(identical(other.size, size) || other.size == size)&&(identical(other.modified, modified) || other.modified == modified)&&(identical(other.modifiedSeconds, modifiedSeconds) || other.modifiedSeconds == modifiedSeconds)&&(identical(other.mime, mime) || other.mime == mime)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.sourceIdentity, sourceIdentity) || other.sourceIdentity == sourceIdentity)&&(identical(other.sourceStamp, sourceStamp) || other.sourceStamp == sourceStamp)&&(identical(other.selectable, selectable) || other.selectable == selectable)&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode)&&(identical(other.reason, reason) || other.reason == reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,path,kind,isDirectory,isSymlink,nameIsUtf8,canOpen,canManage,size,modified,modifiedSeconds,mime,mode,sourceIdentity,sourceStamp,selectable,errorCode,reason);
}

@override
String toString() {
    return 'FileCatalogEntry(name: $name, path: $path, kind: $kind, isDirectory: $isDirectory, isSymlink: $isSymlink, nameIsUtf8: $nameIsUtf8, canOpen: $canOpen, canManage: $canManage, size: $size, modified: $modified, modifiedSeconds: $modifiedSeconds, mime: $mime, mode: $mode, sourceIdentity: $sourceIdentity, sourceStamp: $sourceStamp, selectable: $selectable, errorCode: $errorCode, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$FileCatalogEntryCopyWith<$Res> implements $FileCatalogEntryCopyWith<$Res> {
  factory _$FileCatalogEntryCopyWith(_FileCatalogEntry value, $Res Function(_FileCatalogEntry) _then) = __$FileCatalogEntryCopyWithImpl;
@override @useResult
$Res call({
 String name, String? path, String kind, bool isDirectory, bool isSymlink, bool nameIsUtf8, bool canOpen, bool canManage, int? size, int? modified, int modifiedSeconds, String mime, int mode, String? sourceIdentity,@JsonKey(fromJson: _readStamp, toJson: _writeStamp, includeIfNull: false) FileStamp? sourceStamp, bool selectable,@JsonKey(includeIfNull: false) String? errorCode,@JsonKey(includeIfNull: false) String? reason
});




}
/// @nodoc
class __$FileCatalogEntryCopyWithImpl<$Res>
    implements _$FileCatalogEntryCopyWith<$Res> {
  __$FileCatalogEntryCopyWithImpl(this._self, this._then);

  final _FileCatalogEntry _self;
  final $Res Function(_FileCatalogEntry) _then;

/// Create a copy of FileCatalogEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? path = freezed,Object? kind = null,Object? isDirectory = null,Object? isSymlink = null,Object? nameIsUtf8 = null,Object? canOpen = null,Object? canManage = null,Object? size = freezed,Object? modified = freezed,Object? modifiedSeconds = null,Object? mime = null,Object? mode = null,Object? sourceIdentity = freezed,Object? sourceStamp = freezed,Object? selectable = null,Object? errorCode = freezed,Object? reason = freezed,}) {
  return _then(_FileCatalogEntry(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: freezed == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String?,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,isDirectory: null == isDirectory ? _self.isDirectory : isDirectory // ignore: cast_nullable_to_non_nullable
as bool,isSymlink: null == isSymlink ? _self.isSymlink : isSymlink // ignore: cast_nullable_to_non_nullable
as bool,nameIsUtf8: null == nameIsUtf8 ? _self.nameIsUtf8 : nameIsUtf8 // ignore: cast_nullable_to_non_nullable
as bool,canOpen: null == canOpen ? _self.canOpen : canOpen // ignore: cast_nullable_to_non_nullable
as bool,canManage: null == canManage ? _self.canManage : canManage // ignore: cast_nullable_to_non_nullable
as bool,size: freezed == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int?,modified: freezed == modified ? _self.modified : modified // ignore: cast_nullable_to_non_nullable
as int?,modifiedSeconds: null == modifiedSeconds ? _self.modifiedSeconds : modifiedSeconds // ignore: cast_nullable_to_non_nullable
as int,mime: null == mime ? _self.mime : mime // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as int,sourceIdentity: freezed == sourceIdentity ? _self.sourceIdentity : sourceIdentity // ignore: cast_nullable_to_non_nullable
as String?,sourceStamp: freezed == sourceStamp ? _self.sourceStamp : sourceStamp // ignore: cast_nullable_to_non_nullable
as FileStamp?,selectable: null == selectable ? _self.selectable : selectable // ignore: cast_nullable_to_non_nullable
as bool,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$FileCatalogIssue {

 String get path; String get code; String get reason;
/// Create a copy of FileCatalogIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileCatalogIssueCopyWith<FileCatalogIssue> get copyWith => _$FileCatalogIssueCopyWithImpl<FileCatalogIssue>(this as FileCatalogIssue, _$identity);

  /// Serializes this FileCatalogIssue to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FileCatalogIssue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileCatalogIssue&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FileCatalogIssue;
  return Object.hash(runtimeType,_this.path,_this.code,_this.reason);
}

@override
String toString() {
  final _this = this as FileCatalogIssue;
  return 'FileCatalogIssue(path: ${_this.path}, code: ${_this.code}, reason: ${_this.reason})';
}


}

/// @nodoc
abstract mixin class $FileCatalogIssueCopyWith<$Res>  {
  factory $FileCatalogIssueCopyWith(FileCatalogIssue value, $Res Function(FileCatalogIssue) _then) = _$FileCatalogIssueCopyWithImpl;
@useResult
$Res call({
 String path, String code, String reason
});




}
/// @nodoc
class _$FileCatalogIssueCopyWithImpl<$Res>
    implements $FileCatalogIssueCopyWith<$Res> {
  _$FileCatalogIssueCopyWithImpl(this._self, this._then);

  final FileCatalogIssue _self;
  final $Res Function(FileCatalogIssue) _then;

/// Create a copy of FileCatalogIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? code = null,Object? reason = null,}) {
  return _then(FileCatalogIssue(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FileCatalogIssue].
extension FileCatalogIssuePatterns on FileCatalogIssue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileCatalogIssue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileCatalogIssue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileCatalogIssue value)  $default,){
final _that = this;
switch (_that) {
case _FileCatalogIssue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileCatalogIssue value)?  $default,){
final _that = this;
switch (_that) {
case _FileCatalogIssue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  String code,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileCatalogIssue() when $default != null:
return $default(_that.path,_that.code,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  String code,  String reason)  $default,) {final _that = this;
switch (_that) {
case _FileCatalogIssue():
return $default(_that.path,_that.code,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  String code,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _FileCatalogIssue() when $default != null:
return $default(_that.path,_that.code,_that.reason);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FileCatalogIssue implements FileCatalogIssue {
  const _FileCatalogIssue({required this.path, required this.code, required this.reason});
  factory _FileCatalogIssue.fromJson(Map<String, dynamic> json) => _$FileCatalogIssueFromJson(json);

@override final  String path;
@override final  String code;
@override final  String reason;

/// Create a copy of FileCatalogIssue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileCatalogIssueCopyWith<_FileCatalogIssue> get copyWith => __$FileCatalogIssueCopyWithImpl<_FileCatalogIssue>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FileCatalogIssueToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileCatalogIssue&&(identical(other.path, path) || other.path == path)&&(identical(other.code, code) || other.code == code)&&(identical(other.reason, reason) || other.reason == reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,path,code,reason);
}

@override
String toString() {
    return 'FileCatalogIssue(path: $path, code: $code, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$FileCatalogIssueCopyWith<$Res> implements $FileCatalogIssueCopyWith<$Res> {
  factory _$FileCatalogIssueCopyWith(_FileCatalogIssue value, $Res Function(_FileCatalogIssue) _then) = __$FileCatalogIssueCopyWithImpl;
@override @useResult
$Res call({
 String path, String code, String reason
});




}
/// @nodoc
class __$FileCatalogIssueCopyWithImpl<$Res>
    implements _$FileCatalogIssueCopyWith<$Res> {
  __$FileCatalogIssueCopyWithImpl(this._self, this._then);

  final _FileCatalogIssue _self;
  final $Res Function(_FileCatalogIssue) _then;

/// Create a copy of FileCatalogIssue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? code = null,Object? reason = null,}) {
  return _then(_FileCatalogIssue(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
