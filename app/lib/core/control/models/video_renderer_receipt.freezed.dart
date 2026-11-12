// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'video_renderer_receipt.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VideoRendererReceipt {

 String get sessionId; String? get deviceId; String? get expectedCaptureRef; int get captureGeneration; int get generation; int get textureId; int? get decodedWidth; int? get decodedHeight; int? get frameCount; int? get framesDecoded; int? get presentationTimeUs; String? get decoder; String? get renderer; String? get hardwareAcceleration; bool? get hardwareAccelerated;
/// Create a copy of VideoRendererReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoRendererReceiptCopyWith<VideoRendererReceipt> get copyWith => _$VideoRendererReceiptCopyWithImpl<VideoRendererReceipt>(this as VideoRendererReceipt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoRendererReceipt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoRendererReceipt&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.expectedCaptureRef, _this.expectedCaptureRef) || other.expectedCaptureRef == _this.expectedCaptureRef)&&(identical(other.captureGeneration, _this.captureGeneration) || other.captureGeneration == _this.captureGeneration)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.textureId, _this.textureId) || other.textureId == _this.textureId)&&(identical(other.decodedWidth, _this.decodedWidth) || other.decodedWidth == _this.decodedWidth)&&(identical(other.decodedHeight, _this.decodedHeight) || other.decodedHeight == _this.decodedHeight)&&(identical(other.frameCount, _this.frameCount) || other.frameCount == _this.frameCount)&&(identical(other.framesDecoded, _this.framesDecoded) || other.framesDecoded == _this.framesDecoded)&&(identical(other.presentationTimeUs, _this.presentationTimeUs) || other.presentationTimeUs == _this.presentationTimeUs)&&(identical(other.decoder, _this.decoder) || other.decoder == _this.decoder)&&(identical(other.renderer, _this.renderer) || other.renderer == _this.renderer)&&(identical(other.hardwareAcceleration, _this.hardwareAcceleration) || other.hardwareAcceleration == _this.hardwareAcceleration)&&(identical(other.hardwareAccelerated, _this.hardwareAccelerated) || other.hardwareAccelerated == _this.hardwareAccelerated));
}


@override
int get hashCode {
  final _this = this as VideoRendererReceipt;
  return Object.hash(runtimeType,_this.sessionId,_this.deviceId,_this.expectedCaptureRef,_this.captureGeneration,_this.generation,_this.textureId,_this.decodedWidth,_this.decodedHeight,_this.frameCount,_this.framesDecoded,_this.presentationTimeUs,_this.decoder,_this.renderer,_this.hardwareAcceleration,_this.hardwareAccelerated);
}

@override
String toString() {
  final _this = this as VideoRendererReceipt;
  return 'VideoRendererReceipt(sessionId: ${_this.sessionId}, deviceId: ${_this.deviceId}, expectedCaptureRef: ${_this.expectedCaptureRef}, captureGeneration: ${_this.captureGeneration}, generation: ${_this.generation}, textureId: ${_this.textureId}, decodedWidth: ${_this.decodedWidth}, decodedHeight: ${_this.decodedHeight}, frameCount: ${_this.frameCount}, framesDecoded: ${_this.framesDecoded}, presentationTimeUs: ${_this.presentationTimeUs}, decoder: ${_this.decoder}, renderer: ${_this.renderer}, hardwareAcceleration: ${_this.hardwareAcceleration}, hardwareAccelerated: ${_this.hardwareAccelerated})';
}


}

/// @nodoc
abstract mixin class $VideoRendererReceiptCopyWith<$Res>  {
  factory $VideoRendererReceiptCopyWith(VideoRendererReceipt value, $Res Function(VideoRendererReceipt) _then) = _$VideoRendererReceiptCopyWithImpl;
@useResult
$Res call({
 String sessionId, String? deviceId, String? expectedCaptureRef, int captureGeneration, int generation, int textureId, int? decodedWidth, int? decodedHeight, int? frameCount, int? framesDecoded, int? presentationTimeUs, String? decoder, String? renderer, String? hardwareAcceleration, bool? hardwareAccelerated
});




}
/// @nodoc
class _$VideoRendererReceiptCopyWithImpl<$Res>
    implements $VideoRendererReceiptCopyWith<$Res> {
  _$VideoRendererReceiptCopyWithImpl(this._self, this._then);

  final VideoRendererReceipt _self;
  final $Res Function(VideoRendererReceipt) _then;

/// Create a copy of VideoRendererReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? deviceId = freezed,Object? expectedCaptureRef = freezed,Object? captureGeneration = null,Object? generation = null,Object? textureId = null,Object? decodedWidth = freezed,Object? decodedHeight = freezed,Object? frameCount = freezed,Object? framesDecoded = freezed,Object? presentationTimeUs = freezed,Object? decoder = freezed,Object? renderer = freezed,Object? hardwareAcceleration = freezed,Object? hardwareAccelerated = freezed,}) {
  return _then(VideoRendererReceipt(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,expectedCaptureRef: freezed == expectedCaptureRef ? _self.expectedCaptureRef : expectedCaptureRef // ignore: cast_nullable_to_non_nullable
as String?,captureGeneration: null == captureGeneration ? _self.captureGeneration : captureGeneration // ignore: cast_nullable_to_non_nullable
as int,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,textureId: null == textureId ? _self.textureId : textureId // ignore: cast_nullable_to_non_nullable
as int,decodedWidth: freezed == decodedWidth ? _self.decodedWidth : decodedWidth // ignore: cast_nullable_to_non_nullable
as int?,decodedHeight: freezed == decodedHeight ? _self.decodedHeight : decodedHeight // ignore: cast_nullable_to_non_nullable
as int?,frameCount: freezed == frameCount ? _self.frameCount : frameCount // ignore: cast_nullable_to_non_nullable
as int?,framesDecoded: freezed == framesDecoded ? _self.framesDecoded : framesDecoded // ignore: cast_nullable_to_non_nullable
as int?,presentationTimeUs: freezed == presentationTimeUs ? _self.presentationTimeUs : presentationTimeUs // ignore: cast_nullable_to_non_nullable
as int?,decoder: freezed == decoder ? _self.decoder : decoder // ignore: cast_nullable_to_non_nullable
as String?,renderer: freezed == renderer ? _self.renderer : renderer // ignore: cast_nullable_to_non_nullable
as String?,hardwareAcceleration: freezed == hardwareAcceleration ? _self.hardwareAcceleration : hardwareAcceleration // ignore: cast_nullable_to_non_nullable
as String?,hardwareAccelerated: freezed == hardwareAccelerated ? _self.hardwareAccelerated : hardwareAccelerated // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoRendererReceipt].
extension VideoRendererReceiptPatterns on VideoRendererReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoRendererReceipt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoRendererReceipt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoRendererReceipt value)  $default,){
final _that = this;
switch (_that) {
case _VideoRendererReceipt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoRendererReceipt value)?  $default,){
final _that = this;
switch (_that) {
case _VideoRendererReceipt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sessionId,  String? deviceId,  String? expectedCaptureRef,  int captureGeneration,  int generation,  int textureId,  int? decodedWidth,  int? decodedHeight,  int? frameCount,  int? framesDecoded,  int? presentationTimeUs,  String? decoder,  String? renderer,  String? hardwareAcceleration,  bool? hardwareAccelerated)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoRendererReceipt() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.expectedCaptureRef,_that.captureGeneration,_that.generation,_that.textureId,_that.decodedWidth,_that.decodedHeight,_that.frameCount,_that.framesDecoded,_that.presentationTimeUs,_that.decoder,_that.renderer,_that.hardwareAcceleration,_that.hardwareAccelerated);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sessionId,  String? deviceId,  String? expectedCaptureRef,  int captureGeneration,  int generation,  int textureId,  int? decodedWidth,  int? decodedHeight,  int? frameCount,  int? framesDecoded,  int? presentationTimeUs,  String? decoder,  String? renderer,  String? hardwareAcceleration,  bool? hardwareAccelerated)  $default,) {final _that = this;
switch (_that) {
case _VideoRendererReceipt():
return $default(_that.sessionId,_that.deviceId,_that.expectedCaptureRef,_that.captureGeneration,_that.generation,_that.textureId,_that.decodedWidth,_that.decodedHeight,_that.frameCount,_that.framesDecoded,_that.presentationTimeUs,_that.decoder,_that.renderer,_that.hardwareAcceleration,_that.hardwareAccelerated);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sessionId,  String? deviceId,  String? expectedCaptureRef,  int captureGeneration,  int generation,  int textureId,  int? decodedWidth,  int? decodedHeight,  int? frameCount,  int? framesDecoded,  int? presentationTimeUs,  String? decoder,  String? renderer,  String? hardwareAcceleration,  bool? hardwareAccelerated)?  $default,) {final _that = this;
switch (_that) {
case _VideoRendererReceipt() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.expectedCaptureRef,_that.captureGeneration,_that.generation,_that.textureId,_that.decodedWidth,_that.decodedHeight,_that.frameCount,_that.framesDecoded,_that.presentationTimeUs,_that.decoder,_that.renderer,_that.hardwareAcceleration,_that.hardwareAccelerated);case _:
  return null;

}
}

}

/// @nodoc


class _VideoRendererReceipt implements VideoRendererReceipt {
  const _VideoRendererReceipt({required this.sessionId, this.deviceId, this.expectedCaptureRef, required this.captureGeneration, required this.generation, required this.textureId, this.decodedWidth, this.decodedHeight, this.frameCount, this.framesDecoded, this.presentationTimeUs, this.decoder, this.renderer, this.hardwareAcceleration, this.hardwareAccelerated});
  

@override final  String sessionId;
@override final  String? deviceId;
@override final  String? expectedCaptureRef;
@override final  int captureGeneration;
@override final  int generation;
@override final  int textureId;
@override final  int? decodedWidth;
@override final  int? decodedHeight;
@override final  int? frameCount;
@override final  int? framesDecoded;
@override final  int? presentationTimeUs;
@override final  String? decoder;
@override final  String? renderer;
@override final  String? hardwareAcceleration;
@override final  bool? hardwareAccelerated;

/// Create a copy of VideoRendererReceipt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoRendererReceiptCopyWith<_VideoRendererReceipt> get copyWith => __$VideoRendererReceiptCopyWithImpl<_VideoRendererReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoRendererReceipt&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.expectedCaptureRef, expectedCaptureRef) || other.expectedCaptureRef == expectedCaptureRef)&&(identical(other.captureGeneration, captureGeneration) || other.captureGeneration == captureGeneration)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.textureId, textureId) || other.textureId == textureId)&&(identical(other.decodedWidth, decodedWidth) || other.decodedWidth == decodedWidth)&&(identical(other.decodedHeight, decodedHeight) || other.decodedHeight == decodedHeight)&&(identical(other.frameCount, frameCount) || other.frameCount == frameCount)&&(identical(other.framesDecoded, framesDecoded) || other.framesDecoded == framesDecoded)&&(identical(other.presentationTimeUs, presentationTimeUs) || other.presentationTimeUs == presentationTimeUs)&&(identical(other.decoder, decoder) || other.decoder == decoder)&&(identical(other.renderer, renderer) || other.renderer == renderer)&&(identical(other.hardwareAcceleration, hardwareAcceleration) || other.hardwareAcceleration == hardwareAcceleration)&&(identical(other.hardwareAccelerated, hardwareAccelerated) || other.hardwareAccelerated == hardwareAccelerated));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId,deviceId,expectedCaptureRef,captureGeneration,generation,textureId,decodedWidth,decodedHeight,frameCount,framesDecoded,presentationTimeUs,decoder,renderer,hardwareAcceleration,hardwareAccelerated);
}

@override
String toString() {
    return 'VideoRendererReceipt(sessionId: $sessionId, deviceId: $deviceId, expectedCaptureRef: $expectedCaptureRef, captureGeneration: $captureGeneration, generation: $generation, textureId: $textureId, decodedWidth: $decodedWidth, decodedHeight: $decodedHeight, frameCount: $frameCount, framesDecoded: $framesDecoded, presentationTimeUs: $presentationTimeUs, decoder: $decoder, renderer: $renderer, hardwareAcceleration: $hardwareAcceleration, hardwareAccelerated: $hardwareAccelerated)';
}


}

/// @nodoc
abstract mixin class _$VideoRendererReceiptCopyWith<$Res> implements $VideoRendererReceiptCopyWith<$Res> {
  factory _$VideoRendererReceiptCopyWith(_VideoRendererReceipt value, $Res Function(_VideoRendererReceipt) _then) = __$VideoRendererReceiptCopyWithImpl;
@override @useResult
$Res call({
 String sessionId, String? deviceId, String? expectedCaptureRef, int captureGeneration, int generation, int textureId, int? decodedWidth, int? decodedHeight, int? frameCount, int? framesDecoded, int? presentationTimeUs, String? decoder, String? renderer, String? hardwareAcceleration, bool? hardwareAccelerated
});




}
/// @nodoc
class __$VideoRendererReceiptCopyWithImpl<$Res>
    implements _$VideoRendererReceiptCopyWith<$Res> {
  __$VideoRendererReceiptCopyWithImpl(this._self, this._then);

  final _VideoRendererReceipt _self;
  final $Res Function(_VideoRendererReceipt) _then;

/// Create a copy of VideoRendererReceipt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? deviceId = freezed,Object? expectedCaptureRef = freezed,Object? captureGeneration = null,Object? generation = null,Object? textureId = null,Object? decodedWidth = freezed,Object? decodedHeight = freezed,Object? frameCount = freezed,Object? framesDecoded = freezed,Object? presentationTimeUs = freezed,Object? decoder = freezed,Object? renderer = freezed,Object? hardwareAcceleration = freezed,Object? hardwareAccelerated = freezed,}) {
  return _then(_VideoRendererReceipt(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,expectedCaptureRef: freezed == expectedCaptureRef ? _self.expectedCaptureRef : expectedCaptureRef // ignore: cast_nullable_to_non_nullable
as String?,captureGeneration: null == captureGeneration ? _self.captureGeneration : captureGeneration // ignore: cast_nullable_to_non_nullable
as int,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,textureId: null == textureId ? _self.textureId : textureId // ignore: cast_nullable_to_non_nullable
as int,decodedWidth: freezed == decodedWidth ? _self.decodedWidth : decodedWidth // ignore: cast_nullable_to_non_nullable
as int?,decodedHeight: freezed == decodedHeight ? _self.decodedHeight : decodedHeight // ignore: cast_nullable_to_non_nullable
as int?,frameCount: freezed == frameCount ? _self.frameCount : frameCount // ignore: cast_nullable_to_non_nullable
as int?,framesDecoded: freezed == framesDecoded ? _self.framesDecoded : framesDecoded // ignore: cast_nullable_to_non_nullable
as int?,presentationTimeUs: freezed == presentationTimeUs ? _self.presentationTimeUs : presentationTimeUs // ignore: cast_nullable_to_non_nullable
as int?,decoder: freezed == decoder ? _self.decoder : decoder // ignore: cast_nullable_to_non_nullable
as String?,renderer: freezed == renderer ? _self.renderer : renderer // ignore: cast_nullable_to_non_nullable
as String?,hardwareAcceleration: freezed == hardwareAcceleration ? _self.hardwareAcceleration : hardwareAcceleration // ignore: cast_nullable_to_non_nullable
as String?,hardwareAccelerated: freezed == hardwareAccelerated ? _self.hardwareAccelerated : hardwareAccelerated // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

// dart format on
