// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'video_output.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VideoDecoderMetadata {

 String? get decoderName; bool? get hardwareAccelerated; String? get hardwareVerification; bool? get backendHardwareFrames; bool? get platformTexturePrepared; int? get presentedSequence; String? get presentationPath;
/// Create a copy of VideoDecoderMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoDecoderMetadataCopyWith<VideoDecoderMetadata> get copyWith => _$VideoDecoderMetadataCopyWithImpl<VideoDecoderMetadata>(this as VideoDecoderMetadata, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoDecoderMetadata;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoDecoderMetadata&&(identical(other.decoderName, _this.decoderName) || other.decoderName == _this.decoderName)&&(identical(other.hardwareAccelerated, _this.hardwareAccelerated) || other.hardwareAccelerated == _this.hardwareAccelerated)&&(identical(other.hardwareVerification, _this.hardwareVerification) || other.hardwareVerification == _this.hardwareVerification)&&(identical(other.backendHardwareFrames, _this.backendHardwareFrames) || other.backendHardwareFrames == _this.backendHardwareFrames)&&(identical(other.platformTexturePrepared, _this.platformTexturePrepared) || other.platformTexturePrepared == _this.platformTexturePrepared)&&(identical(other.presentedSequence, _this.presentedSequence) || other.presentedSequence == _this.presentedSequence)&&(identical(other.presentationPath, _this.presentationPath) || other.presentationPath == _this.presentationPath));
}


@override
int get hashCode {
  final _this = this as VideoDecoderMetadata;
  return Object.hash(runtimeType,_this.decoderName,_this.hardwareAccelerated,_this.hardwareVerification,_this.backendHardwareFrames,_this.platformTexturePrepared,_this.presentedSequence,_this.presentationPath);
}

@override
String toString() {
  final _this = this as VideoDecoderMetadata;
  return 'VideoDecoderMetadata(decoderName: ${_this.decoderName}, hardwareAccelerated: ${_this.hardwareAccelerated}, hardwareVerification: ${_this.hardwareVerification}, backendHardwareFrames: ${_this.backendHardwareFrames}, platformTexturePrepared: ${_this.platformTexturePrepared}, presentedSequence: ${_this.presentedSequence}, presentationPath: ${_this.presentationPath})';
}


}

/// @nodoc
abstract mixin class $VideoDecoderMetadataCopyWith<$Res>  {
  factory $VideoDecoderMetadataCopyWith(VideoDecoderMetadata value, $Res Function(VideoDecoderMetadata) _then) = _$VideoDecoderMetadataCopyWithImpl;
@useResult
$Res call({
 String? decoderName, bool? hardwareAccelerated, String? hardwareVerification, bool? backendHardwareFrames, bool? platformTexturePrepared, int? presentedSequence, String? presentationPath
});




}
/// @nodoc
class _$VideoDecoderMetadataCopyWithImpl<$Res>
    implements $VideoDecoderMetadataCopyWith<$Res> {
  _$VideoDecoderMetadataCopyWithImpl(this._self, this._then);

  final VideoDecoderMetadata _self;
  final $Res Function(VideoDecoderMetadata) _then;

/// Create a copy of VideoDecoderMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? decoderName = freezed,Object? hardwareAccelerated = freezed,Object? hardwareVerification = freezed,Object? backendHardwareFrames = freezed,Object? platformTexturePrepared = freezed,Object? presentedSequence = freezed,Object? presentationPath = freezed,}) {
  return _then(VideoDecoderMetadata(
decoderName: freezed == decoderName ? _self.decoderName : decoderName // ignore: cast_nullable_to_non_nullable
as String?,hardwareAccelerated: freezed == hardwareAccelerated ? _self.hardwareAccelerated : hardwareAccelerated // ignore: cast_nullable_to_non_nullable
as bool?,hardwareVerification: freezed == hardwareVerification ? _self.hardwareVerification : hardwareVerification // ignore: cast_nullable_to_non_nullable
as String?,backendHardwareFrames: freezed == backendHardwareFrames ? _self.backendHardwareFrames : backendHardwareFrames // ignore: cast_nullable_to_non_nullable
as bool?,platformTexturePrepared: freezed == platformTexturePrepared ? _self.platformTexturePrepared : platformTexturePrepared // ignore: cast_nullable_to_non_nullable
as bool?,presentedSequence: freezed == presentedSequence ? _self.presentedSequence : presentedSequence // ignore: cast_nullable_to_non_nullable
as int?,presentationPath: freezed == presentationPath ? _self.presentationPath : presentationPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoDecoderMetadata].
extension VideoDecoderMetadataPatterns on VideoDecoderMetadata {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoDecoderMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoDecoderMetadata() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoDecoderMetadata value)  $default,){
final _that = this;
switch (_that) {
case _VideoDecoderMetadata():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoDecoderMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _VideoDecoderMetadata() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? decoderName,  bool? hardwareAccelerated,  String? hardwareVerification,  bool? backendHardwareFrames,  bool? platformTexturePrepared,  int? presentedSequence,  String? presentationPath)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoDecoderMetadata() when $default != null:
return $default(_that.decoderName,_that.hardwareAccelerated,_that.hardwareVerification,_that.backendHardwareFrames,_that.platformTexturePrepared,_that.presentedSequence,_that.presentationPath);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? decoderName,  bool? hardwareAccelerated,  String? hardwareVerification,  bool? backendHardwareFrames,  bool? platformTexturePrepared,  int? presentedSequence,  String? presentationPath)  $default,) {final _that = this;
switch (_that) {
case _VideoDecoderMetadata():
return $default(_that.decoderName,_that.hardwareAccelerated,_that.hardwareVerification,_that.backendHardwareFrames,_that.platformTexturePrepared,_that.presentedSequence,_that.presentationPath);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? decoderName,  bool? hardwareAccelerated,  String? hardwareVerification,  bool? backendHardwareFrames,  bool? platformTexturePrepared,  int? presentedSequence,  String? presentationPath)?  $default,) {final _that = this;
switch (_that) {
case _VideoDecoderMetadata() when $default != null:
return $default(_that.decoderName,_that.hardwareAccelerated,_that.hardwareVerification,_that.backendHardwareFrames,_that.platformTexturePrepared,_that.presentedSequence,_that.presentationPath);case _:
  return null;

}
}

}

/// @nodoc


class _VideoDecoderMetadata extends VideoDecoderMetadata {
  const _VideoDecoderMetadata({this.decoderName, this.hardwareAccelerated, this.hardwareVerification, this.backendHardwareFrames, this.platformTexturePrepared, this.presentedSequence, this.presentationPath}): super._();
  

@override final  String? decoderName;
@override final  bool? hardwareAccelerated;
@override final  String? hardwareVerification;
@override final  bool? backendHardwareFrames;
@override final  bool? platformTexturePrepared;
@override final  int? presentedSequence;
@override final  String? presentationPath;

/// Create a copy of VideoDecoderMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoDecoderMetadataCopyWith<_VideoDecoderMetadata> get copyWith => __$VideoDecoderMetadataCopyWithImpl<_VideoDecoderMetadata>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoDecoderMetadata&&(identical(other.decoderName, decoderName) || other.decoderName == decoderName)&&(identical(other.hardwareAccelerated, hardwareAccelerated) || other.hardwareAccelerated == hardwareAccelerated)&&(identical(other.hardwareVerification, hardwareVerification) || other.hardwareVerification == hardwareVerification)&&(identical(other.backendHardwareFrames, backendHardwareFrames) || other.backendHardwareFrames == backendHardwareFrames)&&(identical(other.platformTexturePrepared, platformTexturePrepared) || other.platformTexturePrepared == platformTexturePrepared)&&(identical(other.presentedSequence, presentedSequence) || other.presentedSequence == presentedSequence)&&(identical(other.presentationPath, presentationPath) || other.presentationPath == presentationPath));
}


@override
int get hashCode {
    return Object.hash(runtimeType,decoderName,hardwareAccelerated,hardwareVerification,backendHardwareFrames,platformTexturePrepared,presentedSequence,presentationPath);
}

@override
String toString() {
    return 'VideoDecoderMetadata(decoderName: $decoderName, hardwareAccelerated: $hardwareAccelerated, hardwareVerification: $hardwareVerification, backendHardwareFrames: $backendHardwareFrames, platformTexturePrepared: $platformTexturePrepared, presentedSequence: $presentedSequence, presentationPath: $presentationPath)';
}


}

/// @nodoc
abstract mixin class _$VideoDecoderMetadataCopyWith<$Res> implements $VideoDecoderMetadataCopyWith<$Res> {
  factory _$VideoDecoderMetadataCopyWith(_VideoDecoderMetadata value, $Res Function(_VideoDecoderMetadata) _then) = __$VideoDecoderMetadataCopyWithImpl;
@override @useResult
$Res call({
 String? decoderName, bool? hardwareAccelerated, String? hardwareVerification, bool? backendHardwareFrames, bool? platformTexturePrepared, int? presentedSequence, String? presentationPath
});




}
/// @nodoc
class __$VideoDecoderMetadataCopyWithImpl<$Res>
    implements _$VideoDecoderMetadataCopyWith<$Res> {
  __$VideoDecoderMetadataCopyWithImpl(this._self, this._then);

  final _VideoDecoderMetadata _self;
  final $Res Function(_VideoDecoderMetadata) _then;

/// Create a copy of VideoDecoderMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? decoderName = freezed,Object? hardwareAccelerated = freezed,Object? hardwareVerification = freezed,Object? backendHardwareFrames = freezed,Object? platformTexturePrepared = freezed,Object? presentedSequence = freezed,Object? presentationPath = freezed,}) {
  return _then(_VideoDecoderMetadata(
decoderName: freezed == decoderName ? _self.decoderName : decoderName // ignore: cast_nullable_to_non_nullable
as String?,hardwareAccelerated: freezed == hardwareAccelerated ? _self.hardwareAccelerated : hardwareAccelerated // ignore: cast_nullable_to_non_nullable
as bool?,hardwareVerification: freezed == hardwareVerification ? _self.hardwareVerification : hardwareVerification // ignore: cast_nullable_to_non_nullable
as String?,backendHardwareFrames: freezed == backendHardwareFrames ? _self.backendHardwareFrames : backendHardwareFrames // ignore: cast_nullable_to_non_nullable
as bool?,platformTexturePrepared: freezed == platformTexturePrepared ? _self.platformTexturePrepared : platformTexturePrepared // ignore: cast_nullable_to_non_nullable
as bool?,presentedSequence: freezed == presentedSequence ? _self.presentedSequence : presentedSequence // ignore: cast_nullable_to_non_nullable
as int?,presentationPath: freezed == presentationPath ? _self.presentationPath : presentationPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$VideoOutputReceipt {

 String get sessionId; String get deviceId; String get relayId; int get textureId; int get decodedWidth; int get decodedHeight; String get codec; int get generation; int get captureGeneration; bool get paused; int? get frameCount; int get decodedReceipts; int get snapshotReceipts; VideoDecoderMetadata get decoder; Map<String, int> get startupTimingMs;
/// Create a copy of VideoOutputReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoOutputReceiptCopyWith<VideoOutputReceipt> get copyWith => _$VideoOutputReceiptCopyWithImpl<VideoOutputReceipt>(this as VideoOutputReceipt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoOutputReceipt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoOutputReceipt&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.relayId, _this.relayId) || other.relayId == _this.relayId)&&(identical(other.textureId, _this.textureId) || other.textureId == _this.textureId)&&(identical(other.decodedWidth, _this.decodedWidth) || other.decodedWidth == _this.decodedWidth)&&(identical(other.decodedHeight, _this.decodedHeight) || other.decodedHeight == _this.decodedHeight)&&(identical(other.codec, _this.codec) || other.codec == _this.codec)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.captureGeneration, _this.captureGeneration) || other.captureGeneration == _this.captureGeneration)&&(identical(other.paused, _this.paused) || other.paused == _this.paused)&&(identical(other.frameCount, _this.frameCount) || other.frameCount == _this.frameCount)&&(identical(other.decodedReceipts, _this.decodedReceipts) || other.decodedReceipts == _this.decodedReceipts)&&(identical(other.snapshotReceipts, _this.snapshotReceipts) || other.snapshotReceipts == _this.snapshotReceipts)&&(identical(other.decoder, _this.decoder) || other.decoder == _this.decoder)&&const DeepCollectionEquality().equals(other.startupTimingMs, _this.startupTimingMs));
}


@override
int get hashCode {
  final _this = this as VideoOutputReceipt;
  return Object.hash(runtimeType,_this.sessionId,_this.deviceId,_this.relayId,_this.textureId,_this.decodedWidth,_this.decodedHeight,_this.codec,_this.generation,_this.captureGeneration,_this.paused,_this.frameCount,_this.decodedReceipts,_this.snapshotReceipts,_this.decoder,const DeepCollectionEquality().hash(_this.startupTimingMs));
}

@override
String toString() {
  final _this = this as VideoOutputReceipt;
  return 'VideoOutputReceipt(sessionId: ${_this.sessionId}, deviceId: ${_this.deviceId}, relayId: ${_this.relayId}, textureId: ${_this.textureId}, decodedWidth: ${_this.decodedWidth}, decodedHeight: ${_this.decodedHeight}, codec: ${_this.codec}, generation: ${_this.generation}, captureGeneration: ${_this.captureGeneration}, paused: ${_this.paused}, frameCount: ${_this.frameCount}, decodedReceipts: ${_this.decodedReceipts}, snapshotReceipts: ${_this.snapshotReceipts}, decoder: ${_this.decoder}, startupTimingMs: ${_this.startupTimingMs})';
}


}

/// @nodoc
abstract mixin class $VideoOutputReceiptCopyWith<$Res>  {
  factory $VideoOutputReceiptCopyWith(VideoOutputReceipt value, $Res Function(VideoOutputReceipt) _then) = _$VideoOutputReceiptCopyWithImpl;
@useResult
$Res call({
 String sessionId, String deviceId, String relayId, int textureId, int decodedWidth, int decodedHeight, String codec, int generation, int captureGeneration, bool paused, int? frameCount, int decodedReceipts, int snapshotReceipts, VideoDecoderMetadata decoder, Map<String, int> startupTimingMs
});


$VideoDecoderMetadataCopyWith<$Res> get decoder;

}
/// @nodoc
class _$VideoOutputReceiptCopyWithImpl<$Res>
    implements $VideoOutputReceiptCopyWith<$Res> {
  _$VideoOutputReceiptCopyWithImpl(this._self, this._then);

  final VideoOutputReceipt _self;
  final $Res Function(VideoOutputReceipt) _then;

/// Create a copy of VideoOutputReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? deviceId = null,Object? relayId = null,Object? textureId = null,Object? decodedWidth = null,Object? decodedHeight = null,Object? codec = null,Object? generation = null,Object? captureGeneration = null,Object? paused = null,Object? frameCount = freezed,Object? decodedReceipts = null,Object? snapshotReceipts = null,Object? decoder = null,Object? startupTimingMs = null,}) {
  return _then(VideoOutputReceipt(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,relayId: null == relayId ? _self.relayId : relayId // ignore: cast_nullable_to_non_nullable
as String,textureId: null == textureId ? _self.textureId : textureId // ignore: cast_nullable_to_non_nullable
as int,decodedWidth: null == decodedWidth ? _self.decodedWidth : decodedWidth // ignore: cast_nullable_to_non_nullable
as int,decodedHeight: null == decodedHeight ? _self.decodedHeight : decodedHeight // ignore: cast_nullable_to_non_nullable
as int,codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,captureGeneration: null == captureGeneration ? _self.captureGeneration : captureGeneration // ignore: cast_nullable_to_non_nullable
as int,paused: null == paused ? _self.paused : paused // ignore: cast_nullable_to_non_nullable
as bool,frameCount: freezed == frameCount ? _self.frameCount : frameCount // ignore: cast_nullable_to_non_nullable
as int?,decodedReceipts: null == decodedReceipts ? _self.decodedReceipts : decodedReceipts // ignore: cast_nullable_to_non_nullable
as int,snapshotReceipts: null == snapshotReceipts ? _self.snapshotReceipts : snapshotReceipts // ignore: cast_nullable_to_non_nullable
as int,decoder: null == decoder ? _self.decoder : decoder // ignore: cast_nullable_to_non_nullable
as VideoDecoderMetadata,startupTimingMs: null == startupTimingMs ? _self.startupTimingMs : startupTimingMs // ignore: cast_nullable_to_non_nullable
as Map<String, int>,
  ));
}
/// Create a copy of VideoOutputReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoDecoderMetadataCopyWith<$Res> get decoder {
  
  return $VideoDecoderMetadataCopyWith<$Res>(_self.decoder, (value) {
    return _then(_self.copyWith(decoder: value));
  });
}
}


/// Adds pattern-matching-related methods to [VideoOutputReceipt].
extension VideoOutputReceiptPatterns on VideoOutputReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoOutputReceipt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoOutputReceipt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoOutputReceipt value)  $default,){
final _that = this;
switch (_that) {
case _VideoOutputReceipt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoOutputReceipt value)?  $default,){
final _that = this;
switch (_that) {
case _VideoOutputReceipt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sessionId,  String deviceId,  String relayId,  int textureId,  int decodedWidth,  int decodedHeight,  String codec,  int generation,  int captureGeneration,  bool paused,  int? frameCount,  int decodedReceipts,  int snapshotReceipts,  VideoDecoderMetadata decoder,  Map<String, int> startupTimingMs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoOutputReceipt() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.relayId,_that.textureId,_that.decodedWidth,_that.decodedHeight,_that.codec,_that.generation,_that.captureGeneration,_that.paused,_that.frameCount,_that.decodedReceipts,_that.snapshotReceipts,_that.decoder,_that.startupTimingMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sessionId,  String deviceId,  String relayId,  int textureId,  int decodedWidth,  int decodedHeight,  String codec,  int generation,  int captureGeneration,  bool paused,  int? frameCount,  int decodedReceipts,  int snapshotReceipts,  VideoDecoderMetadata decoder,  Map<String, int> startupTimingMs)  $default,) {final _that = this;
switch (_that) {
case _VideoOutputReceipt():
return $default(_that.sessionId,_that.deviceId,_that.relayId,_that.textureId,_that.decodedWidth,_that.decodedHeight,_that.codec,_that.generation,_that.captureGeneration,_that.paused,_that.frameCount,_that.decodedReceipts,_that.snapshotReceipts,_that.decoder,_that.startupTimingMs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sessionId,  String deviceId,  String relayId,  int textureId,  int decodedWidth,  int decodedHeight,  String codec,  int generation,  int captureGeneration,  bool paused,  int? frameCount,  int decodedReceipts,  int snapshotReceipts,  VideoDecoderMetadata decoder,  Map<String, int> startupTimingMs)?  $default,) {final _that = this;
switch (_that) {
case _VideoOutputReceipt() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.relayId,_that.textureId,_that.decodedWidth,_that.decodedHeight,_that.codec,_that.generation,_that.captureGeneration,_that.paused,_that.frameCount,_that.decodedReceipts,_that.snapshotReceipts,_that.decoder,_that.startupTimingMs);case _:
  return null;

}
}

}

/// @nodoc


class _VideoOutputReceipt extends VideoOutputReceipt {
  const _VideoOutputReceipt({required this.sessionId, required this.deviceId, required this.relayId, required this.textureId, required this.decodedWidth, required this.decodedHeight, required this.codec, required this.generation, required this.captureGeneration, required this.paused, this.frameCount, required this.decodedReceipts, required this.snapshotReceipts, this.decoder = const VideoDecoderMetadata(),  Map<String, int> startupTimingMs = const {}}): _startupTimingMs = startupTimingMs,super._();
  

@override final  String sessionId;
@override final  String deviceId;
@override final  String relayId;
@override final  int textureId;
@override final  int decodedWidth;
@override final  int decodedHeight;
@override final  String codec;
@override final  int generation;
@override final  int captureGeneration;
@override final  bool paused;
@override final  int? frameCount;
@override final  int decodedReceipts;
@override final  int snapshotReceipts;
@override@JsonKey() final  VideoDecoderMetadata decoder;
 final  Map<String, int> _startupTimingMs;
@override@JsonKey() Map<String, int> get startupTimingMs {
  if (_startupTimingMs is EqualUnmodifiableMapView) return _startupTimingMs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_startupTimingMs);
}


/// Create a copy of VideoOutputReceipt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoOutputReceiptCopyWith<_VideoOutputReceipt> get copyWith => __$VideoOutputReceiptCopyWithImpl<_VideoOutputReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoOutputReceipt&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.relayId, relayId) || other.relayId == relayId)&&(identical(other.textureId, textureId) || other.textureId == textureId)&&(identical(other.decodedWidth, decodedWidth) || other.decodedWidth == decodedWidth)&&(identical(other.decodedHeight, decodedHeight) || other.decodedHeight == decodedHeight)&&(identical(other.codec, codec) || other.codec == codec)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.captureGeneration, captureGeneration) || other.captureGeneration == captureGeneration)&&(identical(other.paused, paused) || other.paused == paused)&&(identical(other.frameCount, frameCount) || other.frameCount == frameCount)&&(identical(other.decodedReceipts, decodedReceipts) || other.decodedReceipts == decodedReceipts)&&(identical(other.snapshotReceipts, snapshotReceipts) || other.snapshotReceipts == snapshotReceipts)&&(identical(other.decoder, decoder) || other.decoder == decoder)&&const DeepCollectionEquality().equals(other.startupTimingMs, _startupTimingMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId,deviceId,relayId,textureId,decodedWidth,decodedHeight,codec,generation,captureGeneration,paused,frameCount,decodedReceipts,snapshotReceipts,decoder,const DeepCollectionEquality().hash(_startupTimingMs));
}

@override
String toString() {
    return 'VideoOutputReceipt(sessionId: $sessionId, deviceId: $deviceId, relayId: $relayId, textureId: $textureId, decodedWidth: $decodedWidth, decodedHeight: $decodedHeight, codec: $codec, generation: $generation, captureGeneration: $captureGeneration, paused: $paused, frameCount: $frameCount, decodedReceipts: $decodedReceipts, snapshotReceipts: $snapshotReceipts, decoder: $decoder, startupTimingMs: $startupTimingMs)';
}


}

/// @nodoc
abstract mixin class _$VideoOutputReceiptCopyWith<$Res> implements $VideoOutputReceiptCopyWith<$Res> {
  factory _$VideoOutputReceiptCopyWith(_VideoOutputReceipt value, $Res Function(_VideoOutputReceipt) _then) = __$VideoOutputReceiptCopyWithImpl;
@override @useResult
$Res call({
 String sessionId, String deviceId, String relayId, int textureId, int decodedWidth, int decodedHeight, String codec, int generation, int captureGeneration, bool paused, int? frameCount, int decodedReceipts, int snapshotReceipts, VideoDecoderMetadata decoder, Map<String, int> startupTimingMs
});


@override $VideoDecoderMetadataCopyWith<$Res> get decoder;

}
/// @nodoc
class __$VideoOutputReceiptCopyWithImpl<$Res>
    implements _$VideoOutputReceiptCopyWith<$Res> {
  __$VideoOutputReceiptCopyWithImpl(this._self, this._then);

  final _VideoOutputReceipt _self;
  final $Res Function(_VideoOutputReceipt) _then;

/// Create a copy of VideoOutputReceipt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? deviceId = null,Object? relayId = null,Object? textureId = null,Object? decodedWidth = null,Object? decodedHeight = null,Object? codec = null,Object? generation = null,Object? captureGeneration = null,Object? paused = null,Object? frameCount = freezed,Object? decodedReceipts = null,Object? snapshotReceipts = null,Object? decoder = null,Object? startupTimingMs = null,}) {
  return _then(_VideoOutputReceipt(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,relayId: null == relayId ? _self.relayId : relayId // ignore: cast_nullable_to_non_nullable
as String,textureId: null == textureId ? _self.textureId : textureId // ignore: cast_nullable_to_non_nullable
as int,decodedWidth: null == decodedWidth ? _self.decodedWidth : decodedWidth // ignore: cast_nullable_to_non_nullable
as int,decodedHeight: null == decodedHeight ? _self.decodedHeight : decodedHeight // ignore: cast_nullable_to_non_nullable
as int,codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,captureGeneration: null == captureGeneration ? _self.captureGeneration : captureGeneration // ignore: cast_nullable_to_non_nullable
as int,paused: null == paused ? _self.paused : paused // ignore: cast_nullable_to_non_nullable
as bool,frameCount: freezed == frameCount ? _self.frameCount : frameCount // ignore: cast_nullable_to_non_nullable
as int?,decodedReceipts: null == decodedReceipts ? _self.decodedReceipts : decodedReceipts // ignore: cast_nullable_to_non_nullable
as int,snapshotReceipts: null == snapshotReceipts ? _self.snapshotReceipts : snapshotReceipts // ignore: cast_nullable_to_non_nullable
as int,decoder: null == decoder ? _self.decoder : decoder // ignore: cast_nullable_to_non_nullable
as VideoDecoderMetadata,startupTimingMs: null == startupTimingMs ? _self._startupTimingMs : startupTimingMs // ignore: cast_nullable_to_non_nullable
as Map<String, int>,
  ));
}

/// Create a copy of VideoOutputReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoDecoderMetadataCopyWith<$Res> get decoder {
  
  return $VideoDecoderMetadataCopyWith<$Res>(_self.decoder, (value) {
    return _then(_self.copyWith(decoder: value));
  });
}
}

/// @nodoc
mixin _$VideoPlaybackReceipt {

 VideoSessionSnapshot get session; VideoOutputReceipt get output;
/// Create a copy of VideoPlaybackReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoPlaybackReceiptCopyWith<VideoPlaybackReceipt> get copyWith => _$VideoPlaybackReceiptCopyWithImpl<VideoPlaybackReceipt>(this as VideoPlaybackReceipt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoPlaybackReceipt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoPlaybackReceipt&&(identical(other.session, _this.session) || other.session == _this.session)&&(identical(other.output, _this.output) || other.output == _this.output));
}


@override
int get hashCode {
  final _this = this as VideoPlaybackReceipt;
  return Object.hash(runtimeType,_this.session,_this.output);
}

@override
String toString() {
  final _this = this as VideoPlaybackReceipt;
  return 'VideoPlaybackReceipt(session: ${_this.session}, output: ${_this.output})';
}


}

/// @nodoc
abstract mixin class $VideoPlaybackReceiptCopyWith<$Res>  {
  factory $VideoPlaybackReceiptCopyWith(VideoPlaybackReceipt value, $Res Function(VideoPlaybackReceipt) _then) = _$VideoPlaybackReceiptCopyWithImpl;
@useResult
$Res call({
 VideoSessionSnapshot session, VideoOutputReceipt output
});


$VideoSessionSnapshotCopyWith<$Res> get session;$VideoOutputReceiptCopyWith<$Res> get output;

}
/// @nodoc
class _$VideoPlaybackReceiptCopyWithImpl<$Res>
    implements $VideoPlaybackReceiptCopyWith<$Res> {
  _$VideoPlaybackReceiptCopyWithImpl(this._self, this._then);

  final VideoPlaybackReceipt _self;
  final $Res Function(VideoPlaybackReceipt) _then;

/// Create a copy of VideoPlaybackReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? session = null,Object? output = null,}) {
  return _then(VideoPlaybackReceipt(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as VideoSessionSnapshot,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as VideoOutputReceipt,
  ));
}
/// Create a copy of VideoPlaybackReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoSessionSnapshotCopyWith<$Res> get session {
  
  return $VideoSessionSnapshotCopyWith<$Res>(_self.session, (value) {
    return _then(_self.copyWith(session: value));
  });
}/// Create a copy of VideoPlaybackReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoOutputReceiptCopyWith<$Res> get output {
  
  return $VideoOutputReceiptCopyWith<$Res>(_self.output, (value) {
    return _then(_self.copyWith(output: value));
  });
}
}


/// Adds pattern-matching-related methods to [VideoPlaybackReceipt].
extension VideoPlaybackReceiptPatterns on VideoPlaybackReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoPlaybackReceipt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoPlaybackReceipt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoPlaybackReceipt value)  $default,){
final _that = this;
switch (_that) {
case _VideoPlaybackReceipt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoPlaybackReceipt value)?  $default,){
final _that = this;
switch (_that) {
case _VideoPlaybackReceipt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( VideoSessionSnapshot session,  VideoOutputReceipt output)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoPlaybackReceipt() when $default != null:
return $default(_that.session,_that.output);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( VideoSessionSnapshot session,  VideoOutputReceipt output)  $default,) {final _that = this;
switch (_that) {
case _VideoPlaybackReceipt():
return $default(_that.session,_that.output);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( VideoSessionSnapshot session,  VideoOutputReceipt output)?  $default,) {final _that = this;
switch (_that) {
case _VideoPlaybackReceipt() when $default != null:
return $default(_that.session,_that.output);case _:
  return null;

}
}

}

/// @nodoc


class _VideoPlaybackReceipt extends VideoPlaybackReceipt {
  const _VideoPlaybackReceipt({required this.session, required this.output}): super._();
  

@override final  VideoSessionSnapshot session;
@override final  VideoOutputReceipt output;

/// Create a copy of VideoPlaybackReceipt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoPlaybackReceiptCopyWith<_VideoPlaybackReceipt> get copyWith => __$VideoPlaybackReceiptCopyWithImpl<_VideoPlaybackReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoPlaybackReceipt&&(identical(other.session, session) || other.session == session)&&(identical(other.output, output) || other.output == output));
}


@override
int get hashCode {
    return Object.hash(runtimeType,session,output);
}

@override
String toString() {
    return 'VideoPlaybackReceipt(session: $session, output: $output)';
}


}

/// @nodoc
abstract mixin class _$VideoPlaybackReceiptCopyWith<$Res> implements $VideoPlaybackReceiptCopyWith<$Res> {
  factory _$VideoPlaybackReceiptCopyWith(_VideoPlaybackReceipt value, $Res Function(_VideoPlaybackReceipt) _then) = __$VideoPlaybackReceiptCopyWithImpl;
@override @useResult
$Res call({
 VideoSessionSnapshot session, VideoOutputReceipt output
});


@override $VideoSessionSnapshotCopyWith<$Res> get session;@override $VideoOutputReceiptCopyWith<$Res> get output;

}
/// @nodoc
class __$VideoPlaybackReceiptCopyWithImpl<$Res>
    implements _$VideoPlaybackReceiptCopyWith<$Res> {
  __$VideoPlaybackReceiptCopyWithImpl(this._self, this._then);

  final _VideoPlaybackReceipt _self;
  final $Res Function(_VideoPlaybackReceipt) _then;

/// Create a copy of VideoPlaybackReceipt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? session = null,Object? output = null,}) {
  return _then(_VideoPlaybackReceipt(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as VideoSessionSnapshot,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as VideoOutputReceipt,
  ));
}

/// Create a copy of VideoPlaybackReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoSessionSnapshotCopyWith<$Res> get session {
  
  return $VideoSessionSnapshotCopyWith<$Res>(_self.session, (value) {
    return _then(_self.copyWith(session: value));
  });
}/// Create a copy of VideoPlaybackReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoOutputReceiptCopyWith<$Res> get output {
  
  return $VideoOutputReceiptCopyWith<$Res>(_self.output, (value) {
    return _then(_self.copyWith(output: value));
  });
}
}

// dart format on
