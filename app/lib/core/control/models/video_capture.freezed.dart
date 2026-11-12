// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'video_capture.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VideoCapture {

 String get sessionId; String get deviceId; String get captureRef; int get captureGeneration; int get generation; String get videoSourceId; VideoCodec get codec; int get width; int get height;
/// Create a copy of VideoCapture
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoCaptureCopyWith<VideoCapture> get copyWith => _$VideoCaptureCopyWithImpl<VideoCapture>(this as VideoCapture, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoCapture;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoCapture&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.captureRef, _this.captureRef) || other.captureRef == _this.captureRef)&&(identical(other.captureGeneration, _this.captureGeneration) || other.captureGeneration == _this.captureGeneration)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.videoSourceId, _this.videoSourceId) || other.videoSourceId == _this.videoSourceId)&&(identical(other.codec, _this.codec) || other.codec == _this.codec)&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.height, _this.height) || other.height == _this.height));
}


@override
int get hashCode {
  final _this = this as VideoCapture;
  return Object.hash(runtimeType,_this.sessionId,_this.deviceId,_this.captureRef,_this.captureGeneration,_this.generation,_this.videoSourceId,_this.codec,_this.width,_this.height);
}

@override
String toString() {
  final _this = this as VideoCapture;
  return 'VideoCapture(sessionId: ${_this.sessionId}, deviceId: ${_this.deviceId}, captureRef: ${_this.captureRef}, captureGeneration: ${_this.captureGeneration}, generation: ${_this.generation}, videoSourceId: ${_this.videoSourceId}, codec: ${_this.codec}, width: ${_this.width}, height: ${_this.height})';
}


}

/// @nodoc
abstract mixin class $VideoCaptureCopyWith<$Res>  {
  factory $VideoCaptureCopyWith(VideoCapture value, $Res Function(VideoCapture) _then) = _$VideoCaptureCopyWithImpl;
@useResult
$Res call({
 String sessionId, String deviceId, String captureRef, int captureGeneration, int generation, String videoSourceId, VideoCodec codec, int width, int height
});




}
/// @nodoc
class _$VideoCaptureCopyWithImpl<$Res>
    implements $VideoCaptureCopyWith<$Res> {
  _$VideoCaptureCopyWithImpl(this._self, this._then);

  final VideoCapture _self;
  final $Res Function(VideoCapture) _then;

/// Create a copy of VideoCapture
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? deviceId = null,Object? captureRef = null,Object? captureGeneration = null,Object? generation = null,Object? videoSourceId = null,Object? codec = null,Object? width = null,Object? height = null,}) {
  return _then(VideoCapture(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,captureRef: null == captureRef ? _self.captureRef : captureRef // ignore: cast_nullable_to_non_nullable
as String,captureGeneration: null == captureGeneration ? _self.captureGeneration : captureGeneration // ignore: cast_nullable_to_non_nullable
as int,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,videoSourceId: null == videoSourceId ? _self.videoSourceId : videoSourceId // ignore: cast_nullable_to_non_nullable
as String,codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoCapture].
extension VideoCapturePatterns on VideoCapture {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoCapture value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoCapture() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoCapture value)  $default,){
final _that = this;
switch (_that) {
case _VideoCapture():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoCapture value)?  $default,){
final _that = this;
switch (_that) {
case _VideoCapture() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sessionId,  String deviceId,  String captureRef,  int captureGeneration,  int generation,  String videoSourceId,  VideoCodec codec,  int width,  int height)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoCapture() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.captureRef,_that.captureGeneration,_that.generation,_that.videoSourceId,_that.codec,_that.width,_that.height);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sessionId,  String deviceId,  String captureRef,  int captureGeneration,  int generation,  String videoSourceId,  VideoCodec codec,  int width,  int height)  $default,) {final _that = this;
switch (_that) {
case _VideoCapture():
return $default(_that.sessionId,_that.deviceId,_that.captureRef,_that.captureGeneration,_that.generation,_that.videoSourceId,_that.codec,_that.width,_that.height);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sessionId,  String deviceId,  String captureRef,  int captureGeneration,  int generation,  String videoSourceId,  VideoCodec codec,  int width,  int height)?  $default,) {final _that = this;
switch (_that) {
case _VideoCapture() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.captureRef,_that.captureGeneration,_that.generation,_that.videoSourceId,_that.codec,_that.width,_that.height);case _:
  return null;

}
}

}

/// @nodoc


class _VideoCapture implements VideoCapture {
  const _VideoCapture({required this.sessionId, required this.deviceId, required this.captureRef, required this.captureGeneration, required this.generation, required this.videoSourceId, required this.codec, required this.width, required this.height});
  

@override final  String sessionId;
@override final  String deviceId;
@override final  String captureRef;
@override final  int captureGeneration;
@override final  int generation;
@override final  String videoSourceId;
@override final  VideoCodec codec;
@override final  int width;
@override final  int height;

/// Create a copy of VideoCapture
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoCaptureCopyWith<_VideoCapture> get copyWith => __$VideoCaptureCopyWithImpl<_VideoCapture>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoCapture&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.captureRef, captureRef) || other.captureRef == captureRef)&&(identical(other.captureGeneration, captureGeneration) || other.captureGeneration == captureGeneration)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.videoSourceId, videoSourceId) || other.videoSourceId == videoSourceId)&&(identical(other.codec, codec) || other.codec == codec)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId,deviceId,captureRef,captureGeneration,generation,videoSourceId,codec,width,height);
}

@override
String toString() {
    return 'VideoCapture(sessionId: $sessionId, deviceId: $deviceId, captureRef: $captureRef, captureGeneration: $captureGeneration, generation: $generation, videoSourceId: $videoSourceId, codec: $codec, width: $width, height: $height)';
}


}

/// @nodoc
abstract mixin class _$VideoCaptureCopyWith<$Res> implements $VideoCaptureCopyWith<$Res> {
  factory _$VideoCaptureCopyWith(_VideoCapture value, $Res Function(_VideoCapture) _then) = __$VideoCaptureCopyWithImpl;
@override @useResult
$Res call({
 String sessionId, String deviceId, String captureRef, int captureGeneration, int generation, String videoSourceId, VideoCodec codec, int width, int height
});




}
/// @nodoc
class __$VideoCaptureCopyWithImpl<$Res>
    implements _$VideoCaptureCopyWith<$Res> {
  __$VideoCaptureCopyWithImpl(this._self, this._then);

  final _VideoCapture _self;
  final $Res Function(_VideoCapture) _then;

/// Create a copy of VideoCapture
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? deviceId = null,Object? captureRef = null,Object? captureGeneration = null,Object? generation = null,Object? videoSourceId = null,Object? codec = null,Object? width = null,Object? height = null,}) {
  return _then(_VideoCapture(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,captureRef: null == captureRef ? _self.captureRef : captureRef // ignore: cast_nullable_to_non_nullable
as String,captureGeneration: null == captureGeneration ? _self.captureGeneration : captureGeneration // ignore: cast_nullable_to_non_nullable
as int,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,videoSourceId: null == videoSourceId ? _self.videoSourceId : videoSourceId // ignore: cast_nullable_to_non_nullable
as String,codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
