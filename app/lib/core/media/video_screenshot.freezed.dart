// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'video_screenshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VideoScreenshot {

 String get sessionId; String get deviceId; int get generation; String get localPath; int get width; int get height; bool get scaled; bool get paused;
/// Create a copy of VideoScreenshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoScreenshotCopyWith<VideoScreenshot> get copyWith => _$VideoScreenshotCopyWithImpl<VideoScreenshot>(this as VideoScreenshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoScreenshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoScreenshot&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.localPath, _this.localPath) || other.localPath == _this.localPath)&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.height, _this.height) || other.height == _this.height)&&(identical(other.scaled, _this.scaled) || other.scaled == _this.scaled)&&(identical(other.paused, _this.paused) || other.paused == _this.paused));
}


@override
int get hashCode {
  final _this = this as VideoScreenshot;
  return Object.hash(runtimeType,_this.sessionId,_this.deviceId,_this.generation,_this.localPath,_this.width,_this.height,_this.scaled,_this.paused);
}

@override
String toString() {
  final _this = this as VideoScreenshot;
  return 'VideoScreenshot(sessionId: ${_this.sessionId}, deviceId: ${_this.deviceId}, generation: ${_this.generation}, localPath: ${_this.localPath}, width: ${_this.width}, height: ${_this.height}, scaled: ${_this.scaled}, paused: ${_this.paused})';
}


}

/// @nodoc
abstract mixin class $VideoScreenshotCopyWith<$Res>  {
  factory $VideoScreenshotCopyWith(VideoScreenshot value, $Res Function(VideoScreenshot) _then) = _$VideoScreenshotCopyWithImpl;
@useResult
$Res call({
 String sessionId, String deviceId, int generation, String localPath, int width, int height, bool scaled, bool paused
});




}
/// @nodoc
class _$VideoScreenshotCopyWithImpl<$Res>
    implements $VideoScreenshotCopyWith<$Res> {
  _$VideoScreenshotCopyWithImpl(this._self, this._then);

  final VideoScreenshot _self;
  final $Res Function(VideoScreenshot) _then;

/// Create a copy of VideoScreenshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? deviceId = null,Object? generation = null,Object? localPath = null,Object? width = null,Object? height = null,Object? scaled = null,Object? paused = null,}) {
  return _then(VideoScreenshot(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,localPath: null == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,scaled: null == scaled ? _self.scaled : scaled // ignore: cast_nullable_to_non_nullable
as bool,paused: null == paused ? _self.paused : paused // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoScreenshot].
extension VideoScreenshotPatterns on VideoScreenshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoScreenshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoScreenshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoScreenshot value)  $default,){
final _that = this;
switch (_that) {
case _VideoScreenshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoScreenshot value)?  $default,){
final _that = this;
switch (_that) {
case _VideoScreenshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sessionId,  String deviceId,  int generation,  String localPath,  int width,  int height,  bool scaled,  bool paused)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoScreenshot() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.generation,_that.localPath,_that.width,_that.height,_that.scaled,_that.paused);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sessionId,  String deviceId,  int generation,  String localPath,  int width,  int height,  bool scaled,  bool paused)  $default,) {final _that = this;
switch (_that) {
case _VideoScreenshot():
return $default(_that.sessionId,_that.deviceId,_that.generation,_that.localPath,_that.width,_that.height,_that.scaled,_that.paused);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sessionId,  String deviceId,  int generation,  String localPath,  int width,  int height,  bool scaled,  bool paused)?  $default,) {final _that = this;
switch (_that) {
case _VideoScreenshot() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.generation,_that.localPath,_that.width,_that.height,_that.scaled,_that.paused);case _:
  return null;

}
}

}

/// @nodoc


class _VideoScreenshot implements VideoScreenshot {
  const _VideoScreenshot({required this.sessionId, required this.deviceId, required this.generation, required this.localPath, required this.width, required this.height, required this.scaled, required this.paused});
  

@override final  String sessionId;
@override final  String deviceId;
@override final  int generation;
@override final  String localPath;
@override final  int width;
@override final  int height;
@override final  bool scaled;
@override final  bool paused;

/// Create a copy of VideoScreenshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoScreenshotCopyWith<_VideoScreenshot> get copyWith => __$VideoScreenshotCopyWithImpl<_VideoScreenshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoScreenshot&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.localPath, localPath) || other.localPath == localPath)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.scaled, scaled) || other.scaled == scaled)&&(identical(other.paused, paused) || other.paused == paused));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId,deviceId,generation,localPath,width,height,scaled,paused);
}

@override
String toString() {
    return 'VideoScreenshot(sessionId: $sessionId, deviceId: $deviceId, generation: $generation, localPath: $localPath, width: $width, height: $height, scaled: $scaled, paused: $paused)';
}


}

/// @nodoc
abstract mixin class _$VideoScreenshotCopyWith<$Res> implements $VideoScreenshotCopyWith<$Res> {
  factory _$VideoScreenshotCopyWith(_VideoScreenshot value, $Res Function(_VideoScreenshot) _then) = __$VideoScreenshotCopyWithImpl;
@override @useResult
$Res call({
 String sessionId, String deviceId, int generation, String localPath, int width, int height, bool scaled, bool paused
});




}
/// @nodoc
class __$VideoScreenshotCopyWithImpl<$Res>
    implements _$VideoScreenshotCopyWith<$Res> {
  __$VideoScreenshotCopyWithImpl(this._self, this._then);

  final _VideoScreenshot _self;
  final $Res Function(_VideoScreenshot) _then;

/// Create a copy of VideoScreenshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? deviceId = null,Object? generation = null,Object? localPath = null,Object? width = null,Object? height = null,Object? scaled = null,Object? paused = null,}) {
  return _then(_VideoScreenshot(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,localPath: null == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,scaled: null == scaled ? _self.scaled : scaled // ignore: cast_nullable_to_non_nullable
as bool,paused: null == paused ? _self.paused : paused // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
