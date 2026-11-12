// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'video_quality.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VideoQualityPatch {

 VideoQualityPreset? get preset; int? get maxSize; int? get maxFps; int? get bitRate; VideoCodec? get codec; ({String? name,})? get encoder;
/// Create a copy of VideoQualityPatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoQualityPatchCopyWith<VideoQualityPatch> get copyWith => _$VideoQualityPatchCopyWithImpl<VideoQualityPatch>(this as VideoQualityPatch, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoQualityPatch;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoQualityPatch&&(identical(other.preset, _this.preset) || other.preset == _this.preset)&&(identical(other.maxSize, _this.maxSize) || other.maxSize == _this.maxSize)&&(identical(other.maxFps, _this.maxFps) || other.maxFps == _this.maxFps)&&(identical(other.bitRate, _this.bitRate) || other.bitRate == _this.bitRate)&&(identical(other.codec, _this.codec) || other.codec == _this.codec)&&(identical(other.encoder, _this.encoder) || other.encoder == _this.encoder));
}


@override
int get hashCode {
  final _this = this as VideoQualityPatch;
  return Object.hash(runtimeType,_this.preset,_this.maxSize,_this.maxFps,_this.bitRate,_this.codec,_this.encoder);
}

@override
String toString() {
  final _this = this as VideoQualityPatch;
  return 'VideoQualityPatch(preset: ${_this.preset}, maxSize: ${_this.maxSize}, maxFps: ${_this.maxFps}, bitRate: ${_this.bitRate}, codec: ${_this.codec}, encoder: ${_this.encoder})';
}


}

/// @nodoc
abstract mixin class $VideoQualityPatchCopyWith<$Res>  {
  factory $VideoQualityPatchCopyWith(VideoQualityPatch value, $Res Function(VideoQualityPatch) _then) = _$VideoQualityPatchCopyWithImpl;
@useResult
$Res call({
 VideoQualityPreset? preset, int? maxSize, int? maxFps, int? bitRate, VideoCodec? codec, ({String? name,})? encoder
});




}
/// @nodoc
class _$VideoQualityPatchCopyWithImpl<$Res>
    implements $VideoQualityPatchCopyWith<$Res> {
  _$VideoQualityPatchCopyWithImpl(this._self, this._then);

  final VideoQualityPatch _self;
  final $Res Function(VideoQualityPatch) _then;

/// Create a copy of VideoQualityPatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? preset = freezed,Object? maxSize = freezed,Object? maxFps = freezed,Object? bitRate = freezed,Object? codec = freezed,Object? encoder = freezed,}) {
  return _then(VideoQualityPatch(
preset: freezed == preset ? _self.preset : preset // ignore: cast_nullable_to_non_nullable
as VideoQualityPreset?,maxSize: freezed == maxSize ? _self.maxSize : maxSize // ignore: cast_nullable_to_non_nullable
as int?,maxFps: freezed == maxFps ? _self.maxFps : maxFps // ignore: cast_nullable_to_non_nullable
as int?,bitRate: freezed == bitRate ? _self.bitRate : bitRate // ignore: cast_nullable_to_non_nullable
as int?,codec: freezed == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec?,encoder: freezed == encoder ? _self.encoder : encoder // ignore: cast_nullable_to_non_nullable
as ({String? name,})?,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoQualityPatch].
extension VideoQualityPatchPatterns on VideoQualityPatch {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoQualityPatch value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoQualityPatch() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoQualityPatch value)  $default,){
final _that = this;
switch (_that) {
case _VideoQualityPatch():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoQualityPatch value)?  $default,){
final _that = this;
switch (_that) {
case _VideoQualityPatch() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( VideoQualityPreset? preset,  int? maxSize,  int? maxFps,  int? bitRate,  VideoCodec? codec,  ({String? name,})? encoder)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoQualityPatch() when $default != null:
return $default(_that.preset,_that.maxSize,_that.maxFps,_that.bitRate,_that.codec,_that.encoder);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( VideoQualityPreset? preset,  int? maxSize,  int? maxFps,  int? bitRate,  VideoCodec? codec,  ({String? name,})? encoder)  $default,) {final _that = this;
switch (_that) {
case _VideoQualityPatch():
return $default(_that.preset,_that.maxSize,_that.maxFps,_that.bitRate,_that.codec,_that.encoder);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( VideoQualityPreset? preset,  int? maxSize,  int? maxFps,  int? bitRate,  VideoCodec? codec,  ({String? name,})? encoder)?  $default,) {final _that = this;
switch (_that) {
case _VideoQualityPatch() when $default != null:
return $default(_that.preset,_that.maxSize,_that.maxFps,_that.bitRate,_that.codec,_that.encoder);case _:
  return null;

}
}

}

/// @nodoc


class _VideoQualityPatch implements VideoQualityPatch {
  const _VideoQualityPatch({this.preset, this.maxSize, this.maxFps, this.bitRate, this.codec, this.encoder});
  

@override final  VideoQualityPreset? preset;
@override final  int? maxSize;
@override final  int? maxFps;
@override final  int? bitRate;
@override final  VideoCodec? codec;
@override final  ({String? name,})? encoder;

/// Create a copy of VideoQualityPatch
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoQualityPatchCopyWith<_VideoQualityPatch> get copyWith => __$VideoQualityPatchCopyWithImpl<_VideoQualityPatch>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoQualityPatch&&(identical(other.preset, preset) || other.preset == preset)&&(identical(other.maxSize, maxSize) || other.maxSize == maxSize)&&(identical(other.maxFps, maxFps) || other.maxFps == maxFps)&&(identical(other.bitRate, bitRate) || other.bitRate == bitRate)&&(identical(other.codec, codec) || other.codec == codec)&&(identical(other.encoder, encoder) || other.encoder == encoder));
}


@override
int get hashCode {
    return Object.hash(runtimeType,preset,maxSize,maxFps,bitRate,codec,encoder);
}

@override
String toString() {
    return 'VideoQualityPatch(preset: $preset, maxSize: $maxSize, maxFps: $maxFps, bitRate: $bitRate, codec: $codec, encoder: $encoder)';
}


}

/// @nodoc
abstract mixin class _$VideoQualityPatchCopyWith<$Res> implements $VideoQualityPatchCopyWith<$Res> {
  factory _$VideoQualityPatchCopyWith(_VideoQualityPatch value, $Res Function(_VideoQualityPatch) _then) = __$VideoQualityPatchCopyWithImpl;
@override @useResult
$Res call({
 VideoQualityPreset? preset, int? maxSize, int? maxFps, int? bitRate, VideoCodec? codec, ({String? name,})? encoder
});




}
/// @nodoc
class __$VideoQualityPatchCopyWithImpl<$Res>
    implements _$VideoQualityPatchCopyWith<$Res> {
  __$VideoQualityPatchCopyWithImpl(this._self, this._then);

  final _VideoQualityPatch _self;
  final $Res Function(_VideoQualityPatch) _then;

/// Create a copy of VideoQualityPatch
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? preset = freezed,Object? maxSize = freezed,Object? maxFps = freezed,Object? bitRate = freezed,Object? codec = freezed,Object? encoder = freezed,}) {
  return _then(_VideoQualityPatch(
preset: freezed == preset ? _self.preset : preset // ignore: cast_nullable_to_non_nullable
as VideoQualityPreset?,maxSize: freezed == maxSize ? _self.maxSize : maxSize // ignore: cast_nullable_to_non_nullable
as int?,maxFps: freezed == maxFps ? _self.maxFps : maxFps // ignore: cast_nullable_to_non_nullable
as int?,bitRate: freezed == bitRate ? _self.bitRate : bitRate // ignore: cast_nullable_to_non_nullable
as int?,codec: freezed == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec?,encoder: freezed == encoder ? _self.encoder : encoder // ignore: cast_nullable_to_non_nullable
as ({String? name,})?,
  ));
}


}


/// @nodoc
mixin _$VideoQuality {

@JsonKey(name: 'qualityPreset') VideoQualityPreset? get preset; int get maxSize; int get maxFps;@JsonKey(name: 'videoBitRate') int get bitRate;@JsonKey(name: 'videoCodec') VideoCodec get codec;@JsonKey(name: 'videoEncoder', includeIfNull: true) String? get encoder;
/// Create a copy of VideoQuality
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoQualityCopyWith<VideoQuality> get copyWith => _$VideoQualityCopyWithImpl<VideoQuality>(this as VideoQuality, _$identity);

  /// Serializes this VideoQuality to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as VideoQuality;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoQuality&&(identical(other.preset, _this.preset) || other.preset == _this.preset)&&(identical(other.maxSize, _this.maxSize) || other.maxSize == _this.maxSize)&&(identical(other.maxFps, _this.maxFps) || other.maxFps == _this.maxFps)&&(identical(other.bitRate, _this.bitRate) || other.bitRate == _this.bitRate)&&(identical(other.codec, _this.codec) || other.codec == _this.codec)&&(identical(other.encoder, _this.encoder) || other.encoder == _this.encoder));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as VideoQuality;
  return Object.hash(runtimeType,_this.preset,_this.maxSize,_this.maxFps,_this.bitRate,_this.codec,_this.encoder);
}

@override
String toString() {
  final _this = this as VideoQuality;
  return 'VideoQuality(preset: ${_this.preset}, maxSize: ${_this.maxSize}, maxFps: ${_this.maxFps}, bitRate: ${_this.bitRate}, codec: ${_this.codec}, encoder: ${_this.encoder})';
}


}

/// @nodoc
abstract mixin class $VideoQualityCopyWith<$Res>  {
  factory $VideoQualityCopyWith(VideoQuality value, $Res Function(VideoQuality) _then) = _$VideoQualityCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'qualityPreset') VideoQualityPreset? preset, int maxSize, int maxFps,@JsonKey(name: 'videoBitRate') int bitRate,@JsonKey(name: 'videoCodec') VideoCodec codec,@JsonKey(name: 'videoEncoder', includeIfNull: true) String? encoder
});




}
/// @nodoc
class _$VideoQualityCopyWithImpl<$Res>
    implements $VideoQualityCopyWith<$Res> {
  _$VideoQualityCopyWithImpl(this._self, this._then);

  final VideoQuality _self;
  final $Res Function(VideoQuality) _then;

/// Create a copy of VideoQuality
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? preset = freezed,Object? maxSize = null,Object? maxFps = null,Object? bitRate = null,Object? codec = null,Object? encoder = freezed,}) {
  return _then(VideoQuality(
preset: freezed == preset ? _self.preset : preset // ignore: cast_nullable_to_non_nullable
as VideoQualityPreset?,maxSize: null == maxSize ? _self.maxSize : maxSize // ignore: cast_nullable_to_non_nullable
as int,maxFps: null == maxFps ? _self.maxFps : maxFps // ignore: cast_nullable_to_non_nullable
as int,bitRate: null == bitRate ? _self.bitRate : bitRate // ignore: cast_nullable_to_non_nullable
as int,codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec,encoder: freezed == encoder ? _self.encoder : encoder // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoQuality].
extension VideoQualityPatterns on VideoQuality {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoQuality value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoQuality() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoQuality value)  $default,){
final _that = this;
switch (_that) {
case _VideoQuality():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoQuality value)?  $default,){
final _that = this;
switch (_that) {
case _VideoQuality() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'qualityPreset')  VideoQualityPreset? preset,  int maxSize,  int maxFps, @JsonKey(name: 'videoBitRate')  int bitRate, @JsonKey(name: 'videoCodec')  VideoCodec codec, @JsonKey(name: 'videoEncoder', includeIfNull: true)  String? encoder)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoQuality() when $default != null:
return $default(_that.preset,_that.maxSize,_that.maxFps,_that.bitRate,_that.codec,_that.encoder);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'qualityPreset')  VideoQualityPreset? preset,  int maxSize,  int maxFps, @JsonKey(name: 'videoBitRate')  int bitRate, @JsonKey(name: 'videoCodec')  VideoCodec codec, @JsonKey(name: 'videoEncoder', includeIfNull: true)  String? encoder)  $default,) {final _that = this;
switch (_that) {
case _VideoQuality():
return $default(_that.preset,_that.maxSize,_that.maxFps,_that.bitRate,_that.codec,_that.encoder);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'qualityPreset')  VideoQualityPreset? preset,  int maxSize,  int maxFps, @JsonKey(name: 'videoBitRate')  int bitRate, @JsonKey(name: 'videoCodec')  VideoCodec codec, @JsonKey(name: 'videoEncoder', includeIfNull: true)  String? encoder)?  $default,) {final _that = this;
switch (_that) {
case _VideoQuality() when $default != null:
return $default(_that.preset,_that.maxSize,_that.maxFps,_that.bitRate,_that.codec,_that.encoder);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(includeIfNull: false)
class _VideoQuality extends VideoQuality {
  const _VideoQuality({@JsonKey(name: 'qualityPreset') this.preset, required this.maxSize, required this.maxFps, @JsonKey(name: 'videoBitRate') required this.bitRate, @JsonKey(name: 'videoCodec') required this.codec, @JsonKey(name: 'videoEncoder', includeIfNull: true) this.encoder}): super._();
  factory _VideoQuality.fromJson(Map<String, dynamic> json) => _$VideoQualityFromJson(json);

@override@JsonKey(name: 'qualityPreset') final  VideoQualityPreset? preset;
@override final  int maxSize;
@override final  int maxFps;
@override@JsonKey(name: 'videoBitRate') final  int bitRate;
@override@JsonKey(name: 'videoCodec') final  VideoCodec codec;
@override@JsonKey(name: 'videoEncoder', includeIfNull: true) final  String? encoder;

/// Create a copy of VideoQuality
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoQualityCopyWith<_VideoQuality> get copyWith => __$VideoQualityCopyWithImpl<_VideoQuality>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$VideoQualityToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoQuality&&(identical(other.preset, preset) || other.preset == preset)&&(identical(other.maxSize, maxSize) || other.maxSize == maxSize)&&(identical(other.maxFps, maxFps) || other.maxFps == maxFps)&&(identical(other.bitRate, bitRate) || other.bitRate == bitRate)&&(identical(other.codec, codec) || other.codec == codec)&&(identical(other.encoder, encoder) || other.encoder == encoder));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,preset,maxSize,maxFps,bitRate,codec,encoder);
}

@override
String toString() {
    return 'VideoQuality(preset: $preset, maxSize: $maxSize, maxFps: $maxFps, bitRate: $bitRate, codec: $codec, encoder: $encoder)';
}


}

/// @nodoc
abstract mixin class _$VideoQualityCopyWith<$Res> implements $VideoQualityCopyWith<$Res> {
  factory _$VideoQualityCopyWith(_VideoQuality value, $Res Function(_VideoQuality) _then) = __$VideoQualityCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'qualityPreset') VideoQualityPreset? preset, int maxSize, int maxFps,@JsonKey(name: 'videoBitRate') int bitRate,@JsonKey(name: 'videoCodec') VideoCodec codec,@JsonKey(name: 'videoEncoder', includeIfNull: true) String? encoder
});




}
/// @nodoc
class __$VideoQualityCopyWithImpl<$Res>
    implements _$VideoQualityCopyWith<$Res> {
  __$VideoQualityCopyWithImpl(this._self, this._then);

  final _VideoQuality _self;
  final $Res Function(_VideoQuality) _then;

/// Create a copy of VideoQuality
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? preset = freezed,Object? maxSize = null,Object? maxFps = null,Object? bitRate = null,Object? codec = null,Object? encoder = freezed,}) {
  return _then(_VideoQuality(
preset: freezed == preset ? _self.preset : preset // ignore: cast_nullable_to_non_nullable
as VideoQualityPreset?,maxSize: null == maxSize ? _self.maxSize : maxSize // ignore: cast_nullable_to_non_nullable
as int,maxFps: null == maxFps ? _self.maxFps : maxFps // ignore: cast_nullable_to_non_nullable
as int,bitRate: null == bitRate ? _self.bitRate : bitRate // ignore: cast_nullable_to_non_nullable
as int,codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec,encoder: freezed == encoder ? _self.encoder : encoder // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$VideoEncoder {

 VideoCodec get codec; String get name; bool? get hardware;
/// Create a copy of VideoEncoder
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoEncoderCopyWith<VideoEncoder> get copyWith => _$VideoEncoderCopyWithImpl<VideoEncoder>(this as VideoEncoder, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoEncoder;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoEncoder&&(identical(other.codec, _this.codec) || other.codec == _this.codec)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.hardware, _this.hardware) || other.hardware == _this.hardware));
}


@override
int get hashCode {
  final _this = this as VideoEncoder;
  return Object.hash(runtimeType,_this.codec,_this.name,_this.hardware);
}

@override
String toString() {
  final _this = this as VideoEncoder;
  return 'VideoEncoder(codec: ${_this.codec}, name: ${_this.name}, hardware: ${_this.hardware})';
}


}

/// @nodoc
abstract mixin class $VideoEncoderCopyWith<$Res>  {
  factory $VideoEncoderCopyWith(VideoEncoder value, $Res Function(VideoEncoder) _then) = _$VideoEncoderCopyWithImpl;
@useResult
$Res call({
 VideoCodec codec, String name, bool? hardware
});




}
/// @nodoc
class _$VideoEncoderCopyWithImpl<$Res>
    implements $VideoEncoderCopyWith<$Res> {
  _$VideoEncoderCopyWithImpl(this._self, this._then);

  final VideoEncoder _self;
  final $Res Function(VideoEncoder) _then;

/// Create a copy of VideoEncoder
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? codec = null,Object? name = null,Object? hardware = freezed,}) {
  return _then(VideoEncoder(
codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,hardware: freezed == hardware ? _self.hardware : hardware // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoEncoder].
extension VideoEncoderPatterns on VideoEncoder {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoEncoder value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoEncoder() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoEncoder value)  $default,){
final _that = this;
switch (_that) {
case _VideoEncoder():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoEncoder value)?  $default,){
final _that = this;
switch (_that) {
case _VideoEncoder() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( VideoCodec codec,  String name,  bool? hardware)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoEncoder() when $default != null:
return $default(_that.codec,_that.name,_that.hardware);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( VideoCodec codec,  String name,  bool? hardware)  $default,) {final _that = this;
switch (_that) {
case _VideoEncoder():
return $default(_that.codec,_that.name,_that.hardware);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( VideoCodec codec,  String name,  bool? hardware)?  $default,) {final _that = this;
switch (_that) {
case _VideoEncoder() when $default != null:
return $default(_that.codec,_that.name,_that.hardware);case _:
  return null;

}
}

}

/// @nodoc


class _VideoEncoder implements VideoEncoder {
  const _VideoEncoder({required this.codec, required this.name, this.hardware});
  

@override final  VideoCodec codec;
@override final  String name;
@override final  bool? hardware;

/// Create a copy of VideoEncoder
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoEncoderCopyWith<_VideoEncoder> get copyWith => __$VideoEncoderCopyWithImpl<_VideoEncoder>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoEncoder&&(identical(other.codec, codec) || other.codec == codec)&&(identical(other.name, name) || other.name == name)&&(identical(other.hardware, hardware) || other.hardware == hardware));
}


@override
int get hashCode {
    return Object.hash(runtimeType,codec,name,hardware);
}

@override
String toString() {
    return 'VideoEncoder(codec: $codec, name: $name, hardware: $hardware)';
}


}

/// @nodoc
abstract mixin class _$VideoEncoderCopyWith<$Res> implements $VideoEncoderCopyWith<$Res> {
  factory _$VideoEncoderCopyWith(_VideoEncoder value, $Res Function(_VideoEncoder) _then) = __$VideoEncoderCopyWithImpl;
@override @useResult
$Res call({
 VideoCodec codec, String name, bool? hardware
});




}
/// @nodoc
class __$VideoEncoderCopyWithImpl<$Res>
    implements _$VideoEncoderCopyWith<$Res> {
  __$VideoEncoderCopyWithImpl(this._self, this._then);

  final _VideoEncoder _self;
  final $Res Function(_VideoEncoder) _then;

/// Create a copy of VideoEncoder
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? codec = null,Object? name = null,Object? hardware = freezed,}) {
  return _then(_VideoEncoder(
codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,hardware: freezed == hardware ? _self.hardware : hardware // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

/// @nodoc
mixin _$VideoDecoderCapability {

 VideoCodec get codec; VideoDecoderEvidence get evidence; bool get canAttempt; String get reason;
/// Create a copy of VideoDecoderCapability
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoDecoderCapabilityCopyWith<VideoDecoderCapability> get copyWith => _$VideoDecoderCapabilityCopyWithImpl<VideoDecoderCapability>(this as VideoDecoderCapability, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoDecoderCapability;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoDecoderCapability&&(identical(other.codec, _this.codec) || other.codec == _this.codec)&&(identical(other.evidence, _this.evidence) || other.evidence == _this.evidence)&&(identical(other.canAttempt, _this.canAttempt) || other.canAttempt == _this.canAttempt)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}


@override
int get hashCode {
  final _this = this as VideoDecoderCapability;
  return Object.hash(runtimeType,_this.codec,_this.evidence,_this.canAttempt,_this.reason);
}

@override
String toString() {
  final _this = this as VideoDecoderCapability;
  return 'VideoDecoderCapability(codec: ${_this.codec}, evidence: ${_this.evidence}, canAttempt: ${_this.canAttempt}, reason: ${_this.reason})';
}


}

/// @nodoc
abstract mixin class $VideoDecoderCapabilityCopyWith<$Res>  {
  factory $VideoDecoderCapabilityCopyWith(VideoDecoderCapability value, $Res Function(VideoDecoderCapability) _then) = _$VideoDecoderCapabilityCopyWithImpl;
@useResult
$Res call({
 VideoCodec codec, VideoDecoderEvidence evidence, bool canAttempt, String reason
});




}
/// @nodoc
class _$VideoDecoderCapabilityCopyWithImpl<$Res>
    implements $VideoDecoderCapabilityCopyWith<$Res> {
  _$VideoDecoderCapabilityCopyWithImpl(this._self, this._then);

  final VideoDecoderCapability _self;
  final $Res Function(VideoDecoderCapability) _then;

/// Create a copy of VideoDecoderCapability
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? codec = null,Object? evidence = null,Object? canAttempt = null,Object? reason = null,}) {
  return _then(VideoDecoderCapability(
codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec,evidence: null == evidence ? _self.evidence : evidence // ignore: cast_nullable_to_non_nullable
as VideoDecoderEvidence,canAttempt: null == canAttempt ? _self.canAttempt : canAttempt // ignore: cast_nullable_to_non_nullable
as bool,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoDecoderCapability].
extension VideoDecoderCapabilityPatterns on VideoDecoderCapability {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoDecoderCapability value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoDecoderCapability() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoDecoderCapability value)  $default,){
final _that = this;
switch (_that) {
case _VideoDecoderCapability():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoDecoderCapability value)?  $default,){
final _that = this;
switch (_that) {
case _VideoDecoderCapability() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( VideoCodec codec,  VideoDecoderEvidence evidence,  bool canAttempt,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoDecoderCapability() when $default != null:
return $default(_that.codec,_that.evidence,_that.canAttempt,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( VideoCodec codec,  VideoDecoderEvidence evidence,  bool canAttempt,  String reason)  $default,) {final _that = this;
switch (_that) {
case _VideoDecoderCapability():
return $default(_that.codec,_that.evidence,_that.canAttempt,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( VideoCodec codec,  VideoDecoderEvidence evidence,  bool canAttempt,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _VideoDecoderCapability() when $default != null:
return $default(_that.codec,_that.evidence,_that.canAttempt,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _VideoDecoderCapability implements VideoDecoderCapability {
  const _VideoDecoderCapability({required this.codec, required this.evidence, required this.canAttempt, required this.reason});
  

@override final  VideoCodec codec;
@override final  VideoDecoderEvidence evidence;
@override final  bool canAttempt;
@override final  String reason;

/// Create a copy of VideoDecoderCapability
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoDecoderCapabilityCopyWith<_VideoDecoderCapability> get copyWith => __$VideoDecoderCapabilityCopyWithImpl<_VideoDecoderCapability>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoDecoderCapability&&(identical(other.codec, codec) || other.codec == codec)&&(identical(other.evidence, evidence) || other.evidence == evidence)&&(identical(other.canAttempt, canAttempt) || other.canAttempt == canAttempt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,codec,evidence,canAttempt,reason);
}

@override
String toString() {
    return 'VideoDecoderCapability(codec: $codec, evidence: $evidence, canAttempt: $canAttempt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$VideoDecoderCapabilityCopyWith<$Res> implements $VideoDecoderCapabilityCopyWith<$Res> {
  factory _$VideoDecoderCapabilityCopyWith(_VideoDecoderCapability value, $Res Function(_VideoDecoderCapability) _then) = __$VideoDecoderCapabilityCopyWithImpl;
@override @useResult
$Res call({
 VideoCodec codec, VideoDecoderEvidence evidence, bool canAttempt, String reason
});




}
/// @nodoc
class __$VideoDecoderCapabilityCopyWithImpl<$Res>
    implements _$VideoDecoderCapabilityCopyWith<$Res> {
  __$VideoDecoderCapabilityCopyWithImpl(this._self, this._then);

  final _VideoDecoderCapability _self;
  final $Res Function(_VideoDecoderCapability) _then;

/// Create a copy of VideoDecoderCapability
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? codec = null,Object? evidence = null,Object? canAttempt = null,Object? reason = null,}) {
  return _then(_VideoDecoderCapability(
codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec,evidence: null == evidence ? _self.evidence : evidence // ignore: cast_nullable_to_non_nullable
as VideoDecoderEvidence,canAttempt: null == canAttempt ? _self.canAttempt : canAttempt // ignore: cast_nullable_to_non_nullable
as bool,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$VideoCodecOption {

 VideoCodec get codec; List<VideoEncoder> get encoders; VideoDecoderCapability get decoder;
/// Create a copy of VideoCodecOption
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoCodecOptionCopyWith<VideoCodecOption> get copyWith => _$VideoCodecOptionCopyWithImpl<VideoCodecOption>(this as VideoCodecOption, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoCodecOption;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoCodecOption&&(identical(other.codec, _this.codec) || other.codec == _this.codec)&&const DeepCollectionEquality().equals(other.encoders, _this.encoders)&&(identical(other.decoder, _this.decoder) || other.decoder == _this.decoder));
}


@override
int get hashCode {
  final _this = this as VideoCodecOption;
  return Object.hash(runtimeType,_this.codec,const DeepCollectionEquality().hash(_this.encoders),_this.decoder);
}

@override
String toString() {
  final _this = this as VideoCodecOption;
  return 'VideoCodecOption(codec: ${_this.codec}, encoders: ${_this.encoders}, decoder: ${_this.decoder})';
}


}

/// @nodoc
abstract mixin class $VideoCodecOptionCopyWith<$Res>  {
  factory $VideoCodecOptionCopyWith(VideoCodecOption value, $Res Function(VideoCodecOption) _then) = _$VideoCodecOptionCopyWithImpl;
@useResult
$Res call({
 VideoCodec codec, List<VideoEncoder> encoders, VideoDecoderCapability decoder
});


$VideoDecoderCapabilityCopyWith<$Res> get decoder;

}
/// @nodoc
class _$VideoCodecOptionCopyWithImpl<$Res>
    implements $VideoCodecOptionCopyWith<$Res> {
  _$VideoCodecOptionCopyWithImpl(this._self, this._then);

  final VideoCodecOption _self;
  final $Res Function(VideoCodecOption) _then;

/// Create a copy of VideoCodecOption
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? codec = null,Object? encoders = null,Object? decoder = null,}) {
  return _then(VideoCodecOption(
codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec,encoders: null == encoders ? _self.encoders : encoders // ignore: cast_nullable_to_non_nullable
as List<VideoEncoder>,decoder: null == decoder ? _self.decoder : decoder // ignore: cast_nullable_to_non_nullable
as VideoDecoderCapability,
  ));
}
/// Create a copy of VideoCodecOption
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoDecoderCapabilityCopyWith<$Res> get decoder {
  
  return $VideoDecoderCapabilityCopyWith<$Res>(_self.decoder, (value) {
    return _then(_self.copyWith(decoder: value));
  });
}
}


/// Adds pattern-matching-related methods to [VideoCodecOption].
extension VideoCodecOptionPatterns on VideoCodecOption {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoCodecOption value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoCodecOption() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoCodecOption value)  $default,){
final _that = this;
switch (_that) {
case _VideoCodecOption():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoCodecOption value)?  $default,){
final _that = this;
switch (_that) {
case _VideoCodecOption() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( VideoCodec codec,  List<VideoEncoder> encoders,  VideoDecoderCapability decoder)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoCodecOption() when $default != null:
return $default(_that.codec,_that.encoders,_that.decoder);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( VideoCodec codec,  List<VideoEncoder> encoders,  VideoDecoderCapability decoder)  $default,) {final _that = this;
switch (_that) {
case _VideoCodecOption():
return $default(_that.codec,_that.encoders,_that.decoder);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( VideoCodec codec,  List<VideoEncoder> encoders,  VideoDecoderCapability decoder)?  $default,) {final _that = this;
switch (_that) {
case _VideoCodecOption() when $default != null:
return $default(_that.codec,_that.encoders,_that.decoder);case _:
  return null;

}
}

}

/// @nodoc


class _VideoCodecOption extends VideoCodecOption {
  const _VideoCodecOption({required this.codec, required  List<VideoEncoder> encoders, required this.decoder}): _encoders = encoders,super._();
  

@override final  VideoCodec codec;
 final  List<VideoEncoder> _encoders;
@override List<VideoEncoder> get encoders {
  if (_encoders is EqualUnmodifiableListView) return _encoders;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_encoders);
}

@override final  VideoDecoderCapability decoder;

/// Create a copy of VideoCodecOption
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoCodecOptionCopyWith<_VideoCodecOption> get copyWith => __$VideoCodecOptionCopyWithImpl<_VideoCodecOption>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoCodecOption&&(identical(other.codec, codec) || other.codec == codec)&&const DeepCollectionEquality().equals(other.encoders, _encoders)&&(identical(other.decoder, decoder) || other.decoder == decoder));
}


@override
int get hashCode {
    return Object.hash(runtimeType,codec,const DeepCollectionEquality().hash(_encoders),decoder);
}

@override
String toString() {
    return 'VideoCodecOption(codec: $codec, encoders: $encoders, decoder: $decoder)';
}


}

/// @nodoc
abstract mixin class _$VideoCodecOptionCopyWith<$Res> implements $VideoCodecOptionCopyWith<$Res> {
  factory _$VideoCodecOptionCopyWith(_VideoCodecOption value, $Res Function(_VideoCodecOption) _then) = __$VideoCodecOptionCopyWithImpl;
@override @useResult
$Res call({
 VideoCodec codec, List<VideoEncoder> encoders, VideoDecoderCapability decoder
});


@override $VideoDecoderCapabilityCopyWith<$Res> get decoder;

}
/// @nodoc
class __$VideoCodecOptionCopyWithImpl<$Res>
    implements _$VideoCodecOptionCopyWith<$Res> {
  __$VideoCodecOptionCopyWithImpl(this._self, this._then);

  final _VideoCodecOption _self;
  final $Res Function(_VideoCodecOption) _then;

/// Create a copy of VideoCodecOption
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? codec = null,Object? encoders = null,Object? decoder = null,}) {
  return _then(_VideoCodecOption(
codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as VideoCodec,encoders: null == encoders ? _self._encoders : encoders // ignore: cast_nullable_to_non_nullable
as List<VideoEncoder>,decoder: null == decoder ? _self.decoder : decoder // ignore: cast_nullable_to_non_nullable
as VideoDecoderCapability,
  ));
}

/// Create a copy of VideoCodecOption
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoDecoderCapabilityCopyWith<$Res> get decoder {
  
  return $VideoDecoderCapabilityCopyWith<$Res>(_self.decoder, (value) {
    return _then(_self.copyWith(decoder: value));
  });
}
}

/// @nodoc
mixin _$VideoQualityOptions {

 VideoQuality get current; List<VideoCodecOption> get codecs; List<SessionActivity> get activeSessions; List<VideoQualityPreset> get presets; List<int> get maxSizes; List<int> get frameRates; List<int> get bitRates;
/// Create a copy of VideoQualityOptions
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoQualityOptionsCopyWith<VideoQualityOptions> get copyWith => _$VideoQualityOptionsCopyWithImpl<VideoQualityOptions>(this as VideoQualityOptions, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoQualityOptions;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoQualityOptions&&(identical(other.current, _this.current) || other.current == _this.current)&&const DeepCollectionEquality().equals(other.codecs, _this.codecs)&&const DeepCollectionEquality().equals(other.activeSessions, _this.activeSessions)&&const DeepCollectionEquality().equals(other.presets, _this.presets)&&const DeepCollectionEquality().equals(other.maxSizes, _this.maxSizes)&&const DeepCollectionEquality().equals(other.frameRates, _this.frameRates)&&const DeepCollectionEquality().equals(other.bitRates, _this.bitRates));
}


@override
int get hashCode {
  final _this = this as VideoQualityOptions;
  return Object.hash(runtimeType,_this.current,const DeepCollectionEquality().hash(_this.codecs),const DeepCollectionEquality().hash(_this.activeSessions),const DeepCollectionEquality().hash(_this.presets),const DeepCollectionEquality().hash(_this.maxSizes),const DeepCollectionEquality().hash(_this.frameRates),const DeepCollectionEquality().hash(_this.bitRates));
}

@override
String toString() {
  final _this = this as VideoQualityOptions;
  return 'VideoQualityOptions(current: ${_this.current}, codecs: ${_this.codecs}, activeSessions: ${_this.activeSessions}, presets: ${_this.presets}, maxSizes: ${_this.maxSizes}, frameRates: ${_this.frameRates}, bitRates: ${_this.bitRates})';
}


}

/// @nodoc
abstract mixin class $VideoQualityOptionsCopyWith<$Res>  {
  factory $VideoQualityOptionsCopyWith(VideoQualityOptions value, $Res Function(VideoQualityOptions) _then) = _$VideoQualityOptionsCopyWithImpl;
@useResult
$Res call({
 VideoQuality current, List<VideoCodecOption> codecs, List<SessionActivity> activeSessions, List<VideoQualityPreset> presets, List<int> maxSizes, List<int> frameRates, List<int> bitRates
});


$VideoQualityCopyWith<$Res> get current;

}
/// @nodoc
class _$VideoQualityOptionsCopyWithImpl<$Res>
    implements $VideoQualityOptionsCopyWith<$Res> {
  _$VideoQualityOptionsCopyWithImpl(this._self, this._then);

  final VideoQualityOptions _self;
  final $Res Function(VideoQualityOptions) _then;

/// Create a copy of VideoQualityOptions
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? current = null,Object? codecs = null,Object? activeSessions = null,Object? presets = null,Object? maxSizes = null,Object? frameRates = null,Object? bitRates = null,}) {
  return _then(VideoQualityOptions(
current: null == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as VideoQuality,codecs: null == codecs ? _self.codecs : codecs // ignore: cast_nullable_to_non_nullable
as List<VideoCodecOption>,activeSessions: null == activeSessions ? _self.activeSessions : activeSessions // ignore: cast_nullable_to_non_nullable
as List<SessionActivity>,presets: null == presets ? _self.presets : presets // ignore: cast_nullable_to_non_nullable
as List<VideoQualityPreset>,maxSizes: null == maxSizes ? _self.maxSizes : maxSizes // ignore: cast_nullable_to_non_nullable
as List<int>,frameRates: null == frameRates ? _self.frameRates : frameRates // ignore: cast_nullable_to_non_nullable
as List<int>,bitRates: null == bitRates ? _self.bitRates : bitRates // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of VideoQualityOptions
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoQualityCopyWith<$Res> get current {
  
  return $VideoQualityCopyWith<$Res>(_self.current, (value) {
    return _then(_self.copyWith(current: value));
  });
}
}


/// Adds pattern-matching-related methods to [VideoQualityOptions].
extension VideoQualityOptionsPatterns on VideoQualityOptions {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoQualityOptions value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoQualityOptions() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoQualityOptions value)  $default,){
final _that = this;
switch (_that) {
case _VideoQualityOptions():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoQualityOptions value)?  $default,){
final _that = this;
switch (_that) {
case _VideoQualityOptions() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( VideoQuality current,  List<VideoCodecOption> codecs,  List<SessionActivity> activeSessions,  List<VideoQualityPreset> presets,  List<int> maxSizes,  List<int> frameRates,  List<int> bitRates)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoQualityOptions() when $default != null:
return $default(_that.current,_that.codecs,_that.activeSessions,_that.presets,_that.maxSizes,_that.frameRates,_that.bitRates);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( VideoQuality current,  List<VideoCodecOption> codecs,  List<SessionActivity> activeSessions,  List<VideoQualityPreset> presets,  List<int> maxSizes,  List<int> frameRates,  List<int> bitRates)  $default,) {final _that = this;
switch (_that) {
case _VideoQualityOptions():
return $default(_that.current,_that.codecs,_that.activeSessions,_that.presets,_that.maxSizes,_that.frameRates,_that.bitRates);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( VideoQuality current,  List<VideoCodecOption> codecs,  List<SessionActivity> activeSessions,  List<VideoQualityPreset> presets,  List<int> maxSizes,  List<int> frameRates,  List<int> bitRates)?  $default,) {final _that = this;
switch (_that) {
case _VideoQualityOptions() when $default != null:
return $default(_that.current,_that.codecs,_that.activeSessions,_that.presets,_that.maxSizes,_that.frameRates,_that.bitRates);case _:
  return null;

}
}

}

/// @nodoc


class _VideoQualityOptions implements VideoQualityOptions {
  const _VideoQualityOptions({required this.current, required  List<VideoCodecOption> codecs, required  List<SessionActivity> activeSessions,  List<VideoQualityPreset> presets = const [VideoQualityPreset.smooth, VideoQualityPreset.balanced, VideoQualityPreset.clear],  List<int> maxSizes = const [720, 1080, 1280, 1920],  List<int> frameRates = const [30, 60],  List<int> bitRates = const [2000000, 4000000, 8000000, 12000000]}): _codecs = codecs,_activeSessions = activeSessions,_presets = presets,_maxSizes = maxSizes,_frameRates = frameRates,_bitRates = bitRates;
  

@override final  VideoQuality current;
 final  List<VideoCodecOption> _codecs;
@override List<VideoCodecOption> get codecs {
  if (_codecs is EqualUnmodifiableListView) return _codecs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_codecs);
}

 final  List<SessionActivity> _activeSessions;
@override List<SessionActivity> get activeSessions {
  if (_activeSessions is EqualUnmodifiableListView) return _activeSessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activeSessions);
}

 final  List<VideoQualityPreset> _presets;
@override@JsonKey() List<VideoQualityPreset> get presets {
  if (_presets is EqualUnmodifiableListView) return _presets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_presets);
}

 final  List<int> _maxSizes;
@override@JsonKey() List<int> get maxSizes {
  if (_maxSizes is EqualUnmodifiableListView) return _maxSizes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_maxSizes);
}

 final  List<int> _frameRates;
@override@JsonKey() List<int> get frameRates {
  if (_frameRates is EqualUnmodifiableListView) return _frameRates;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_frameRates);
}

 final  List<int> _bitRates;
@override@JsonKey() List<int> get bitRates {
  if (_bitRates is EqualUnmodifiableListView) return _bitRates;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_bitRates);
}


/// Create a copy of VideoQualityOptions
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoQualityOptionsCopyWith<_VideoQualityOptions> get copyWith => __$VideoQualityOptionsCopyWithImpl<_VideoQualityOptions>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoQualityOptions&&(identical(other.current, current) || other.current == current)&&const DeepCollectionEquality().equals(other.codecs, _codecs)&&const DeepCollectionEquality().equals(other.activeSessions, _activeSessions)&&const DeepCollectionEquality().equals(other.presets, _presets)&&const DeepCollectionEquality().equals(other.maxSizes, _maxSizes)&&const DeepCollectionEquality().equals(other.frameRates, _frameRates)&&const DeepCollectionEquality().equals(other.bitRates, _bitRates));
}


@override
int get hashCode {
    return Object.hash(runtimeType,current,const DeepCollectionEquality().hash(_codecs),const DeepCollectionEquality().hash(_activeSessions),const DeepCollectionEquality().hash(_presets),const DeepCollectionEquality().hash(_maxSizes),const DeepCollectionEquality().hash(_frameRates),const DeepCollectionEquality().hash(_bitRates));
}

@override
String toString() {
    return 'VideoQualityOptions(current: $current, codecs: $codecs, activeSessions: $activeSessions, presets: $presets, maxSizes: $maxSizes, frameRates: $frameRates, bitRates: $bitRates)';
}


}

/// @nodoc
abstract mixin class _$VideoQualityOptionsCopyWith<$Res> implements $VideoQualityOptionsCopyWith<$Res> {
  factory _$VideoQualityOptionsCopyWith(_VideoQualityOptions value, $Res Function(_VideoQualityOptions) _then) = __$VideoQualityOptionsCopyWithImpl;
@override @useResult
$Res call({
 VideoQuality current, List<VideoCodecOption> codecs, List<SessionActivity> activeSessions, List<VideoQualityPreset> presets, List<int> maxSizes, List<int> frameRates, List<int> bitRates
});


@override $VideoQualityCopyWith<$Res> get current;

}
/// @nodoc
class __$VideoQualityOptionsCopyWithImpl<$Res>
    implements _$VideoQualityOptionsCopyWith<$Res> {
  __$VideoQualityOptionsCopyWithImpl(this._self, this._then);

  final _VideoQualityOptions _self;
  final $Res Function(_VideoQualityOptions) _then;

/// Create a copy of VideoQualityOptions
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? current = null,Object? codecs = null,Object? activeSessions = null,Object? presets = null,Object? maxSizes = null,Object? frameRates = null,Object? bitRates = null,}) {
  return _then(_VideoQualityOptions(
current: null == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as VideoQuality,codecs: null == codecs ? _self._codecs : codecs // ignore: cast_nullable_to_non_nullable
as List<VideoCodecOption>,activeSessions: null == activeSessions ? _self._activeSessions : activeSessions // ignore: cast_nullable_to_non_nullable
as List<SessionActivity>,presets: null == presets ? _self._presets : presets // ignore: cast_nullable_to_non_nullable
as List<VideoQualityPreset>,maxSizes: null == maxSizes ? _self._maxSizes : maxSizes // ignore: cast_nullable_to_non_nullable
as List<int>,frameRates: null == frameRates ? _self._frameRates : frameRates // ignore: cast_nullable_to_non_nullable
as List<int>,bitRates: null == bitRates ? _self._bitRates : bitRates // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}

/// Create a copy of VideoQualityOptions
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoQualityCopyWith<$Res> get current {
  
  return $VideoQualityCopyWith<$Res>(_self.current, (value) {
    return _then(_self.copyWith(current: value));
  });
}
}

/// @nodoc
mixin _$VideoQualityFailure {

 String? get sessionId; String get name; String get reason; String? get code;
/// Create a copy of VideoQualityFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoQualityFailureCopyWith<VideoQualityFailure> get copyWith => _$VideoQualityFailureCopyWithImpl<VideoQualityFailure>(this as VideoQualityFailure, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoQualityFailure;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoQualityFailure&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.code, _this.code) || other.code == _this.code));
}


@override
int get hashCode {
  final _this = this as VideoQualityFailure;
  return Object.hash(runtimeType,_this.sessionId,_this.name,_this.reason,_this.code);
}

@override
String toString() {
  final _this = this as VideoQualityFailure;
  return 'VideoQualityFailure(sessionId: ${_this.sessionId}, name: ${_this.name}, reason: ${_this.reason}, code: ${_this.code})';
}


}

/// @nodoc
abstract mixin class $VideoQualityFailureCopyWith<$Res>  {
  factory $VideoQualityFailureCopyWith(VideoQualityFailure value, $Res Function(VideoQualityFailure) _then) = _$VideoQualityFailureCopyWithImpl;
@useResult
$Res call({
 String? sessionId, String name, String reason, String? code
});




}
/// @nodoc
class _$VideoQualityFailureCopyWithImpl<$Res>
    implements $VideoQualityFailureCopyWith<$Res> {
  _$VideoQualityFailureCopyWithImpl(this._self, this._then);

  final VideoQualityFailure _self;
  final $Res Function(VideoQualityFailure) _then;

/// Create a copy of VideoQualityFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = freezed,Object? name = null,Object? reason = null,Object? code = freezed,}) {
  return _then(VideoQualityFailure(
sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoQualityFailure].
extension VideoQualityFailurePatterns on VideoQualityFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoQualityFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoQualityFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoQualityFailure value)  $default,){
final _that = this;
switch (_that) {
case _VideoQualityFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoQualityFailure value)?  $default,){
final _that = this;
switch (_that) {
case _VideoQualityFailure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? sessionId,  String name,  String reason,  String? code)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoQualityFailure() when $default != null:
return $default(_that.sessionId,_that.name,_that.reason,_that.code);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? sessionId,  String name,  String reason,  String? code)  $default,) {final _that = this;
switch (_that) {
case _VideoQualityFailure():
return $default(_that.sessionId,_that.name,_that.reason,_that.code);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? sessionId,  String name,  String reason,  String? code)?  $default,) {final _that = this;
switch (_that) {
case _VideoQualityFailure() when $default != null:
return $default(_that.sessionId,_that.name,_that.reason,_that.code);case _:
  return null;

}
}

}

/// @nodoc


class _VideoQualityFailure implements VideoQualityFailure {
  const _VideoQualityFailure({this.sessionId, required this.name, required this.reason, this.code});
  

@override final  String? sessionId;
@override final  String name;
@override final  String reason;
@override final  String? code;

/// Create a copy of VideoQualityFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoQualityFailureCopyWith<_VideoQualityFailure> get copyWith => __$VideoQualityFailureCopyWithImpl<_VideoQualityFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoQualityFailure&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.name, name) || other.name == name)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId,name,reason,code);
}

@override
String toString() {
    return 'VideoQualityFailure(sessionId: $sessionId, name: $name, reason: $reason, code: $code)';
}


}

/// @nodoc
abstract mixin class _$VideoQualityFailureCopyWith<$Res> implements $VideoQualityFailureCopyWith<$Res> {
  factory _$VideoQualityFailureCopyWith(_VideoQualityFailure value, $Res Function(_VideoQualityFailure) _then) = __$VideoQualityFailureCopyWithImpl;
@override @useResult
$Res call({
 String? sessionId, String name, String reason, String? code
});




}
/// @nodoc
class __$VideoQualityFailureCopyWithImpl<$Res>
    implements _$VideoQualityFailureCopyWith<$Res> {
  __$VideoQualityFailureCopyWithImpl(this._self, this._then);

  final _VideoQualityFailure _self;
  final $Res Function(_VideoQualityFailure) _then;

/// Create a copy of VideoQualityFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = freezed,Object? name = null,Object? reason = null,Object? code = freezed,}) {
  return _then(_VideoQualityFailure(
sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$VideoQualityApplication {

 VideoQuality get current; bool get appliedToAll; List<SessionActivity> get appliedSessions; List<VideoQualityFailure> get failures; List<String> get skippedSessions; String get reason;
/// Create a copy of VideoQualityApplication
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoQualityApplicationCopyWith<VideoQualityApplication> get copyWith => _$VideoQualityApplicationCopyWithImpl<VideoQualityApplication>(this as VideoQualityApplication, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoQualityApplication;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoQualityApplication&&(identical(other.current, _this.current) || other.current == _this.current)&&(identical(other.appliedToAll, _this.appliedToAll) || other.appliedToAll == _this.appliedToAll)&&const DeepCollectionEquality().equals(other.appliedSessions, _this.appliedSessions)&&const DeepCollectionEquality().equals(other.failures, _this.failures)&&const DeepCollectionEquality().equals(other.skippedSessions, _this.skippedSessions)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}


@override
int get hashCode {
  final _this = this as VideoQualityApplication;
  return Object.hash(runtimeType,_this.current,_this.appliedToAll,const DeepCollectionEquality().hash(_this.appliedSessions),const DeepCollectionEquality().hash(_this.failures),const DeepCollectionEquality().hash(_this.skippedSessions),_this.reason);
}

@override
String toString() {
  final _this = this as VideoQualityApplication;
  return 'VideoQualityApplication(current: ${_this.current}, appliedToAll: ${_this.appliedToAll}, appliedSessions: ${_this.appliedSessions}, failures: ${_this.failures}, skippedSessions: ${_this.skippedSessions}, reason: ${_this.reason})';
}


}

/// @nodoc
abstract mixin class $VideoQualityApplicationCopyWith<$Res>  {
  factory $VideoQualityApplicationCopyWith(VideoQualityApplication value, $Res Function(VideoQualityApplication) _then) = _$VideoQualityApplicationCopyWithImpl;
@useResult
$Res call({
 VideoQuality current, bool appliedToAll, List<SessionActivity> appliedSessions, List<VideoQualityFailure> failures, List<String> skippedSessions, String reason
});


$VideoQualityCopyWith<$Res> get current;

}
/// @nodoc
class _$VideoQualityApplicationCopyWithImpl<$Res>
    implements $VideoQualityApplicationCopyWith<$Res> {
  _$VideoQualityApplicationCopyWithImpl(this._self, this._then);

  final VideoQualityApplication _self;
  final $Res Function(VideoQualityApplication) _then;

/// Create a copy of VideoQualityApplication
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? current = null,Object? appliedToAll = null,Object? appliedSessions = null,Object? failures = null,Object? skippedSessions = null,Object? reason = null,}) {
  return _then(VideoQualityApplication(
current: null == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as VideoQuality,appliedToAll: null == appliedToAll ? _self.appliedToAll : appliedToAll // ignore: cast_nullable_to_non_nullable
as bool,appliedSessions: null == appliedSessions ? _self.appliedSessions : appliedSessions // ignore: cast_nullable_to_non_nullable
as List<SessionActivity>,failures: null == failures ? _self.failures : failures // ignore: cast_nullable_to_non_nullable
as List<VideoQualityFailure>,skippedSessions: null == skippedSessions ? _self.skippedSessions : skippedSessions // ignore: cast_nullable_to_non_nullable
as List<String>,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of VideoQualityApplication
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoQualityCopyWith<$Res> get current {
  
  return $VideoQualityCopyWith<$Res>(_self.current, (value) {
    return _then(_self.copyWith(current: value));
  });
}
}


/// Adds pattern-matching-related methods to [VideoQualityApplication].
extension VideoQualityApplicationPatterns on VideoQualityApplication {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoQualityApplication value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoQualityApplication() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoQualityApplication value)  $default,){
final _that = this;
switch (_that) {
case _VideoQualityApplication():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoQualityApplication value)?  $default,){
final _that = this;
switch (_that) {
case _VideoQualityApplication() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( VideoQuality current,  bool appliedToAll,  List<SessionActivity> appliedSessions,  List<VideoQualityFailure> failures,  List<String> skippedSessions,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoQualityApplication() when $default != null:
return $default(_that.current,_that.appliedToAll,_that.appliedSessions,_that.failures,_that.skippedSessions,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( VideoQuality current,  bool appliedToAll,  List<SessionActivity> appliedSessions,  List<VideoQualityFailure> failures,  List<String> skippedSessions,  String reason)  $default,) {final _that = this;
switch (_that) {
case _VideoQualityApplication():
return $default(_that.current,_that.appliedToAll,_that.appliedSessions,_that.failures,_that.skippedSessions,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( VideoQuality current,  bool appliedToAll,  List<SessionActivity> appliedSessions,  List<VideoQualityFailure> failures,  List<String> skippedSessions,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _VideoQualityApplication() when $default != null:
return $default(_that.current,_that.appliedToAll,_that.appliedSessions,_that.failures,_that.skippedSessions,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _VideoQualityApplication implements VideoQualityApplication {
  const _VideoQualityApplication({required this.current, required this.appliedToAll, required  List<SessionActivity> appliedSessions, required  List<VideoQualityFailure> failures, required  List<String> skippedSessions, required this.reason}): _appliedSessions = appliedSessions,_failures = failures,_skippedSessions = skippedSessions;
  

@override final  VideoQuality current;
@override final  bool appliedToAll;
 final  List<SessionActivity> _appliedSessions;
@override List<SessionActivity> get appliedSessions {
  if (_appliedSessions is EqualUnmodifiableListView) return _appliedSessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_appliedSessions);
}

 final  List<VideoQualityFailure> _failures;
@override List<VideoQualityFailure> get failures {
  if (_failures is EqualUnmodifiableListView) return _failures;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_failures);
}

 final  List<String> _skippedSessions;
@override List<String> get skippedSessions {
  if (_skippedSessions is EqualUnmodifiableListView) return _skippedSessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_skippedSessions);
}

@override final  String reason;

/// Create a copy of VideoQualityApplication
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoQualityApplicationCopyWith<_VideoQualityApplication> get copyWith => __$VideoQualityApplicationCopyWithImpl<_VideoQualityApplication>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoQualityApplication&&(identical(other.current, current) || other.current == current)&&(identical(other.appliedToAll, appliedToAll) || other.appliedToAll == appliedToAll)&&const DeepCollectionEquality().equals(other.appliedSessions, _appliedSessions)&&const DeepCollectionEquality().equals(other.failures, _failures)&&const DeepCollectionEquality().equals(other.skippedSessions, _skippedSessions)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,current,appliedToAll,const DeepCollectionEquality().hash(_appliedSessions),const DeepCollectionEquality().hash(_failures),const DeepCollectionEquality().hash(_skippedSessions),reason);
}

@override
String toString() {
    return 'VideoQualityApplication(current: $current, appliedToAll: $appliedToAll, appliedSessions: $appliedSessions, failures: $failures, skippedSessions: $skippedSessions, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$VideoQualityApplicationCopyWith<$Res> implements $VideoQualityApplicationCopyWith<$Res> {
  factory _$VideoQualityApplicationCopyWith(_VideoQualityApplication value, $Res Function(_VideoQualityApplication) _then) = __$VideoQualityApplicationCopyWithImpl;
@override @useResult
$Res call({
 VideoQuality current, bool appliedToAll, List<SessionActivity> appliedSessions, List<VideoQualityFailure> failures, List<String> skippedSessions, String reason
});


@override $VideoQualityCopyWith<$Res> get current;

}
/// @nodoc
class __$VideoQualityApplicationCopyWithImpl<$Res>
    implements _$VideoQualityApplicationCopyWith<$Res> {
  __$VideoQualityApplicationCopyWithImpl(this._self, this._then);

  final _VideoQualityApplication _self;
  final $Res Function(_VideoQualityApplication) _then;

/// Create a copy of VideoQualityApplication
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? current = null,Object? appliedToAll = null,Object? appliedSessions = null,Object? failures = null,Object? skippedSessions = null,Object? reason = null,}) {
  return _then(_VideoQualityApplication(
current: null == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as VideoQuality,appliedToAll: null == appliedToAll ? _self.appliedToAll : appliedToAll // ignore: cast_nullable_to_non_nullable
as bool,appliedSessions: null == appliedSessions ? _self._appliedSessions : appliedSessions // ignore: cast_nullable_to_non_nullable
as List<SessionActivity>,failures: null == failures ? _self._failures : failures // ignore: cast_nullable_to_non_nullable
as List<VideoQualityFailure>,skippedSessions: null == skippedSessions ? _self._skippedSessions : skippedSessions // ignore: cast_nullable_to_non_nullable
as List<String>,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of VideoQualityApplication
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoQualityCopyWith<$Res> get current {
  
  return $VideoQualityCopyWith<$Res>(_self.current, (value) {
    return _then(_self.copyWith(current: value));
  });
}
}

/// @nodoc
mixin _$VideoQualityState {

 bool get loading; VideoQualityOptions? get data; Object? get error; int get revision;
/// Create a copy of VideoQualityState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoQualityStateCopyWith<VideoQualityState> get copyWith => _$VideoQualityStateCopyWithImpl<VideoQualityState>(this as VideoQualityState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoQualityState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoQualityState&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.data, _this.data) || other.data == _this.data)&&const DeepCollectionEquality().equals(other.error, _this.error)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as VideoQualityState;
  return Object.hash(runtimeType,_this.loading,_this.data,const DeepCollectionEquality().hash(_this.error),_this.revision);
}

@override
String toString() {
  final _this = this as VideoQualityState;
  return 'VideoQualityState(loading: ${_this.loading}, data: ${_this.data}, error: ${_this.error}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $VideoQualityStateCopyWith<$Res>  {
  factory $VideoQualityStateCopyWith(VideoQualityState value, $Res Function(VideoQualityState) _then) = _$VideoQualityStateCopyWithImpl;
@useResult
$Res call({
 bool loading, VideoQualityOptions? data, Object? error, int revision
});


$VideoQualityOptionsCopyWith<$Res>? get data;

}
/// @nodoc
class _$VideoQualityStateCopyWithImpl<$Res>
    implements $VideoQualityStateCopyWith<$Res> {
  _$VideoQualityStateCopyWithImpl(this._self, this._then);

  final VideoQualityState _self;
  final $Res Function(VideoQualityState) _then;

/// Create a copy of VideoQualityState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? loading = null,Object? data = freezed,Object? error = freezed,Object? revision = null,}) {
  return _then(VideoQualityState(
loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as VideoQualityOptions?,error: freezed == error ? _self.error : error ,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of VideoQualityState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoQualityOptionsCopyWith<$Res>? get data {
    if (_self.data == null) {
    return null;
  }

  return $VideoQualityOptionsCopyWith<$Res>(_self.data!, (value) {
    return _then(_self.copyWith(data: value));
  });
}
}


/// Adds pattern-matching-related methods to [VideoQualityState].
extension VideoQualityStatePatterns on VideoQualityState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoQualityState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoQualityState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoQualityState value)  $default,){
final _that = this;
switch (_that) {
case _VideoQualityState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoQualityState value)?  $default,){
final _that = this;
switch (_that) {
case _VideoQualityState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool loading,  VideoQualityOptions? data,  Object? error,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoQualityState() when $default != null:
return $default(_that.loading,_that.data,_that.error,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool loading,  VideoQualityOptions? data,  Object? error,  int revision)  $default,) {final _that = this;
switch (_that) {
case _VideoQualityState():
return $default(_that.loading,_that.data,_that.error,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool loading,  VideoQualityOptions? data,  Object? error,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _VideoQualityState() when $default != null:
return $default(_that.loading,_that.data,_that.error,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _VideoQualityState implements VideoQualityState {
  const _VideoQualityState({this.loading = true, this.data, this.error, this.revision = 0});
  

@override@JsonKey() final  bool loading;
@override final  VideoQualityOptions? data;
@override final  Object? error;
@override@JsonKey() final  int revision;

/// Create a copy of VideoQualityState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoQualityStateCopyWith<_VideoQualityState> get copyWith => __$VideoQualityStateCopyWithImpl<_VideoQualityState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoQualityState&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.data, data) || other.data == data)&&const DeepCollectionEquality().equals(other.error, error)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,loading,data,const DeepCollectionEquality().hash(error),revision);
}

@override
String toString() {
    return 'VideoQualityState(loading: $loading, data: $data, error: $error, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$VideoQualityStateCopyWith<$Res> implements $VideoQualityStateCopyWith<$Res> {
  factory _$VideoQualityStateCopyWith(_VideoQualityState value, $Res Function(_VideoQualityState) _then) = __$VideoQualityStateCopyWithImpl;
@override @useResult
$Res call({
 bool loading, VideoQualityOptions? data, Object? error, int revision
});


@override $VideoQualityOptionsCopyWith<$Res>? get data;

}
/// @nodoc
class __$VideoQualityStateCopyWithImpl<$Res>
    implements _$VideoQualityStateCopyWith<$Res> {
  __$VideoQualityStateCopyWithImpl(this._self, this._then);

  final _VideoQualityState _self;
  final $Res Function(_VideoQualityState) _then;

/// Create a copy of VideoQualityState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? loading = null,Object? data = freezed,Object? error = freezed,Object? revision = null,}) {
  return _then(_VideoQualityState(
loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as VideoQualityOptions?,error: freezed == error ? _self.error : error ,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of VideoQualityState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoQualityOptionsCopyWith<$Res>? get data {
    if (_self.data == null) {
    return null;
  }

  return $VideoQualityOptionsCopyWith<$Res>(_self.data!, (value) {
    return _then(_self.copyWith(data: value));
  });
}
}

// dart format on
