// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'incoming_share.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$IncomingShareFile {

 String get name; String get localPath; int get size;
/// Create a copy of IncomingShareFile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IncomingShareFileCopyWith<IncomingShareFile> get copyWith => _$IncomingShareFileCopyWithImpl<IncomingShareFile>(this as IncomingShareFile, _$identity);

  /// Serializes this IncomingShareFile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as IncomingShareFile;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IncomingShareFile&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.localPath, _this.localPath) || other.localPath == _this.localPath)&&(identical(other.size, _this.size) || other.size == _this.size));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as IncomingShareFile;
  return Object.hash(runtimeType,_this.name,_this.localPath,_this.size);
}

@override
String toString() {
  final _this = this as IncomingShareFile;
  return 'IncomingShareFile(name: ${_this.name}, localPath: ${_this.localPath}, size: ${_this.size})';
}


}

/// @nodoc
abstract mixin class $IncomingShareFileCopyWith<$Res>  {
  factory $IncomingShareFileCopyWith(IncomingShareFile value, $Res Function(IncomingShareFile) _then) = _$IncomingShareFileCopyWithImpl;
@useResult
$Res call({
 String name, String localPath, int size
});




}
/// @nodoc
class _$IncomingShareFileCopyWithImpl<$Res>
    implements $IncomingShareFileCopyWith<$Res> {
  _$IncomingShareFileCopyWithImpl(this._self, this._then);

  final IncomingShareFile _self;
  final $Res Function(IncomingShareFile) _then;

/// Create a copy of IncomingShareFile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? localPath = null,Object? size = null,}) {
  return _then(IncomingShareFile(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,localPath: null == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [IncomingShareFile].
extension IncomingShareFilePatterns on IncomingShareFile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _IncomingShareFile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _IncomingShareFile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _IncomingShareFile value)  $default,){
final _that = this;
switch (_that) {
case _IncomingShareFile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _IncomingShareFile value)?  $default,){
final _that = this;
switch (_that) {
case _IncomingShareFile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String localPath,  int size)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _IncomingShareFile() when $default != null:
return $default(_that.name,_that.localPath,_that.size);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String localPath,  int size)  $default,) {final _that = this;
switch (_that) {
case _IncomingShareFile():
return $default(_that.name,_that.localPath,_that.size);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String localPath,  int size)?  $default,) {final _that = this;
switch (_that) {
case _IncomingShareFile() when $default != null:
return $default(_that.name,_that.localPath,_that.size);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _IncomingShareFile implements IncomingShareFile {
  const _IncomingShareFile({required this.name, required this.localPath, required this.size});
  factory _IncomingShareFile.fromJson(Map<String, dynamic> json) => _$IncomingShareFileFromJson(json);

@override final  String name;
@override final  String localPath;
@override final  int size;

/// Create a copy of IncomingShareFile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$IncomingShareFileCopyWith<_IncomingShareFile> get copyWith => __$IncomingShareFileCopyWithImpl<_IncomingShareFile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$IncomingShareFileToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _IncomingShareFile&&(identical(other.name, name) || other.name == name)&&(identical(other.localPath, localPath) || other.localPath == localPath)&&(identical(other.size, size) || other.size == size));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,localPath,size);
}

@override
String toString() {
    return 'IncomingShareFile(name: $name, localPath: $localPath, size: $size)';
}


}

/// @nodoc
abstract mixin class _$IncomingShareFileCopyWith<$Res> implements $IncomingShareFileCopyWith<$Res> {
  factory _$IncomingShareFileCopyWith(_IncomingShareFile value, $Res Function(_IncomingShareFile) _then) = __$IncomingShareFileCopyWithImpl;
@override @useResult
$Res call({
 String name, String localPath, int size
});




}
/// @nodoc
class __$IncomingShareFileCopyWithImpl<$Res>
    implements _$IncomingShareFileCopyWith<$Res> {
  __$IncomingShareFileCopyWithImpl(this._self, this._then);

  final _IncomingShareFile _self;
  final $Res Function(_IncomingShareFile) _then;

/// Create a copy of IncomingShareFile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? localPath = null,Object? size = null,}) {
  return _then(_IncomingShareFile(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,localPath: null == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$IncomingShare {

 String get shareId; IncomingShareStatus get status; String get text; String? get mime; List<IncomingShareFile> get files; List<String> get errors;
/// Create a copy of IncomingShare
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IncomingShareCopyWith<IncomingShare> get copyWith => _$IncomingShareCopyWithImpl<IncomingShare>(this as IncomingShare, _$identity);

  /// Serializes this IncomingShare to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as IncomingShare;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IncomingShare&&(identical(other.shareId, _this.shareId) || other.shareId == _this.shareId)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.mime, _this.mime) || other.mime == _this.mime)&&const DeepCollectionEquality().equals(other.files, _this.files)&&const DeepCollectionEquality().equals(other.errors, _this.errors));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as IncomingShare;
  return Object.hash(runtimeType,_this.shareId,_this.status,_this.text,_this.mime,const DeepCollectionEquality().hash(_this.files),const DeepCollectionEquality().hash(_this.errors));
}

@override
String toString() {
  final _this = this as IncomingShare;
  return 'IncomingShare(shareId: ${_this.shareId}, status: ${_this.status}, text: ${_this.text}, mime: ${_this.mime}, files: ${_this.files}, errors: ${_this.errors})';
}


}

/// @nodoc
abstract mixin class $IncomingShareCopyWith<$Res>  {
  factory $IncomingShareCopyWith(IncomingShare value, $Res Function(IncomingShare) _then) = _$IncomingShareCopyWithImpl;
@useResult
$Res call({
 String shareId, IncomingShareStatus status, String text, String? mime, List<IncomingShareFile> files, List<String> errors
});




}
/// @nodoc
class _$IncomingShareCopyWithImpl<$Res>
    implements $IncomingShareCopyWith<$Res> {
  _$IncomingShareCopyWithImpl(this._self, this._then);

  final IncomingShare _self;
  final $Res Function(IncomingShare) _then;

/// Create a copy of IncomingShare
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? shareId = null,Object? status = null,Object? text = null,Object? mime = freezed,Object? files = null,Object? errors = null,}) {
  return _then(IncomingShare(
shareId: null == shareId ? _self.shareId : shareId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as IncomingShareStatus,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,mime: freezed == mime ? _self.mime : mime // ignore: cast_nullable_to_non_nullable
as String?,files: null == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as List<IncomingShareFile>,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [IncomingShare].
extension IncomingSharePatterns on IncomingShare {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _IncomingShare value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _IncomingShare() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _IncomingShare value)  $default,){
final _that = this;
switch (_that) {
case _IncomingShare():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _IncomingShare value)?  $default,){
final _that = this;
switch (_that) {
case _IncomingShare() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String shareId,  IncomingShareStatus status,  String text,  String? mime,  List<IncomingShareFile> files,  List<String> errors)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _IncomingShare() when $default != null:
return $default(_that.shareId,_that.status,_that.text,_that.mime,_that.files,_that.errors);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String shareId,  IncomingShareStatus status,  String text,  String? mime,  List<IncomingShareFile> files,  List<String> errors)  $default,) {final _that = this;
switch (_that) {
case _IncomingShare():
return $default(_that.shareId,_that.status,_that.text,_that.mime,_that.files,_that.errors);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String shareId,  IncomingShareStatus status,  String text,  String? mime,  List<IncomingShareFile> files,  List<String> errors)?  $default,) {final _that = this;
switch (_that) {
case _IncomingShare() when $default != null:
return $default(_that.shareId,_that.status,_that.text,_that.mime,_that.files,_that.errors);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true)
class _IncomingShare implements IncomingShare {
  const _IncomingShare({required this.shareId, required this.status, this.text = '', this.mime,  List<IncomingShareFile> files = const [],  List<String> errors = const []}): _files = files,_errors = errors;
  factory _IncomingShare.fromJson(Map<String, dynamic> json) => _$IncomingShareFromJson(json);

@override final  String shareId;
@override final  IncomingShareStatus status;
@override@JsonKey() final  String text;
@override final  String? mime;
 final  List<IncomingShareFile> _files;
@override@JsonKey() List<IncomingShareFile> get files {
  if (_files is EqualUnmodifiableListView) return _files;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_files);
}

 final  List<String> _errors;
@override@JsonKey() List<String> get errors {
  if (_errors is EqualUnmodifiableListView) return _errors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_errors);
}


/// Create a copy of IncomingShare
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$IncomingShareCopyWith<_IncomingShare> get copyWith => __$IncomingShareCopyWithImpl<_IncomingShare>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$IncomingShareToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _IncomingShare&&(identical(other.shareId, shareId) || other.shareId == shareId)&&(identical(other.status, status) || other.status == status)&&(identical(other.text, text) || other.text == text)&&(identical(other.mime, mime) || other.mime == mime)&&const DeepCollectionEquality().equals(other.files, _files)&&const DeepCollectionEquality().equals(other.errors, _errors));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,shareId,status,text,mime,const DeepCollectionEquality().hash(_files),const DeepCollectionEquality().hash(_errors));
}

@override
String toString() {
    return 'IncomingShare(shareId: $shareId, status: $status, text: $text, mime: $mime, files: $files, errors: $errors)';
}


}

/// @nodoc
abstract mixin class _$IncomingShareCopyWith<$Res> implements $IncomingShareCopyWith<$Res> {
  factory _$IncomingShareCopyWith(_IncomingShare value, $Res Function(_IncomingShare) _then) = __$IncomingShareCopyWithImpl;
@override @useResult
$Res call({
 String shareId, IncomingShareStatus status, String text, String? mime, List<IncomingShareFile> files, List<String> errors
});




}
/// @nodoc
class __$IncomingShareCopyWithImpl<$Res>
    implements _$IncomingShareCopyWith<$Res> {
  __$IncomingShareCopyWithImpl(this._self, this._then);

  final _IncomingShare _self;
  final $Res Function(_IncomingShare) _then;

/// Create a copy of IncomingShare
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shareId = null,Object? status = null,Object? text = null,Object? mime = freezed,Object? files = null,Object? errors = null,}) {
  return _then(_IncomingShare(
shareId: null == shareId ? _self.shareId : shareId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as IncomingShareStatus,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,mime: freezed == mime ? _self.mime : mime // ignore: cast_nullable_to_non_nullable
as String?,files: null == files ? _self._files : files // ignore: cast_nullable_to_non_nullable
as List<IncomingShareFile>,errors: null == errors ? _self._errors : errors // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
