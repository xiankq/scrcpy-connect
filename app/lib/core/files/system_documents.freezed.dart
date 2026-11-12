// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'system_documents.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DocumentSource {

 String get sourceId; String get localPath; DocumentKind get kind;
/// Create a copy of DocumentSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DocumentSourceCopyWith<DocumentSource> get copyWith => _$DocumentSourceCopyWithImpl<DocumentSource>(this as DocumentSource, _$identity);

  /// Serializes this DocumentSource to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DocumentSource;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DocumentSource&&(identical(other.sourceId, _this.sourceId) || other.sourceId == _this.sourceId)&&(identical(other.localPath, _this.localPath) || other.localPath == _this.localPath)&&(identical(other.kind, _this.kind) || other.kind == _this.kind));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DocumentSource;
  return Object.hash(runtimeType,_this.sourceId,_this.localPath,_this.kind);
}

@override
String toString() {
  final _this = this as DocumentSource;
  return 'DocumentSource(sourceId: ${_this.sourceId}, localPath: ${_this.localPath}, kind: ${_this.kind})';
}


}

/// @nodoc
abstract mixin class $DocumentSourceCopyWith<$Res>  {
  factory $DocumentSourceCopyWith(DocumentSource value, $Res Function(DocumentSource) _then) = _$DocumentSourceCopyWithImpl;
@useResult
$Res call({
 String sourceId, String localPath, DocumentKind kind
});




}
/// @nodoc
class _$DocumentSourceCopyWithImpl<$Res>
    implements $DocumentSourceCopyWith<$Res> {
  _$DocumentSourceCopyWithImpl(this._self, this._then);

  final DocumentSource _self;
  final $Res Function(DocumentSource) _then;

/// Create a copy of DocumentSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sourceId = null,Object? localPath = null,Object? kind = null,}) {
  return _then(DocumentSource(
sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,localPath: null == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as DocumentKind,
  ));
}

}


/// Adds pattern-matching-related methods to [DocumentSource].
extension DocumentSourcePatterns on DocumentSource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DocumentSource value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DocumentSource() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DocumentSource value)  $default,){
final _that = this;
switch (_that) {
case _DocumentSource():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DocumentSource value)?  $default,){
final _that = this;
switch (_that) {
case _DocumentSource() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sourceId,  String localPath,  DocumentKind kind)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DocumentSource() when $default != null:
return $default(_that.sourceId,_that.localPath,_that.kind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sourceId,  String localPath,  DocumentKind kind)  $default,) {final _that = this;
switch (_that) {
case _DocumentSource():
return $default(_that.sourceId,_that.localPath,_that.kind);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sourceId,  String localPath,  DocumentKind kind)?  $default,) {final _that = this;
switch (_that) {
case _DocumentSource() when $default != null:
return $default(_that.sourceId,_that.localPath,_that.kind);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DocumentSource implements DocumentSource {
  const _DocumentSource({required this.sourceId, required this.localPath, required this.kind});
  factory _DocumentSource.fromJson(Map<String, dynamic> json) => _$DocumentSourceFromJson(json);

@override final  String sourceId;
@override final  String localPath;
@override final  DocumentKind kind;

/// Create a copy of DocumentSource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DocumentSourceCopyWith<_DocumentSource> get copyWith => __$DocumentSourceCopyWithImpl<_DocumentSource>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DocumentSourceToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DocumentSource&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.localPath, localPath) || other.localPath == localPath)&&(identical(other.kind, kind) || other.kind == kind));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,sourceId,localPath,kind);
}

@override
String toString() {
    return 'DocumentSource(sourceId: $sourceId, localPath: $localPath, kind: $kind)';
}


}

/// @nodoc
abstract mixin class _$DocumentSourceCopyWith<$Res> implements $DocumentSourceCopyWith<$Res> {
  factory _$DocumentSourceCopyWith(_DocumentSource value, $Res Function(_DocumentSource) _then) = __$DocumentSourceCopyWithImpl;
@override @useResult
$Res call({
 String sourceId, String localPath, DocumentKind kind
});




}
/// @nodoc
class __$DocumentSourceCopyWithImpl<$Res>
    implements _$DocumentSourceCopyWith<$Res> {
  __$DocumentSourceCopyWithImpl(this._self, this._then);

  final _DocumentSource _self;
  final $Res Function(_DocumentSource) _then;

/// Create a copy of DocumentSource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourceId = null,Object? localPath = null,Object? kind = null,}) {
  return _then(_DocumentSource(
sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,localPath: null == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as DocumentKind,
  ));
}


}


/// @nodoc
mixin _$DocumentIssue {

 String get path; String get code; String get message;
/// Create a copy of DocumentIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DocumentIssueCopyWith<DocumentIssue> get copyWith => _$DocumentIssueCopyWithImpl<DocumentIssue>(this as DocumentIssue, _$identity);

  /// Serializes this DocumentIssue to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DocumentIssue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DocumentIssue&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.message, _this.message) || other.message == _this.message));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DocumentIssue;
  return Object.hash(runtimeType,_this.path,_this.code,_this.message);
}

@override
String toString() {
  final _this = this as DocumentIssue;
  return 'DocumentIssue(path: ${_this.path}, code: ${_this.code}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $DocumentIssueCopyWith<$Res>  {
  factory $DocumentIssueCopyWith(DocumentIssue value, $Res Function(DocumentIssue) _then) = _$DocumentIssueCopyWithImpl;
@useResult
$Res call({
 String path, String code, String message
});




}
/// @nodoc
class _$DocumentIssueCopyWithImpl<$Res>
    implements $DocumentIssueCopyWith<$Res> {
  _$DocumentIssueCopyWithImpl(this._self, this._then);

  final DocumentIssue _self;
  final $Res Function(DocumentIssue) _then;

/// Create a copy of DocumentIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? code = null,Object? message = null,}) {
  return _then(DocumentIssue(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DocumentIssue].
extension DocumentIssuePatterns on DocumentIssue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DocumentIssue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DocumentIssue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DocumentIssue value)  $default,){
final _that = this;
switch (_that) {
case _DocumentIssue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DocumentIssue value)?  $default,){
final _that = this;
switch (_that) {
case _DocumentIssue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  String code,  String message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DocumentIssue() when $default != null:
return $default(_that.path,_that.code,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  String code,  String message)  $default,) {final _that = this;
switch (_that) {
case _DocumentIssue():
return $default(_that.path,_that.code,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  String code,  String message)?  $default,) {final _that = this;
switch (_that) {
case _DocumentIssue() when $default != null:
return $default(_that.path,_that.code,_that.message);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DocumentIssue implements DocumentIssue {
  const _DocumentIssue({this.path = '', this.code = '', this.message = ''});
  factory _DocumentIssue.fromJson(Map<String, dynamic> json) => _$DocumentIssueFromJson(json);

@override@JsonKey() final  String path;
@override@JsonKey() final  String code;
@override@JsonKey() final  String message;

/// Create a copy of DocumentIssue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DocumentIssueCopyWith<_DocumentIssue> get copyWith => __$DocumentIssueCopyWithImpl<_DocumentIssue>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DocumentIssueToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DocumentIssue&&(identical(other.path, path) || other.path == path)&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,path,code,message);
}

@override
String toString() {
    return 'DocumentIssue(path: $path, code: $code, message: $message)';
}


}

/// @nodoc
abstract mixin class _$DocumentIssueCopyWith<$Res> implements $DocumentIssueCopyWith<$Res> {
  factory _$DocumentIssueCopyWith(_DocumentIssue value, $Res Function(_DocumentIssue) _then) = __$DocumentIssueCopyWithImpl;
@override @useResult
$Res call({
 String path, String code, String message
});




}
/// @nodoc
class __$DocumentIssueCopyWithImpl<$Res>
    implements _$DocumentIssueCopyWith<$Res> {
  __$DocumentIssueCopyWithImpl(this._self, this._then);

  final _DocumentIssue _self;
  final $Res Function(_DocumentIssue) _then;

/// Create a copy of DocumentIssue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? code = null,Object? message = null,}) {
  return _then(_DocumentIssue(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$DocumentOutcome {

 DocumentOutcomeStatus get status; String? get operationId; String? get managedSourceId; String? get localPath; String? get uri; String? get name; int? get bytes; int? get files; int? get directories; int? get skipped; int? get errorCount; bool? get errorsTruncated; bool? get partialDestinationPossible; bool? get cacheRetained; List<DocumentIssue> get errors;
/// Create a copy of DocumentOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DocumentOutcomeCopyWith<DocumentOutcome> get copyWith => _$DocumentOutcomeCopyWithImpl<DocumentOutcome>(this as DocumentOutcome, _$identity);

  /// Serializes this DocumentOutcome to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DocumentOutcome;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DocumentOutcome&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.managedSourceId, _this.managedSourceId) || other.managedSourceId == _this.managedSourceId)&&(identical(other.localPath, _this.localPath) || other.localPath == _this.localPath)&&(identical(other.uri, _this.uri) || other.uri == _this.uri)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.bytes, _this.bytes) || other.bytes == _this.bytes)&&(identical(other.files, _this.files) || other.files == _this.files)&&(identical(other.directories, _this.directories) || other.directories == _this.directories)&&(identical(other.skipped, _this.skipped) || other.skipped == _this.skipped)&&(identical(other.errorCount, _this.errorCount) || other.errorCount == _this.errorCount)&&(identical(other.errorsTruncated, _this.errorsTruncated) || other.errorsTruncated == _this.errorsTruncated)&&(identical(other.partialDestinationPossible, _this.partialDestinationPossible) || other.partialDestinationPossible == _this.partialDestinationPossible)&&(identical(other.cacheRetained, _this.cacheRetained) || other.cacheRetained == _this.cacheRetained)&&const DeepCollectionEquality().equals(other.errors, _this.errors));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DocumentOutcome;
  return Object.hash(runtimeType,_this.status,_this.operationId,_this.managedSourceId,_this.localPath,_this.uri,_this.name,_this.bytes,_this.files,_this.directories,_this.skipped,_this.errorCount,_this.errorsTruncated,_this.partialDestinationPossible,_this.cacheRetained,const DeepCollectionEquality().hash(_this.errors));
}

@override
String toString() {
  final _this = this as DocumentOutcome;
  return 'DocumentOutcome(status: ${_this.status}, operationId: ${_this.operationId}, managedSourceId: ${_this.managedSourceId}, localPath: ${_this.localPath}, uri: ${_this.uri}, name: ${_this.name}, bytes: ${_this.bytes}, files: ${_this.files}, directories: ${_this.directories}, skipped: ${_this.skipped}, errorCount: ${_this.errorCount}, errorsTruncated: ${_this.errorsTruncated}, partialDestinationPossible: ${_this.partialDestinationPossible}, cacheRetained: ${_this.cacheRetained}, errors: ${_this.errors})';
}


}

/// @nodoc
abstract mixin class $DocumentOutcomeCopyWith<$Res>  {
  factory $DocumentOutcomeCopyWith(DocumentOutcome value, $Res Function(DocumentOutcome) _then) = _$DocumentOutcomeCopyWithImpl;
@useResult
$Res call({
 DocumentOutcomeStatus status, String? operationId, String? managedSourceId, String? localPath, String? uri, String? name, int? bytes, int? files, int? directories, int? skipped, int? errorCount, bool? errorsTruncated, bool? partialDestinationPossible, bool? cacheRetained, List<DocumentIssue> errors
});




}
/// @nodoc
class _$DocumentOutcomeCopyWithImpl<$Res>
    implements $DocumentOutcomeCopyWith<$Res> {
  _$DocumentOutcomeCopyWithImpl(this._self, this._then);

  final DocumentOutcome _self;
  final $Res Function(DocumentOutcome) _then;

/// Create a copy of DocumentOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? operationId = freezed,Object? managedSourceId = freezed,Object? localPath = freezed,Object? uri = freezed,Object? name = freezed,Object? bytes = freezed,Object? files = freezed,Object? directories = freezed,Object? skipped = freezed,Object? errorCount = freezed,Object? errorsTruncated = freezed,Object? partialDestinationPossible = freezed,Object? cacheRetained = freezed,Object? errors = null,}) {
  return _then(DocumentOutcome(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DocumentOutcomeStatus,operationId: freezed == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String?,managedSourceId: freezed == managedSourceId ? _self.managedSourceId : managedSourceId // ignore: cast_nullable_to_non_nullable
as String?,localPath: freezed == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String?,uri: freezed == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,bytes: freezed == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as int?,files: freezed == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as int?,directories: freezed == directories ? _self.directories : directories // ignore: cast_nullable_to_non_nullable
as int?,skipped: freezed == skipped ? _self.skipped : skipped // ignore: cast_nullable_to_non_nullable
as int?,errorCount: freezed == errorCount ? _self.errorCount : errorCount // ignore: cast_nullable_to_non_nullable
as int?,errorsTruncated: freezed == errorsTruncated ? _self.errorsTruncated : errorsTruncated // ignore: cast_nullable_to_non_nullable
as bool?,partialDestinationPossible: freezed == partialDestinationPossible ? _self.partialDestinationPossible : partialDestinationPossible // ignore: cast_nullable_to_non_nullable
as bool?,cacheRetained: freezed == cacheRetained ? _self.cacheRetained : cacheRetained // ignore: cast_nullable_to_non_nullable
as bool?,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as List<DocumentIssue>,
  ));
}

}


/// Adds pattern-matching-related methods to [DocumentOutcome].
extension DocumentOutcomePatterns on DocumentOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DocumentOutcome value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DocumentOutcome() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DocumentOutcome value)  $default,){
final _that = this;
switch (_that) {
case _DocumentOutcome():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DocumentOutcome value)?  $default,){
final _that = this;
switch (_that) {
case _DocumentOutcome() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DocumentOutcomeStatus status,  String? operationId,  String? managedSourceId,  String? localPath,  String? uri,  String? name,  int? bytes,  int? files,  int? directories,  int? skipped,  int? errorCount,  bool? errorsTruncated,  bool? partialDestinationPossible,  bool? cacheRetained,  List<DocumentIssue> errors)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DocumentOutcome() when $default != null:
return $default(_that.status,_that.operationId,_that.managedSourceId,_that.localPath,_that.uri,_that.name,_that.bytes,_that.files,_that.directories,_that.skipped,_that.errorCount,_that.errorsTruncated,_that.partialDestinationPossible,_that.cacheRetained,_that.errors);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DocumentOutcomeStatus status,  String? operationId,  String? managedSourceId,  String? localPath,  String? uri,  String? name,  int? bytes,  int? files,  int? directories,  int? skipped,  int? errorCount,  bool? errorsTruncated,  bool? partialDestinationPossible,  bool? cacheRetained,  List<DocumentIssue> errors)  $default,) {final _that = this;
switch (_that) {
case _DocumentOutcome():
return $default(_that.status,_that.operationId,_that.managedSourceId,_that.localPath,_that.uri,_that.name,_that.bytes,_that.files,_that.directories,_that.skipped,_that.errorCount,_that.errorsTruncated,_that.partialDestinationPossible,_that.cacheRetained,_that.errors);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DocumentOutcomeStatus status,  String? operationId,  String? managedSourceId,  String? localPath,  String? uri,  String? name,  int? bytes,  int? files,  int? directories,  int? skipped,  int? errorCount,  bool? errorsTruncated,  bool? partialDestinationPossible,  bool? cacheRetained,  List<DocumentIssue> errors)?  $default,) {final _that = this;
switch (_that) {
case _DocumentOutcome() when $default != null:
return $default(_that.status,_that.operationId,_that.managedSourceId,_that.localPath,_that.uri,_that.name,_that.bytes,_that.files,_that.directories,_that.skipped,_that.errorCount,_that.errorsTruncated,_that.partialDestinationPossible,_that.cacheRetained,_that.errors);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class _DocumentOutcome implements DocumentOutcome {
  const _DocumentOutcome({required this.status, this.operationId, this.managedSourceId, this.localPath, this.uri, this.name, this.bytes, this.files, this.directories, this.skipped, this.errorCount, this.errorsTruncated, this.partialDestinationPossible, this.cacheRetained,  List<DocumentIssue> errors = const []}): _errors = errors;
  factory _DocumentOutcome.fromJson(Map<String, dynamic> json) => _$DocumentOutcomeFromJson(json);

@override final  DocumentOutcomeStatus status;
@override final  String? operationId;
@override final  String? managedSourceId;
@override final  String? localPath;
@override final  String? uri;
@override final  String? name;
@override final  int? bytes;
@override final  int? files;
@override final  int? directories;
@override final  int? skipped;
@override final  int? errorCount;
@override final  bool? errorsTruncated;
@override final  bool? partialDestinationPossible;
@override final  bool? cacheRetained;
 final  List<DocumentIssue> _errors;
@override@JsonKey() List<DocumentIssue> get errors {
  if (_errors is EqualUnmodifiableListView) return _errors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_errors);
}


/// Create a copy of DocumentOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DocumentOutcomeCopyWith<_DocumentOutcome> get copyWith => __$DocumentOutcomeCopyWithImpl<_DocumentOutcome>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DocumentOutcomeToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DocumentOutcome&&(identical(other.status, status) || other.status == status)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.managedSourceId, managedSourceId) || other.managedSourceId == managedSourceId)&&(identical(other.localPath, localPath) || other.localPath == localPath)&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.name, name) || other.name == name)&&(identical(other.bytes, bytes) || other.bytes == bytes)&&(identical(other.files, files) || other.files == files)&&(identical(other.directories, directories) || other.directories == directories)&&(identical(other.skipped, skipped) || other.skipped == skipped)&&(identical(other.errorCount, errorCount) || other.errorCount == errorCount)&&(identical(other.errorsTruncated, errorsTruncated) || other.errorsTruncated == errorsTruncated)&&(identical(other.partialDestinationPossible, partialDestinationPossible) || other.partialDestinationPossible == partialDestinationPossible)&&(identical(other.cacheRetained, cacheRetained) || other.cacheRetained == cacheRetained)&&const DeepCollectionEquality().equals(other.errors, _errors));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,status,operationId,managedSourceId,localPath,uri,name,bytes,files,directories,skipped,errorCount,errorsTruncated,partialDestinationPossible,cacheRetained,const DeepCollectionEquality().hash(_errors));
}

@override
String toString() {
    return 'DocumentOutcome(status: $status, operationId: $operationId, managedSourceId: $managedSourceId, localPath: $localPath, uri: $uri, name: $name, bytes: $bytes, files: $files, directories: $directories, skipped: $skipped, errorCount: $errorCount, errorsTruncated: $errorsTruncated, partialDestinationPossible: $partialDestinationPossible, cacheRetained: $cacheRetained, errors: $errors)';
}


}

/// @nodoc
abstract mixin class _$DocumentOutcomeCopyWith<$Res> implements $DocumentOutcomeCopyWith<$Res> {
  factory _$DocumentOutcomeCopyWith(_DocumentOutcome value, $Res Function(_DocumentOutcome) _then) = __$DocumentOutcomeCopyWithImpl;
@override @useResult
$Res call({
 DocumentOutcomeStatus status, String? operationId, String? managedSourceId, String? localPath, String? uri, String? name, int? bytes, int? files, int? directories, int? skipped, int? errorCount, bool? errorsTruncated, bool? partialDestinationPossible, bool? cacheRetained, List<DocumentIssue> errors
});




}
/// @nodoc
class __$DocumentOutcomeCopyWithImpl<$Res>
    implements _$DocumentOutcomeCopyWith<$Res> {
  __$DocumentOutcomeCopyWithImpl(this._self, this._then);

  final _DocumentOutcome _self;
  final $Res Function(_DocumentOutcome) _then;

/// Create a copy of DocumentOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? operationId = freezed,Object? managedSourceId = freezed,Object? localPath = freezed,Object? uri = freezed,Object? name = freezed,Object? bytes = freezed,Object? files = freezed,Object? directories = freezed,Object? skipped = freezed,Object? errorCount = freezed,Object? errorsTruncated = freezed,Object? partialDestinationPossible = freezed,Object? cacheRetained = freezed,Object? errors = null,}) {
  return _then(_DocumentOutcome(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DocumentOutcomeStatus,operationId: freezed == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String?,managedSourceId: freezed == managedSourceId ? _self.managedSourceId : managedSourceId // ignore: cast_nullable_to_non_nullable
as String?,localPath: freezed == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String?,uri: freezed == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,bytes: freezed == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as int?,files: freezed == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as int?,directories: freezed == directories ? _self.directories : directories // ignore: cast_nullable_to_non_nullable
as int?,skipped: freezed == skipped ? _self.skipped : skipped // ignore: cast_nullable_to_non_nullable
as int?,errorCount: freezed == errorCount ? _self.errorCount : errorCount // ignore: cast_nullable_to_non_nullable
as int?,errorsTruncated: freezed == errorsTruncated ? _self.errorsTruncated : errorsTruncated // ignore: cast_nullable_to_non_nullable
as bool?,partialDestinationPossible: freezed == partialDestinationPossible ? _self.partialDestinationPossible : partialDestinationPossible // ignore: cast_nullable_to_non_nullable
as bool?,cacheRetained: freezed == cacheRetained ? _self.cacheRetained : cacheRetained // ignore: cast_nullable_to_non_nullable
as bool?,errors: null == errors ? _self._errors : errors // ignore: cast_nullable_to_non_nullable
as List<DocumentIssue>,
  ));
}


}


/// @nodoc
mixin _$DocumentConflict {

 String get operationId; String get conflictId; String get name;
/// Create a copy of DocumentConflict
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DocumentConflictCopyWith<DocumentConflict> get copyWith => _$DocumentConflictCopyWithImpl<DocumentConflict>(this as DocumentConflict, _$identity);

  /// Serializes this DocumentConflict to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DocumentConflict;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DocumentConflict&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.conflictId, _this.conflictId) || other.conflictId == _this.conflictId)&&(identical(other.name, _this.name) || other.name == _this.name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DocumentConflict;
  return Object.hash(runtimeType,_this.operationId,_this.conflictId,_this.name);
}

@override
String toString() {
  final _this = this as DocumentConflict;
  return 'DocumentConflict(operationId: ${_this.operationId}, conflictId: ${_this.conflictId}, name: ${_this.name})';
}


}

/// @nodoc
abstract mixin class $DocumentConflictCopyWith<$Res>  {
  factory $DocumentConflictCopyWith(DocumentConflict value, $Res Function(DocumentConflict) _then) = _$DocumentConflictCopyWithImpl;
@useResult
$Res call({
 String operationId, String conflictId, String name
});




}
/// @nodoc
class _$DocumentConflictCopyWithImpl<$Res>
    implements $DocumentConflictCopyWith<$Res> {
  _$DocumentConflictCopyWithImpl(this._self, this._then);

  final DocumentConflict _self;
  final $Res Function(DocumentConflict) _then;

/// Create a copy of DocumentConflict
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? conflictId = null,Object? name = null,}) {
  return _then(DocumentConflict(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,conflictId: null == conflictId ? _self.conflictId : conflictId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DocumentConflict].
extension DocumentConflictPatterns on DocumentConflict {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DocumentConflict value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DocumentConflict() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DocumentConflict value)  $default,){
final _that = this;
switch (_that) {
case _DocumentConflict():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DocumentConflict value)?  $default,){
final _that = this;
switch (_that) {
case _DocumentConflict() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String operationId,  String conflictId,  String name)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DocumentConflict() when $default != null:
return $default(_that.operationId,_that.conflictId,_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String operationId,  String conflictId,  String name)  $default,) {final _that = this;
switch (_that) {
case _DocumentConflict():
return $default(_that.operationId,_that.conflictId,_that.name);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String operationId,  String conflictId,  String name)?  $default,) {final _that = this;
switch (_that) {
case _DocumentConflict() when $default != null:
return $default(_that.operationId,_that.conflictId,_that.name);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DocumentConflict implements DocumentConflict {
  const _DocumentConflict({required this.operationId, required this.conflictId, required this.name});
  factory _DocumentConflict.fromJson(Map<String, dynamic> json) => _$DocumentConflictFromJson(json);

@override final  String operationId;
@override final  String conflictId;
@override final  String name;

/// Create a copy of DocumentConflict
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DocumentConflictCopyWith<_DocumentConflict> get copyWith => __$DocumentConflictCopyWithImpl<_DocumentConflict>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DocumentConflictToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DocumentConflict&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.conflictId, conflictId) || other.conflictId == conflictId)&&(identical(other.name, name) || other.name == name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,operationId,conflictId,name);
}

@override
String toString() {
    return 'DocumentConflict(operationId: $operationId, conflictId: $conflictId, name: $name)';
}


}

/// @nodoc
abstract mixin class _$DocumentConflictCopyWith<$Res> implements $DocumentConflictCopyWith<$Res> {
  factory _$DocumentConflictCopyWith(_DocumentConflict value, $Res Function(_DocumentConflict) _then) = __$DocumentConflictCopyWithImpl;
@override @useResult
$Res call({
 String operationId, String conflictId, String name
});




}
/// @nodoc
class __$DocumentConflictCopyWithImpl<$Res>
    implements _$DocumentConflictCopyWith<$Res> {
  __$DocumentConflictCopyWithImpl(this._self, this._then);

  final _DocumentConflict _self;
  final $Res Function(_DocumentConflict) _then;

/// Create a copy of DocumentConflict
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? conflictId = null,Object? name = null,}) {
  return _then(_DocumentConflict(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,conflictId: null == conflictId ? _self.conflictId : conflictId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
