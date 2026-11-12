// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_audio_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DeviceAudioTarget {

 String get deviceId; String? get sourceId;
/// Create a copy of DeviceAudioTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceAudioTargetCopyWith<DeviceAudioTarget> get copyWith => _$DeviceAudioTargetCopyWithImpl<DeviceAudioTarget>(this as DeviceAudioTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceAudioTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceAudioTarget&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.sourceId, _this.sourceId) || other.sourceId == _this.sourceId));
}


@override
int get hashCode {
  final _this = this as DeviceAudioTarget;
  return Object.hash(runtimeType,_this.deviceId,_this.sourceId);
}

@override
String toString() {
  final _this = this as DeviceAudioTarget;
  return 'DeviceAudioTarget(deviceId: ${_this.deviceId}, sourceId: ${_this.sourceId})';
}


}

/// @nodoc
abstract mixin class $DeviceAudioTargetCopyWith<$Res>  {
  factory $DeviceAudioTargetCopyWith(DeviceAudioTarget value, $Res Function(DeviceAudioTarget) _then) = _$DeviceAudioTargetCopyWithImpl;
@useResult
$Res call({
 String deviceId, String? sourceId
});




}
/// @nodoc
class _$DeviceAudioTargetCopyWithImpl<$Res>
    implements $DeviceAudioTargetCopyWith<$Res> {
  _$DeviceAudioTargetCopyWithImpl(this._self, this._then);

  final DeviceAudioTarget _self;
  final $Res Function(DeviceAudioTarget) _then;

/// Create a copy of DeviceAudioTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? sourceId = freezed,}) {
  return _then(DeviceAudioTarget(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,sourceId: freezed == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceAudioTarget].
extension DeviceAudioTargetPatterns on DeviceAudioTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceAudioTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceAudioTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceAudioTarget value)  $default,){
final _that = this;
switch (_that) {
case _DeviceAudioTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceAudioTarget value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceAudioTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  String? sourceId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceAudioTarget() when $default != null:
return $default(_that.deviceId,_that.sourceId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  String? sourceId)  $default,) {final _that = this;
switch (_that) {
case _DeviceAudioTarget():
return $default(_that.deviceId,_that.sourceId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  String? sourceId)?  $default,) {final _that = this;
switch (_that) {
case _DeviceAudioTarget() when $default != null:
return $default(_that.deviceId,_that.sourceId);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceAudioTarget implements DeviceAudioTarget {
  const _DeviceAudioTarget({required this.deviceId, this.sourceId});
  

@override final  String deviceId;
@override final  String? sourceId;

/// Create a copy of DeviceAudioTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceAudioTargetCopyWith<_DeviceAudioTarget> get copyWith => __$DeviceAudioTargetCopyWithImpl<_DeviceAudioTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceAudioTarget&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,sourceId);
}

@override
String toString() {
    return 'DeviceAudioTarget(deviceId: $deviceId, sourceId: $sourceId)';
}


}

/// @nodoc
abstract mixin class _$DeviceAudioTargetCopyWith<$Res> implements $DeviceAudioTargetCopyWith<$Res> {
  factory _$DeviceAudioTargetCopyWith(_DeviceAudioTarget value, $Res Function(_DeviceAudioTarget) _then) = __$DeviceAudioTargetCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, String? sourceId
});




}
/// @nodoc
class __$DeviceAudioTargetCopyWithImpl<$Res>
    implements _$DeviceAudioTargetCopyWith<$Res> {
  __$DeviceAudioTargetCopyWithImpl(this._self, this._then);

  final _DeviceAudioTarget _self;
  final $Res Function(_DeviceAudioTarget) _then;

/// Create a copy of DeviceAudioTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? sourceId = freezed,}) {
  return _then(_DeviceAudioTarget(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,sourceId: freezed == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AudioCleanupFailure {

 String get code; String get reason;
/// Create a copy of AudioCleanupFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AudioCleanupFailureCopyWith<AudioCleanupFailure> get copyWith => _$AudioCleanupFailureCopyWithImpl<AudioCleanupFailure>(this as AudioCleanupFailure, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AudioCleanupFailure;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AudioCleanupFailure&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}


@override
int get hashCode {
  final _this = this as AudioCleanupFailure;
  return Object.hash(runtimeType,_this.code,_this.reason);
}

@override
String toString() {
  final _this = this as AudioCleanupFailure;
  return 'AudioCleanupFailure(code: ${_this.code}, reason: ${_this.reason})';
}


}

/// @nodoc
abstract mixin class $AudioCleanupFailureCopyWith<$Res>  {
  factory $AudioCleanupFailureCopyWith(AudioCleanupFailure value, $Res Function(AudioCleanupFailure) _then) = _$AudioCleanupFailureCopyWithImpl;
@useResult
$Res call({
 String code, String reason
});




}
/// @nodoc
class _$AudioCleanupFailureCopyWithImpl<$Res>
    implements $AudioCleanupFailureCopyWith<$Res> {
  _$AudioCleanupFailureCopyWithImpl(this._self, this._then);

  final AudioCleanupFailure _self;
  final $Res Function(AudioCleanupFailure) _then;

/// Create a copy of AudioCleanupFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? reason = null,}) {
  return _then(AudioCleanupFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AudioCleanupFailure].
extension AudioCleanupFailurePatterns on AudioCleanupFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AudioCleanupFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AudioCleanupFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AudioCleanupFailure value)  $default,){
final _that = this;
switch (_that) {
case _AudioCleanupFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AudioCleanupFailure value)?  $default,){
final _that = this;
switch (_that) {
case _AudioCleanupFailure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String code,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AudioCleanupFailure() when $default != null:
return $default(_that.code,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String code,  String reason)  $default,) {final _that = this;
switch (_that) {
case _AudioCleanupFailure():
return $default(_that.code,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String code,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _AudioCleanupFailure() when $default != null:
return $default(_that.code,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _AudioCleanupFailure implements AudioCleanupFailure {
  const _AudioCleanupFailure({required this.code, required this.reason});
  

@override final  String code;
@override final  String reason;

/// Create a copy of AudioCleanupFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AudioCleanupFailureCopyWith<_AudioCleanupFailure> get copyWith => __$AudioCleanupFailureCopyWithImpl<_AudioCleanupFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AudioCleanupFailure&&(identical(other.code, code) || other.code == code)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,reason);
}

@override
String toString() {
    return 'AudioCleanupFailure(code: $code, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$AudioCleanupFailureCopyWith<$Res> implements $AudioCleanupFailureCopyWith<$Res> {
  factory _$AudioCleanupFailureCopyWith(_AudioCleanupFailure value, $Res Function(_AudioCleanupFailure) _then) = __$AudioCleanupFailureCopyWithImpl;
@override @useResult
$Res call({
 String code, String reason
});




}
/// @nodoc
class __$AudioCleanupFailureCopyWithImpl<$Res>
    implements _$AudioCleanupFailureCopyWith<$Res> {
  __$AudioCleanupFailureCopyWithImpl(this._self, this._then);

  final _AudioCleanupFailure _self;
  final $Res Function(_AudioCleanupFailure) _then;

/// Create a copy of AudioCleanupFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? reason = null,}) {
  return _then(_AudioCleanupFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$DeviceAudioSnapshot {

 String get sourceId; String get deviceId; int get generation; String get name; DeviceAudioStatus get status; int get createdAt; String get codec; int get sampleRate; int get channels; int get bytesPerSample; double get volume; bool get muted; bool get nativeAttached; bool get playbackVerified; bool get speakerSamplesVerified; bool get audibleContentVerified; String get captureSource; bool get callAudioSupported; bool get remoteExitVerified; bool get captureReady; bool get mediaReady; bool get localReleased; bool get existing; String? get audioSourceId; String? get captureRef; int? get nativeGeneration; int? get processId; int? get processStarted; String? get backend; int? get nativeRevision; int? get bytesWritten; bool? get presentationOnly; bool? get manualPaused; bool? get focusPaused; bool? get backgroundPaused; bool? get requiresUserResume; String? get focusSignal; String? get reason; AudioCleanupFailure? get cleanupError;
/// Create a copy of DeviceAudioSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceAudioSnapshotCopyWith<DeviceAudioSnapshot> get copyWith => _$DeviceAudioSnapshotCopyWithImpl<DeviceAudioSnapshot>(this as DeviceAudioSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceAudioSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceAudioSnapshot&&(identical(other.sourceId, _this.sourceId) || other.sourceId == _this.sourceId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.codec, _this.codec) || other.codec == _this.codec)&&(identical(other.sampleRate, _this.sampleRate) || other.sampleRate == _this.sampleRate)&&(identical(other.channels, _this.channels) || other.channels == _this.channels)&&(identical(other.bytesPerSample, _this.bytesPerSample) || other.bytesPerSample == _this.bytesPerSample)&&(identical(other.volume, _this.volume) || other.volume == _this.volume)&&(identical(other.muted, _this.muted) || other.muted == _this.muted)&&(identical(other.nativeAttached, _this.nativeAttached) || other.nativeAttached == _this.nativeAttached)&&(identical(other.playbackVerified, _this.playbackVerified) || other.playbackVerified == _this.playbackVerified)&&(identical(other.speakerSamplesVerified, _this.speakerSamplesVerified) || other.speakerSamplesVerified == _this.speakerSamplesVerified)&&(identical(other.audibleContentVerified, _this.audibleContentVerified) || other.audibleContentVerified == _this.audibleContentVerified)&&(identical(other.captureSource, _this.captureSource) || other.captureSource == _this.captureSource)&&(identical(other.callAudioSupported, _this.callAudioSupported) || other.callAudioSupported == _this.callAudioSupported)&&(identical(other.remoteExitVerified, _this.remoteExitVerified) || other.remoteExitVerified == _this.remoteExitVerified)&&(identical(other.captureReady, _this.captureReady) || other.captureReady == _this.captureReady)&&(identical(other.mediaReady, _this.mediaReady) || other.mediaReady == _this.mediaReady)&&(identical(other.localReleased, _this.localReleased) || other.localReleased == _this.localReleased)&&(identical(other.existing, _this.existing) || other.existing == _this.existing)&&(identical(other.audioSourceId, _this.audioSourceId) || other.audioSourceId == _this.audioSourceId)&&(identical(other.captureRef, _this.captureRef) || other.captureRef == _this.captureRef)&&(identical(other.nativeGeneration, _this.nativeGeneration) || other.nativeGeneration == _this.nativeGeneration)&&(identical(other.processId, _this.processId) || other.processId == _this.processId)&&(identical(other.processStarted, _this.processStarted) || other.processStarted == _this.processStarted)&&(identical(other.backend, _this.backend) || other.backend == _this.backend)&&(identical(other.nativeRevision, _this.nativeRevision) || other.nativeRevision == _this.nativeRevision)&&(identical(other.bytesWritten, _this.bytesWritten) || other.bytesWritten == _this.bytesWritten)&&(identical(other.presentationOnly, _this.presentationOnly) || other.presentationOnly == _this.presentationOnly)&&(identical(other.manualPaused, _this.manualPaused) || other.manualPaused == _this.manualPaused)&&(identical(other.focusPaused, _this.focusPaused) || other.focusPaused == _this.focusPaused)&&(identical(other.backgroundPaused, _this.backgroundPaused) || other.backgroundPaused == _this.backgroundPaused)&&(identical(other.requiresUserResume, _this.requiresUserResume) || other.requiresUserResume == _this.requiresUserResume)&&(identical(other.focusSignal, _this.focusSignal) || other.focusSignal == _this.focusSignal)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.cleanupError, _this.cleanupError) || other.cleanupError == _this.cleanupError));
}


@override
int get hashCode {
  final _this = this as DeviceAudioSnapshot;
  return Object.hashAll([runtimeType,_this.sourceId,_this.deviceId,_this.generation,_this.name,_this.status,_this.createdAt,_this.codec,_this.sampleRate,_this.channels,_this.bytesPerSample,_this.volume,_this.muted,_this.nativeAttached,_this.playbackVerified,_this.speakerSamplesVerified,_this.audibleContentVerified,_this.captureSource,_this.callAudioSupported,_this.remoteExitVerified,_this.captureReady,_this.mediaReady,_this.localReleased,_this.existing,_this.audioSourceId,_this.captureRef,_this.nativeGeneration,_this.processId,_this.processStarted,_this.backend,_this.nativeRevision,_this.bytesWritten,_this.presentationOnly,_this.manualPaused,_this.focusPaused,_this.backgroundPaused,_this.requiresUserResume,_this.focusSignal,_this.reason,_this.cleanupError]);
}

@override
String toString() {
  final _this = this as DeviceAudioSnapshot;
  return 'DeviceAudioSnapshot(sourceId: ${_this.sourceId}, deviceId: ${_this.deviceId}, generation: ${_this.generation}, name: ${_this.name}, status: ${_this.status}, createdAt: ${_this.createdAt}, codec: ${_this.codec}, sampleRate: ${_this.sampleRate}, channels: ${_this.channels}, bytesPerSample: ${_this.bytesPerSample}, volume: ${_this.volume}, muted: ${_this.muted}, nativeAttached: ${_this.nativeAttached}, playbackVerified: ${_this.playbackVerified}, speakerSamplesVerified: ${_this.speakerSamplesVerified}, audibleContentVerified: ${_this.audibleContentVerified}, captureSource: ${_this.captureSource}, callAudioSupported: ${_this.callAudioSupported}, remoteExitVerified: ${_this.remoteExitVerified}, captureReady: ${_this.captureReady}, mediaReady: ${_this.mediaReady}, localReleased: ${_this.localReleased}, existing: ${_this.existing}, audioSourceId: ${_this.audioSourceId}, captureRef: ${_this.captureRef}, nativeGeneration: ${_this.nativeGeneration}, processId: ${_this.processId}, processStarted: ${_this.processStarted}, backend: ${_this.backend}, nativeRevision: ${_this.nativeRevision}, bytesWritten: ${_this.bytesWritten}, presentationOnly: ${_this.presentationOnly}, manualPaused: ${_this.manualPaused}, focusPaused: ${_this.focusPaused}, backgroundPaused: ${_this.backgroundPaused}, requiresUserResume: ${_this.requiresUserResume}, focusSignal: ${_this.focusSignal}, reason: ${_this.reason}, cleanupError: ${_this.cleanupError})';
}


}

/// @nodoc
abstract mixin class $DeviceAudioSnapshotCopyWith<$Res>  {
  factory $DeviceAudioSnapshotCopyWith(DeviceAudioSnapshot value, $Res Function(DeviceAudioSnapshot) _then) = _$DeviceAudioSnapshotCopyWithImpl;
@useResult
$Res call({
 String sourceId, String deviceId, int generation, String name, DeviceAudioStatus status, int createdAt, String codec, int sampleRate, int channels, int bytesPerSample, double volume, bool muted, bool nativeAttached, bool playbackVerified, bool speakerSamplesVerified, bool audibleContentVerified, String captureSource, bool callAudioSupported, bool remoteExitVerified, bool captureReady, bool mediaReady, bool localReleased, bool existing, String? audioSourceId, String? captureRef, int? nativeGeneration, int? processId, int? processStarted, String? backend, int? nativeRevision, int? bytesWritten, bool? presentationOnly, bool? manualPaused, bool? focusPaused, bool? backgroundPaused, bool? requiresUserResume, String? focusSignal, String? reason, AudioCleanupFailure? cleanupError
});


$AudioCleanupFailureCopyWith<$Res>? get cleanupError;

}
/// @nodoc
class _$DeviceAudioSnapshotCopyWithImpl<$Res>
    implements $DeviceAudioSnapshotCopyWith<$Res> {
  _$DeviceAudioSnapshotCopyWithImpl(this._self, this._then);

  final DeviceAudioSnapshot _self;
  final $Res Function(DeviceAudioSnapshot) _then;

/// Create a copy of DeviceAudioSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sourceId = null,Object? deviceId = null,Object? generation = null,Object? name = null,Object? status = null,Object? createdAt = null,Object? codec = null,Object? sampleRate = null,Object? channels = null,Object? bytesPerSample = null,Object? volume = null,Object? muted = null,Object? nativeAttached = null,Object? playbackVerified = null,Object? speakerSamplesVerified = null,Object? audibleContentVerified = null,Object? captureSource = null,Object? callAudioSupported = null,Object? remoteExitVerified = null,Object? captureReady = null,Object? mediaReady = null,Object? localReleased = null,Object? existing = null,Object? audioSourceId = freezed,Object? captureRef = freezed,Object? nativeGeneration = freezed,Object? processId = freezed,Object? processStarted = freezed,Object? backend = freezed,Object? nativeRevision = freezed,Object? bytesWritten = freezed,Object? presentationOnly = freezed,Object? manualPaused = freezed,Object? focusPaused = freezed,Object? backgroundPaused = freezed,Object? requiresUserResume = freezed,Object? focusSignal = freezed,Object? reason = freezed,Object? cleanupError = freezed,}) {
  return _then(DeviceAudioSnapshot(
sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceAudioStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as String,sampleRate: null == sampleRate ? _self.sampleRate : sampleRate // ignore: cast_nullable_to_non_nullable
as int,channels: null == channels ? _self.channels : channels // ignore: cast_nullable_to_non_nullable
as int,bytesPerSample: null == bytesPerSample ? _self.bytesPerSample : bytesPerSample // ignore: cast_nullable_to_non_nullable
as int,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,nativeAttached: null == nativeAttached ? _self.nativeAttached : nativeAttached // ignore: cast_nullable_to_non_nullable
as bool,playbackVerified: null == playbackVerified ? _self.playbackVerified : playbackVerified // ignore: cast_nullable_to_non_nullable
as bool,speakerSamplesVerified: null == speakerSamplesVerified ? _self.speakerSamplesVerified : speakerSamplesVerified // ignore: cast_nullable_to_non_nullable
as bool,audibleContentVerified: null == audibleContentVerified ? _self.audibleContentVerified : audibleContentVerified // ignore: cast_nullable_to_non_nullable
as bool,captureSource: null == captureSource ? _self.captureSource : captureSource // ignore: cast_nullable_to_non_nullable
as String,callAudioSupported: null == callAudioSupported ? _self.callAudioSupported : callAudioSupported // ignore: cast_nullable_to_non_nullable
as bool,remoteExitVerified: null == remoteExitVerified ? _self.remoteExitVerified : remoteExitVerified // ignore: cast_nullable_to_non_nullable
as bool,captureReady: null == captureReady ? _self.captureReady : captureReady // ignore: cast_nullable_to_non_nullable
as bool,mediaReady: null == mediaReady ? _self.mediaReady : mediaReady // ignore: cast_nullable_to_non_nullable
as bool,localReleased: null == localReleased ? _self.localReleased : localReleased // ignore: cast_nullable_to_non_nullable
as bool,existing: null == existing ? _self.existing : existing // ignore: cast_nullable_to_non_nullable
as bool,audioSourceId: freezed == audioSourceId ? _self.audioSourceId : audioSourceId // ignore: cast_nullable_to_non_nullable
as String?,captureRef: freezed == captureRef ? _self.captureRef : captureRef // ignore: cast_nullable_to_non_nullable
as String?,nativeGeneration: freezed == nativeGeneration ? _self.nativeGeneration : nativeGeneration // ignore: cast_nullable_to_non_nullable
as int?,processId: freezed == processId ? _self.processId : processId // ignore: cast_nullable_to_non_nullable
as int?,processStarted: freezed == processStarted ? _self.processStarted : processStarted // ignore: cast_nullable_to_non_nullable
as int?,backend: freezed == backend ? _self.backend : backend // ignore: cast_nullable_to_non_nullable
as String?,nativeRevision: freezed == nativeRevision ? _self.nativeRevision : nativeRevision // ignore: cast_nullable_to_non_nullable
as int?,bytesWritten: freezed == bytesWritten ? _self.bytesWritten : bytesWritten // ignore: cast_nullable_to_non_nullable
as int?,presentationOnly: freezed == presentationOnly ? _self.presentationOnly : presentationOnly // ignore: cast_nullable_to_non_nullable
as bool?,manualPaused: freezed == manualPaused ? _self.manualPaused : manualPaused // ignore: cast_nullable_to_non_nullable
as bool?,focusPaused: freezed == focusPaused ? _self.focusPaused : focusPaused // ignore: cast_nullable_to_non_nullable
as bool?,backgroundPaused: freezed == backgroundPaused ? _self.backgroundPaused : backgroundPaused // ignore: cast_nullable_to_non_nullable
as bool?,requiresUserResume: freezed == requiresUserResume ? _self.requiresUserResume : requiresUserResume // ignore: cast_nullable_to_non_nullable
as bool?,focusSignal: freezed == focusSignal ? _self.focusSignal : focusSignal // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,cleanupError: freezed == cleanupError ? _self.cleanupError : cleanupError // ignore: cast_nullable_to_non_nullable
as AudioCleanupFailure?,
  ));
}
/// Create a copy of DeviceAudioSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AudioCleanupFailureCopyWith<$Res>? get cleanupError {
    if (_self.cleanupError == null) {
    return null;
  }

  return $AudioCleanupFailureCopyWith<$Res>(_self.cleanupError!, (value) {
    return _then(_self.copyWith(cleanupError: value));
  });
}
}


/// Adds pattern-matching-related methods to [DeviceAudioSnapshot].
extension DeviceAudioSnapshotPatterns on DeviceAudioSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceAudioSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceAudioSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceAudioSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _DeviceAudioSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceAudioSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceAudioSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sourceId,  String deviceId,  int generation,  String name,  DeviceAudioStatus status,  int createdAt,  String codec,  int sampleRate,  int channels,  int bytesPerSample,  double volume,  bool muted,  bool nativeAttached,  bool playbackVerified,  bool speakerSamplesVerified,  bool audibleContentVerified,  String captureSource,  bool callAudioSupported,  bool remoteExitVerified,  bool captureReady,  bool mediaReady,  bool localReleased,  bool existing,  String? audioSourceId,  String? captureRef,  int? nativeGeneration,  int? processId,  int? processStarted,  String? backend,  int? nativeRevision,  int? bytesWritten,  bool? presentationOnly,  bool? manualPaused,  bool? focusPaused,  bool? backgroundPaused,  bool? requiresUserResume,  String? focusSignal,  String? reason,  AudioCleanupFailure? cleanupError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceAudioSnapshot() when $default != null:
return $default(_that.sourceId,_that.deviceId,_that.generation,_that.name,_that.status,_that.createdAt,_that.codec,_that.sampleRate,_that.channels,_that.bytesPerSample,_that.volume,_that.muted,_that.nativeAttached,_that.playbackVerified,_that.speakerSamplesVerified,_that.audibleContentVerified,_that.captureSource,_that.callAudioSupported,_that.remoteExitVerified,_that.captureReady,_that.mediaReady,_that.localReleased,_that.existing,_that.audioSourceId,_that.captureRef,_that.nativeGeneration,_that.processId,_that.processStarted,_that.backend,_that.nativeRevision,_that.bytesWritten,_that.presentationOnly,_that.manualPaused,_that.focusPaused,_that.backgroundPaused,_that.requiresUserResume,_that.focusSignal,_that.reason,_that.cleanupError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sourceId,  String deviceId,  int generation,  String name,  DeviceAudioStatus status,  int createdAt,  String codec,  int sampleRate,  int channels,  int bytesPerSample,  double volume,  bool muted,  bool nativeAttached,  bool playbackVerified,  bool speakerSamplesVerified,  bool audibleContentVerified,  String captureSource,  bool callAudioSupported,  bool remoteExitVerified,  bool captureReady,  bool mediaReady,  bool localReleased,  bool existing,  String? audioSourceId,  String? captureRef,  int? nativeGeneration,  int? processId,  int? processStarted,  String? backend,  int? nativeRevision,  int? bytesWritten,  bool? presentationOnly,  bool? manualPaused,  bool? focusPaused,  bool? backgroundPaused,  bool? requiresUserResume,  String? focusSignal,  String? reason,  AudioCleanupFailure? cleanupError)  $default,) {final _that = this;
switch (_that) {
case _DeviceAudioSnapshot():
return $default(_that.sourceId,_that.deviceId,_that.generation,_that.name,_that.status,_that.createdAt,_that.codec,_that.sampleRate,_that.channels,_that.bytesPerSample,_that.volume,_that.muted,_that.nativeAttached,_that.playbackVerified,_that.speakerSamplesVerified,_that.audibleContentVerified,_that.captureSource,_that.callAudioSupported,_that.remoteExitVerified,_that.captureReady,_that.mediaReady,_that.localReleased,_that.existing,_that.audioSourceId,_that.captureRef,_that.nativeGeneration,_that.processId,_that.processStarted,_that.backend,_that.nativeRevision,_that.bytesWritten,_that.presentationOnly,_that.manualPaused,_that.focusPaused,_that.backgroundPaused,_that.requiresUserResume,_that.focusSignal,_that.reason,_that.cleanupError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sourceId,  String deviceId,  int generation,  String name,  DeviceAudioStatus status,  int createdAt,  String codec,  int sampleRate,  int channels,  int bytesPerSample,  double volume,  bool muted,  bool nativeAttached,  bool playbackVerified,  bool speakerSamplesVerified,  bool audibleContentVerified,  String captureSource,  bool callAudioSupported,  bool remoteExitVerified,  bool captureReady,  bool mediaReady,  bool localReleased,  bool existing,  String? audioSourceId,  String? captureRef,  int? nativeGeneration,  int? processId,  int? processStarted,  String? backend,  int? nativeRevision,  int? bytesWritten,  bool? presentationOnly,  bool? manualPaused,  bool? focusPaused,  bool? backgroundPaused,  bool? requiresUserResume,  String? focusSignal,  String? reason,  AudioCleanupFailure? cleanupError)?  $default,) {final _that = this;
switch (_that) {
case _DeviceAudioSnapshot() when $default != null:
return $default(_that.sourceId,_that.deviceId,_that.generation,_that.name,_that.status,_that.createdAt,_that.codec,_that.sampleRate,_that.channels,_that.bytesPerSample,_that.volume,_that.muted,_that.nativeAttached,_that.playbackVerified,_that.speakerSamplesVerified,_that.audibleContentVerified,_that.captureSource,_that.callAudioSupported,_that.remoteExitVerified,_that.captureReady,_that.mediaReady,_that.localReleased,_that.existing,_that.audioSourceId,_that.captureRef,_that.nativeGeneration,_that.processId,_that.processStarted,_that.backend,_that.nativeRevision,_that.bytesWritten,_that.presentationOnly,_that.manualPaused,_that.focusPaused,_that.backgroundPaused,_that.requiresUserResume,_that.focusSignal,_that.reason,_that.cleanupError);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceAudioSnapshot implements DeviceAudioSnapshot {
  const _DeviceAudioSnapshot({required this.sourceId, required this.deviceId, required this.generation, required this.name, required this.status, required this.createdAt, this.codec = 'pcm_s16le', this.sampleRate = 48000, this.channels = 2, this.bytesPerSample = 2, this.volume = 1, this.muted = false, this.nativeAttached = false, this.playbackVerified = false, this.speakerSamplesVerified = false, this.audibleContentVerified = false, this.captureSource = 'output', this.callAudioSupported = false, this.remoteExitVerified = false, this.captureReady = false, this.mediaReady = false, this.localReleased = false, this.existing = false, this.audioSourceId, this.captureRef, this.nativeGeneration, this.processId, this.processStarted, this.backend, this.nativeRevision, this.bytesWritten, this.presentationOnly, this.manualPaused, this.focusPaused, this.backgroundPaused, this.requiresUserResume, this.focusSignal, this.reason, this.cleanupError});
  

@override final  String sourceId;
@override final  String deviceId;
@override final  int generation;
@override final  String name;
@override final  DeviceAudioStatus status;
@override final  int createdAt;
@override@JsonKey() final  String codec;
@override@JsonKey() final  int sampleRate;
@override@JsonKey() final  int channels;
@override@JsonKey() final  int bytesPerSample;
@override@JsonKey() final  double volume;
@override@JsonKey() final  bool muted;
@override@JsonKey() final  bool nativeAttached;
@override@JsonKey() final  bool playbackVerified;
@override@JsonKey() final  bool speakerSamplesVerified;
@override@JsonKey() final  bool audibleContentVerified;
@override@JsonKey() final  String captureSource;
@override@JsonKey() final  bool callAudioSupported;
@override@JsonKey() final  bool remoteExitVerified;
@override@JsonKey() final  bool captureReady;
@override@JsonKey() final  bool mediaReady;
@override@JsonKey() final  bool localReleased;
@override@JsonKey() final  bool existing;
@override final  String? audioSourceId;
@override final  String? captureRef;
@override final  int? nativeGeneration;
@override final  int? processId;
@override final  int? processStarted;
@override final  String? backend;
@override final  int? nativeRevision;
@override final  int? bytesWritten;
@override final  bool? presentationOnly;
@override final  bool? manualPaused;
@override final  bool? focusPaused;
@override final  bool? backgroundPaused;
@override final  bool? requiresUserResume;
@override final  String? focusSignal;
@override final  String? reason;
@override final  AudioCleanupFailure? cleanupError;

/// Create a copy of DeviceAudioSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceAudioSnapshotCopyWith<_DeviceAudioSnapshot> get copyWith => __$DeviceAudioSnapshotCopyWithImpl<_DeviceAudioSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceAudioSnapshot&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.name, name) || other.name == name)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.codec, codec) || other.codec == codec)&&(identical(other.sampleRate, sampleRate) || other.sampleRate == sampleRate)&&(identical(other.channels, channels) || other.channels == channels)&&(identical(other.bytesPerSample, bytesPerSample) || other.bytesPerSample == bytesPerSample)&&(identical(other.volume, volume) || other.volume == volume)&&(identical(other.muted, muted) || other.muted == muted)&&(identical(other.nativeAttached, nativeAttached) || other.nativeAttached == nativeAttached)&&(identical(other.playbackVerified, playbackVerified) || other.playbackVerified == playbackVerified)&&(identical(other.speakerSamplesVerified, speakerSamplesVerified) || other.speakerSamplesVerified == speakerSamplesVerified)&&(identical(other.audibleContentVerified, audibleContentVerified) || other.audibleContentVerified == audibleContentVerified)&&(identical(other.captureSource, captureSource) || other.captureSource == captureSource)&&(identical(other.callAudioSupported, callAudioSupported) || other.callAudioSupported == callAudioSupported)&&(identical(other.remoteExitVerified, remoteExitVerified) || other.remoteExitVerified == remoteExitVerified)&&(identical(other.captureReady, captureReady) || other.captureReady == captureReady)&&(identical(other.mediaReady, mediaReady) || other.mediaReady == mediaReady)&&(identical(other.localReleased, localReleased) || other.localReleased == localReleased)&&(identical(other.existing, existing) || other.existing == existing)&&(identical(other.audioSourceId, audioSourceId) || other.audioSourceId == audioSourceId)&&(identical(other.captureRef, captureRef) || other.captureRef == captureRef)&&(identical(other.nativeGeneration, nativeGeneration) || other.nativeGeneration == nativeGeneration)&&(identical(other.processId, processId) || other.processId == processId)&&(identical(other.processStarted, processStarted) || other.processStarted == processStarted)&&(identical(other.backend, backend) || other.backend == backend)&&(identical(other.nativeRevision, nativeRevision) || other.nativeRevision == nativeRevision)&&(identical(other.bytesWritten, bytesWritten) || other.bytesWritten == bytesWritten)&&(identical(other.presentationOnly, presentationOnly) || other.presentationOnly == presentationOnly)&&(identical(other.manualPaused, manualPaused) || other.manualPaused == manualPaused)&&(identical(other.focusPaused, focusPaused) || other.focusPaused == focusPaused)&&(identical(other.backgroundPaused, backgroundPaused) || other.backgroundPaused == backgroundPaused)&&(identical(other.requiresUserResume, requiresUserResume) || other.requiresUserResume == requiresUserResume)&&(identical(other.focusSignal, focusSignal) || other.focusSignal == focusSignal)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.cleanupError, cleanupError) || other.cleanupError == cleanupError));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,sourceId,deviceId,generation,name,status,createdAt,codec,sampleRate,channels,bytesPerSample,volume,muted,nativeAttached,playbackVerified,speakerSamplesVerified,audibleContentVerified,captureSource,callAudioSupported,remoteExitVerified,captureReady,mediaReady,localReleased,existing,audioSourceId,captureRef,nativeGeneration,processId,processStarted,backend,nativeRevision,bytesWritten,presentationOnly,manualPaused,focusPaused,backgroundPaused,requiresUserResume,focusSignal,reason,cleanupError]);
}

@override
String toString() {
    return 'DeviceAudioSnapshot(sourceId: $sourceId, deviceId: $deviceId, generation: $generation, name: $name, status: $status, createdAt: $createdAt, codec: $codec, sampleRate: $sampleRate, channels: $channels, bytesPerSample: $bytesPerSample, volume: $volume, muted: $muted, nativeAttached: $nativeAttached, playbackVerified: $playbackVerified, speakerSamplesVerified: $speakerSamplesVerified, audibleContentVerified: $audibleContentVerified, captureSource: $captureSource, callAudioSupported: $callAudioSupported, remoteExitVerified: $remoteExitVerified, captureReady: $captureReady, mediaReady: $mediaReady, localReleased: $localReleased, existing: $existing, audioSourceId: $audioSourceId, captureRef: $captureRef, nativeGeneration: $nativeGeneration, processId: $processId, processStarted: $processStarted, backend: $backend, nativeRevision: $nativeRevision, bytesWritten: $bytesWritten, presentationOnly: $presentationOnly, manualPaused: $manualPaused, focusPaused: $focusPaused, backgroundPaused: $backgroundPaused, requiresUserResume: $requiresUserResume, focusSignal: $focusSignal, reason: $reason, cleanupError: $cleanupError)';
}


}

/// @nodoc
abstract mixin class _$DeviceAudioSnapshotCopyWith<$Res> implements $DeviceAudioSnapshotCopyWith<$Res> {
  factory _$DeviceAudioSnapshotCopyWith(_DeviceAudioSnapshot value, $Res Function(_DeviceAudioSnapshot) _then) = __$DeviceAudioSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String sourceId, String deviceId, int generation, String name, DeviceAudioStatus status, int createdAt, String codec, int sampleRate, int channels, int bytesPerSample, double volume, bool muted, bool nativeAttached, bool playbackVerified, bool speakerSamplesVerified, bool audibleContentVerified, String captureSource, bool callAudioSupported, bool remoteExitVerified, bool captureReady, bool mediaReady, bool localReleased, bool existing, String? audioSourceId, String? captureRef, int? nativeGeneration, int? processId, int? processStarted, String? backend, int? nativeRevision, int? bytesWritten, bool? presentationOnly, bool? manualPaused, bool? focusPaused, bool? backgroundPaused, bool? requiresUserResume, String? focusSignal, String? reason, AudioCleanupFailure? cleanupError
});


@override $AudioCleanupFailureCopyWith<$Res>? get cleanupError;

}
/// @nodoc
class __$DeviceAudioSnapshotCopyWithImpl<$Res>
    implements _$DeviceAudioSnapshotCopyWith<$Res> {
  __$DeviceAudioSnapshotCopyWithImpl(this._self, this._then);

  final _DeviceAudioSnapshot _self;
  final $Res Function(_DeviceAudioSnapshot) _then;

/// Create a copy of DeviceAudioSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourceId = null,Object? deviceId = null,Object? generation = null,Object? name = null,Object? status = null,Object? createdAt = null,Object? codec = null,Object? sampleRate = null,Object? channels = null,Object? bytesPerSample = null,Object? volume = null,Object? muted = null,Object? nativeAttached = null,Object? playbackVerified = null,Object? speakerSamplesVerified = null,Object? audibleContentVerified = null,Object? captureSource = null,Object? callAudioSupported = null,Object? remoteExitVerified = null,Object? captureReady = null,Object? mediaReady = null,Object? localReleased = null,Object? existing = null,Object? audioSourceId = freezed,Object? captureRef = freezed,Object? nativeGeneration = freezed,Object? processId = freezed,Object? processStarted = freezed,Object? backend = freezed,Object? nativeRevision = freezed,Object? bytesWritten = freezed,Object? presentationOnly = freezed,Object? manualPaused = freezed,Object? focusPaused = freezed,Object? backgroundPaused = freezed,Object? requiresUserResume = freezed,Object? focusSignal = freezed,Object? reason = freezed,Object? cleanupError = freezed,}) {
  return _then(_DeviceAudioSnapshot(
sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceAudioStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,codec: null == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as String,sampleRate: null == sampleRate ? _self.sampleRate : sampleRate // ignore: cast_nullable_to_non_nullable
as int,channels: null == channels ? _self.channels : channels // ignore: cast_nullable_to_non_nullable
as int,bytesPerSample: null == bytesPerSample ? _self.bytesPerSample : bytesPerSample // ignore: cast_nullable_to_non_nullable
as int,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,nativeAttached: null == nativeAttached ? _self.nativeAttached : nativeAttached // ignore: cast_nullable_to_non_nullable
as bool,playbackVerified: null == playbackVerified ? _self.playbackVerified : playbackVerified // ignore: cast_nullable_to_non_nullable
as bool,speakerSamplesVerified: null == speakerSamplesVerified ? _self.speakerSamplesVerified : speakerSamplesVerified // ignore: cast_nullable_to_non_nullable
as bool,audibleContentVerified: null == audibleContentVerified ? _self.audibleContentVerified : audibleContentVerified // ignore: cast_nullable_to_non_nullable
as bool,captureSource: null == captureSource ? _self.captureSource : captureSource // ignore: cast_nullable_to_non_nullable
as String,callAudioSupported: null == callAudioSupported ? _self.callAudioSupported : callAudioSupported // ignore: cast_nullable_to_non_nullable
as bool,remoteExitVerified: null == remoteExitVerified ? _self.remoteExitVerified : remoteExitVerified // ignore: cast_nullable_to_non_nullable
as bool,captureReady: null == captureReady ? _self.captureReady : captureReady // ignore: cast_nullable_to_non_nullable
as bool,mediaReady: null == mediaReady ? _self.mediaReady : mediaReady // ignore: cast_nullable_to_non_nullable
as bool,localReleased: null == localReleased ? _self.localReleased : localReleased // ignore: cast_nullable_to_non_nullable
as bool,existing: null == existing ? _self.existing : existing // ignore: cast_nullable_to_non_nullable
as bool,audioSourceId: freezed == audioSourceId ? _self.audioSourceId : audioSourceId // ignore: cast_nullable_to_non_nullable
as String?,captureRef: freezed == captureRef ? _self.captureRef : captureRef // ignore: cast_nullable_to_non_nullable
as String?,nativeGeneration: freezed == nativeGeneration ? _self.nativeGeneration : nativeGeneration // ignore: cast_nullable_to_non_nullable
as int?,processId: freezed == processId ? _self.processId : processId // ignore: cast_nullable_to_non_nullable
as int?,processStarted: freezed == processStarted ? _self.processStarted : processStarted // ignore: cast_nullable_to_non_nullable
as int?,backend: freezed == backend ? _self.backend : backend // ignore: cast_nullable_to_non_nullable
as String?,nativeRevision: freezed == nativeRevision ? _self.nativeRevision : nativeRevision // ignore: cast_nullable_to_non_nullable
as int?,bytesWritten: freezed == bytesWritten ? _self.bytesWritten : bytesWritten // ignore: cast_nullable_to_non_nullable
as int?,presentationOnly: freezed == presentationOnly ? _self.presentationOnly : presentationOnly // ignore: cast_nullable_to_non_nullable
as bool?,manualPaused: freezed == manualPaused ? _self.manualPaused : manualPaused // ignore: cast_nullable_to_non_nullable
as bool?,focusPaused: freezed == focusPaused ? _self.focusPaused : focusPaused // ignore: cast_nullable_to_non_nullable
as bool?,backgroundPaused: freezed == backgroundPaused ? _self.backgroundPaused : backgroundPaused // ignore: cast_nullable_to_non_nullable
as bool?,requiresUserResume: freezed == requiresUserResume ? _self.requiresUserResume : requiresUserResume // ignore: cast_nullable_to_non_nullable
as bool?,focusSignal: freezed == focusSignal ? _self.focusSignal : focusSignal // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,cleanupError: freezed == cleanupError ? _self.cleanupError : cleanupError // ignore: cast_nullable_to_non_nullable
as AudioCleanupFailure?,
  ));
}

/// Create a copy of DeviceAudioSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AudioCleanupFailureCopyWith<$Res>? get cleanupError {
    if (_self.cleanupError == null) {
    return null;
  }

  return $AudioCleanupFailureCopyWith<$Res>(_self.cleanupError!, (value) {
    return _then(_self.copyWith(cleanupError: value));
  });
}
}

/// @nodoc
mixin _$AudioVolumeChange {

 DeviceAudioTarget get target; double get volume; bool get muted;
/// Create a copy of AudioVolumeChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AudioVolumeChangeCopyWith<AudioVolumeChange> get copyWith => _$AudioVolumeChangeCopyWithImpl<AudioVolumeChange>(this as AudioVolumeChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AudioVolumeChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AudioVolumeChange&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.volume, _this.volume) || other.volume == _this.volume)&&(identical(other.muted, _this.muted) || other.muted == _this.muted));
}


@override
int get hashCode {
  final _this = this as AudioVolumeChange;
  return Object.hash(runtimeType,_this.target,_this.volume,_this.muted);
}

@override
String toString() {
  final _this = this as AudioVolumeChange;
  return 'AudioVolumeChange(target: ${_this.target}, volume: ${_this.volume}, muted: ${_this.muted})';
}


}

/// @nodoc
abstract mixin class $AudioVolumeChangeCopyWith<$Res>  {
  factory $AudioVolumeChangeCopyWith(AudioVolumeChange value, $Res Function(AudioVolumeChange) _then) = _$AudioVolumeChangeCopyWithImpl;
@useResult
$Res call({
 DeviceAudioTarget target, double volume, bool muted
});


$DeviceAudioTargetCopyWith<$Res> get target;

}
/// @nodoc
class _$AudioVolumeChangeCopyWithImpl<$Res>
    implements $AudioVolumeChangeCopyWith<$Res> {
  _$AudioVolumeChangeCopyWithImpl(this._self, this._then);

  final AudioVolumeChange _self;
  final $Res Function(AudioVolumeChange) _then;

/// Create a copy of AudioVolumeChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? target = null,Object? volume = null,Object? muted = null,}) {
  return _then(AudioVolumeChange(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as DeviceAudioTarget,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of AudioVolumeChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceAudioTargetCopyWith<$Res> get target {
  
  return $DeviceAudioTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}


/// Adds pattern-matching-related methods to [AudioVolumeChange].
extension AudioVolumeChangePatterns on AudioVolumeChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AudioVolumeChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AudioVolumeChange() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AudioVolumeChange value)  $default,){
final _that = this;
switch (_that) {
case _AudioVolumeChange():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AudioVolumeChange value)?  $default,){
final _that = this;
switch (_that) {
case _AudioVolumeChange() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DeviceAudioTarget target,  double volume,  bool muted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AudioVolumeChange() when $default != null:
return $default(_that.target,_that.volume,_that.muted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DeviceAudioTarget target,  double volume,  bool muted)  $default,) {final _that = this;
switch (_that) {
case _AudioVolumeChange():
return $default(_that.target,_that.volume,_that.muted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DeviceAudioTarget target,  double volume,  bool muted)?  $default,) {final _that = this;
switch (_that) {
case _AudioVolumeChange() when $default != null:
return $default(_that.target,_that.volume,_that.muted);case _:
  return null;

}
}

}

/// @nodoc


class _AudioVolumeChange implements AudioVolumeChange {
  const _AudioVolumeChange({required this.target, required this.volume, required this.muted});
  

@override final  DeviceAudioTarget target;
@override final  double volume;
@override final  bool muted;

/// Create a copy of AudioVolumeChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AudioVolumeChangeCopyWith<_AudioVolumeChange> get copyWith => __$AudioVolumeChangeCopyWithImpl<_AudioVolumeChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AudioVolumeChange&&(identical(other.target, target) || other.target == target)&&(identical(other.volume, volume) || other.volume == volume)&&(identical(other.muted, muted) || other.muted == muted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,target,volume,muted);
}

@override
String toString() {
    return 'AudioVolumeChange(target: $target, volume: $volume, muted: $muted)';
}


}

/// @nodoc
abstract mixin class _$AudioVolumeChangeCopyWith<$Res> implements $AudioVolumeChangeCopyWith<$Res> {
  factory _$AudioVolumeChangeCopyWith(_AudioVolumeChange value, $Res Function(_AudioVolumeChange) _then) = __$AudioVolumeChangeCopyWithImpl;
@override @useResult
$Res call({
 DeviceAudioTarget target, double volume, bool muted
});


@override $DeviceAudioTargetCopyWith<$Res> get target;

}
/// @nodoc
class __$AudioVolumeChangeCopyWithImpl<$Res>
    implements _$AudioVolumeChangeCopyWith<$Res> {
  __$AudioVolumeChangeCopyWithImpl(this._self, this._then);

  final _AudioVolumeChange _self;
  final $Res Function(_AudioVolumeChange) _then;

/// Create a copy of AudioVolumeChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? target = null,Object? volume = null,Object? muted = null,}) {
  return _then(_AudioVolumeChange(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as DeviceAudioTarget,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of AudioVolumeChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceAudioTargetCopyWith<$Res> get target {
  
  return $DeviceAudioTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}

/// @nodoc
mixin _$AudioOutputReceipt {

 String get sourceId; String get deviceId; String? get relayId; String get backend; bool get nativeReady; int get bytesWritten; int get revision; bool get applied; AudioPlayState get playState; bool get manualPaused; bool get focusPaused; bool get backgroundPaused; bool get requiresUserResume; String get reason; int get sampleRate; int get channels; bool get mediaInfoReady; bool get playingConfirmed; bool get sourcePcmReceived; int get sourcePcmPackets; bool get playbackClockAdvanced; int? get clockStartMs; int? get clockEndMs; int? get positionMs; double get volume; bool get muted; int? get focusEpoch; String get focusSignal; bool get audibleContentVerified; bool get speakerSamplesVerified; bool get volumeConfigured; bool get volumeOutputVerified;
/// Create a copy of AudioOutputReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AudioOutputReceiptCopyWith<AudioOutputReceipt> get copyWith => _$AudioOutputReceiptCopyWithImpl<AudioOutputReceipt>(this as AudioOutputReceipt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AudioOutputReceipt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AudioOutputReceipt&&(identical(other.sourceId, _this.sourceId) || other.sourceId == _this.sourceId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.relayId, _this.relayId) || other.relayId == _this.relayId)&&(identical(other.backend, _this.backend) || other.backend == _this.backend)&&(identical(other.nativeReady, _this.nativeReady) || other.nativeReady == _this.nativeReady)&&(identical(other.bytesWritten, _this.bytesWritten) || other.bytesWritten == _this.bytesWritten)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.applied, _this.applied) || other.applied == _this.applied)&&(identical(other.playState, _this.playState) || other.playState == _this.playState)&&(identical(other.manualPaused, _this.manualPaused) || other.manualPaused == _this.manualPaused)&&(identical(other.focusPaused, _this.focusPaused) || other.focusPaused == _this.focusPaused)&&(identical(other.backgroundPaused, _this.backgroundPaused) || other.backgroundPaused == _this.backgroundPaused)&&(identical(other.requiresUserResume, _this.requiresUserResume) || other.requiresUserResume == _this.requiresUserResume)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.sampleRate, _this.sampleRate) || other.sampleRate == _this.sampleRate)&&(identical(other.channels, _this.channels) || other.channels == _this.channels)&&(identical(other.mediaInfoReady, _this.mediaInfoReady) || other.mediaInfoReady == _this.mediaInfoReady)&&(identical(other.playingConfirmed, _this.playingConfirmed) || other.playingConfirmed == _this.playingConfirmed)&&(identical(other.sourcePcmReceived, _this.sourcePcmReceived) || other.sourcePcmReceived == _this.sourcePcmReceived)&&(identical(other.sourcePcmPackets, _this.sourcePcmPackets) || other.sourcePcmPackets == _this.sourcePcmPackets)&&(identical(other.playbackClockAdvanced, _this.playbackClockAdvanced) || other.playbackClockAdvanced == _this.playbackClockAdvanced)&&(identical(other.clockStartMs, _this.clockStartMs) || other.clockStartMs == _this.clockStartMs)&&(identical(other.clockEndMs, _this.clockEndMs) || other.clockEndMs == _this.clockEndMs)&&(identical(other.positionMs, _this.positionMs) || other.positionMs == _this.positionMs)&&(identical(other.volume, _this.volume) || other.volume == _this.volume)&&(identical(other.muted, _this.muted) || other.muted == _this.muted)&&(identical(other.focusEpoch, _this.focusEpoch) || other.focusEpoch == _this.focusEpoch)&&(identical(other.focusSignal, _this.focusSignal) || other.focusSignal == _this.focusSignal)&&(identical(other.audibleContentVerified, _this.audibleContentVerified) || other.audibleContentVerified == _this.audibleContentVerified)&&(identical(other.speakerSamplesVerified, _this.speakerSamplesVerified) || other.speakerSamplesVerified == _this.speakerSamplesVerified)&&(identical(other.volumeConfigured, _this.volumeConfigured) || other.volumeConfigured == _this.volumeConfigured)&&(identical(other.volumeOutputVerified, _this.volumeOutputVerified) || other.volumeOutputVerified == _this.volumeOutputVerified));
}


@override
int get hashCode {
  final _this = this as AudioOutputReceipt;
  return Object.hashAll([runtimeType,_this.sourceId,_this.deviceId,_this.relayId,_this.backend,_this.nativeReady,_this.bytesWritten,_this.revision,_this.applied,_this.playState,_this.manualPaused,_this.focusPaused,_this.backgroundPaused,_this.requiresUserResume,_this.reason,_this.sampleRate,_this.channels,_this.mediaInfoReady,_this.playingConfirmed,_this.sourcePcmReceived,_this.sourcePcmPackets,_this.playbackClockAdvanced,_this.clockStartMs,_this.clockEndMs,_this.positionMs,_this.volume,_this.muted,_this.focusEpoch,_this.focusSignal,_this.audibleContentVerified,_this.speakerSamplesVerified,_this.volumeConfigured,_this.volumeOutputVerified]);
}

@override
String toString() {
  final _this = this as AudioOutputReceipt;
  return 'AudioOutputReceipt(sourceId: ${_this.sourceId}, deviceId: ${_this.deviceId}, relayId: ${_this.relayId}, backend: ${_this.backend}, nativeReady: ${_this.nativeReady}, bytesWritten: ${_this.bytesWritten}, revision: ${_this.revision}, applied: ${_this.applied}, playState: ${_this.playState}, manualPaused: ${_this.manualPaused}, focusPaused: ${_this.focusPaused}, backgroundPaused: ${_this.backgroundPaused}, requiresUserResume: ${_this.requiresUserResume}, reason: ${_this.reason}, sampleRate: ${_this.sampleRate}, channels: ${_this.channels}, mediaInfoReady: ${_this.mediaInfoReady}, playingConfirmed: ${_this.playingConfirmed}, sourcePcmReceived: ${_this.sourcePcmReceived}, sourcePcmPackets: ${_this.sourcePcmPackets}, playbackClockAdvanced: ${_this.playbackClockAdvanced}, clockStartMs: ${_this.clockStartMs}, clockEndMs: ${_this.clockEndMs}, positionMs: ${_this.positionMs}, volume: ${_this.volume}, muted: ${_this.muted}, focusEpoch: ${_this.focusEpoch}, focusSignal: ${_this.focusSignal}, audibleContentVerified: ${_this.audibleContentVerified}, speakerSamplesVerified: ${_this.speakerSamplesVerified}, volumeConfigured: ${_this.volumeConfigured}, volumeOutputVerified: ${_this.volumeOutputVerified})';
}


}

/// @nodoc
abstract mixin class $AudioOutputReceiptCopyWith<$Res>  {
  factory $AudioOutputReceiptCopyWith(AudioOutputReceipt value, $Res Function(AudioOutputReceipt) _then) = _$AudioOutputReceiptCopyWithImpl;
@useResult
$Res call({
 String sourceId, String deviceId, String? relayId, String backend, bool nativeReady, int bytesWritten, int revision, bool applied, AudioPlayState playState, bool manualPaused, bool focusPaused, bool backgroundPaused, bool requiresUserResume, String reason, int sampleRate, int channels, bool mediaInfoReady, bool playingConfirmed, bool sourcePcmReceived, int sourcePcmPackets, bool playbackClockAdvanced, int? clockStartMs, int? clockEndMs, int? positionMs, double volume, bool muted, int? focusEpoch, String focusSignal, bool audibleContentVerified, bool speakerSamplesVerified, bool volumeConfigured, bool volumeOutputVerified
});




}
/// @nodoc
class _$AudioOutputReceiptCopyWithImpl<$Res>
    implements $AudioOutputReceiptCopyWith<$Res> {
  _$AudioOutputReceiptCopyWithImpl(this._self, this._then);

  final AudioOutputReceipt _self;
  final $Res Function(AudioOutputReceipt) _then;

/// Create a copy of AudioOutputReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sourceId = null,Object? deviceId = null,Object? relayId = freezed,Object? backend = null,Object? nativeReady = null,Object? bytesWritten = null,Object? revision = null,Object? applied = null,Object? playState = null,Object? manualPaused = null,Object? focusPaused = null,Object? backgroundPaused = null,Object? requiresUserResume = null,Object? reason = null,Object? sampleRate = null,Object? channels = null,Object? mediaInfoReady = null,Object? playingConfirmed = null,Object? sourcePcmReceived = null,Object? sourcePcmPackets = null,Object? playbackClockAdvanced = null,Object? clockStartMs = freezed,Object? clockEndMs = freezed,Object? positionMs = freezed,Object? volume = null,Object? muted = null,Object? focusEpoch = freezed,Object? focusSignal = null,Object? audibleContentVerified = null,Object? speakerSamplesVerified = null,Object? volumeConfigured = null,Object? volumeOutputVerified = null,}) {
  return _then(AudioOutputReceipt(
sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,relayId: freezed == relayId ? _self.relayId : relayId // ignore: cast_nullable_to_non_nullable
as String?,backend: null == backend ? _self.backend : backend // ignore: cast_nullable_to_non_nullable
as String,nativeReady: null == nativeReady ? _self.nativeReady : nativeReady // ignore: cast_nullable_to_non_nullable
as bool,bytesWritten: null == bytesWritten ? _self.bytesWritten : bytesWritten // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,applied: null == applied ? _self.applied : applied // ignore: cast_nullable_to_non_nullable
as bool,playState: null == playState ? _self.playState : playState // ignore: cast_nullable_to_non_nullable
as AudioPlayState,manualPaused: null == manualPaused ? _self.manualPaused : manualPaused // ignore: cast_nullable_to_non_nullable
as bool,focusPaused: null == focusPaused ? _self.focusPaused : focusPaused // ignore: cast_nullable_to_non_nullable
as bool,backgroundPaused: null == backgroundPaused ? _self.backgroundPaused : backgroundPaused // ignore: cast_nullable_to_non_nullable
as bool,requiresUserResume: null == requiresUserResume ? _self.requiresUserResume : requiresUserResume // ignore: cast_nullable_to_non_nullable
as bool,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,sampleRate: null == sampleRate ? _self.sampleRate : sampleRate // ignore: cast_nullable_to_non_nullable
as int,channels: null == channels ? _self.channels : channels // ignore: cast_nullable_to_non_nullable
as int,mediaInfoReady: null == mediaInfoReady ? _self.mediaInfoReady : mediaInfoReady // ignore: cast_nullable_to_non_nullable
as bool,playingConfirmed: null == playingConfirmed ? _self.playingConfirmed : playingConfirmed // ignore: cast_nullable_to_non_nullable
as bool,sourcePcmReceived: null == sourcePcmReceived ? _self.sourcePcmReceived : sourcePcmReceived // ignore: cast_nullable_to_non_nullable
as bool,sourcePcmPackets: null == sourcePcmPackets ? _self.sourcePcmPackets : sourcePcmPackets // ignore: cast_nullable_to_non_nullable
as int,playbackClockAdvanced: null == playbackClockAdvanced ? _self.playbackClockAdvanced : playbackClockAdvanced // ignore: cast_nullable_to_non_nullable
as bool,clockStartMs: freezed == clockStartMs ? _self.clockStartMs : clockStartMs // ignore: cast_nullable_to_non_nullable
as int?,clockEndMs: freezed == clockEndMs ? _self.clockEndMs : clockEndMs // ignore: cast_nullable_to_non_nullable
as int?,positionMs: freezed == positionMs ? _self.positionMs : positionMs // ignore: cast_nullable_to_non_nullable
as int?,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,focusEpoch: freezed == focusEpoch ? _self.focusEpoch : focusEpoch // ignore: cast_nullable_to_non_nullable
as int?,focusSignal: null == focusSignal ? _self.focusSignal : focusSignal // ignore: cast_nullable_to_non_nullable
as String,audibleContentVerified: null == audibleContentVerified ? _self.audibleContentVerified : audibleContentVerified // ignore: cast_nullable_to_non_nullable
as bool,speakerSamplesVerified: null == speakerSamplesVerified ? _self.speakerSamplesVerified : speakerSamplesVerified // ignore: cast_nullable_to_non_nullable
as bool,volumeConfigured: null == volumeConfigured ? _self.volumeConfigured : volumeConfigured // ignore: cast_nullable_to_non_nullable
as bool,volumeOutputVerified: null == volumeOutputVerified ? _self.volumeOutputVerified : volumeOutputVerified // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AudioOutputReceipt].
extension AudioOutputReceiptPatterns on AudioOutputReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AudioOutputReceipt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AudioOutputReceipt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AudioOutputReceipt value)  $default,){
final _that = this;
switch (_that) {
case _AudioOutputReceipt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AudioOutputReceipt value)?  $default,){
final _that = this;
switch (_that) {
case _AudioOutputReceipt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sourceId,  String deviceId,  String? relayId,  String backend,  bool nativeReady,  int bytesWritten,  int revision,  bool applied,  AudioPlayState playState,  bool manualPaused,  bool focusPaused,  bool backgroundPaused,  bool requiresUserResume,  String reason,  int sampleRate,  int channels,  bool mediaInfoReady,  bool playingConfirmed,  bool sourcePcmReceived,  int sourcePcmPackets,  bool playbackClockAdvanced,  int? clockStartMs,  int? clockEndMs,  int? positionMs,  double volume,  bool muted,  int? focusEpoch,  String focusSignal,  bool audibleContentVerified,  bool speakerSamplesVerified,  bool volumeConfigured,  bool volumeOutputVerified)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AudioOutputReceipt() when $default != null:
return $default(_that.sourceId,_that.deviceId,_that.relayId,_that.backend,_that.nativeReady,_that.bytesWritten,_that.revision,_that.applied,_that.playState,_that.manualPaused,_that.focusPaused,_that.backgroundPaused,_that.requiresUserResume,_that.reason,_that.sampleRate,_that.channels,_that.mediaInfoReady,_that.playingConfirmed,_that.sourcePcmReceived,_that.sourcePcmPackets,_that.playbackClockAdvanced,_that.clockStartMs,_that.clockEndMs,_that.positionMs,_that.volume,_that.muted,_that.focusEpoch,_that.focusSignal,_that.audibleContentVerified,_that.speakerSamplesVerified,_that.volumeConfigured,_that.volumeOutputVerified);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sourceId,  String deviceId,  String? relayId,  String backend,  bool nativeReady,  int bytesWritten,  int revision,  bool applied,  AudioPlayState playState,  bool manualPaused,  bool focusPaused,  bool backgroundPaused,  bool requiresUserResume,  String reason,  int sampleRate,  int channels,  bool mediaInfoReady,  bool playingConfirmed,  bool sourcePcmReceived,  int sourcePcmPackets,  bool playbackClockAdvanced,  int? clockStartMs,  int? clockEndMs,  int? positionMs,  double volume,  bool muted,  int? focusEpoch,  String focusSignal,  bool audibleContentVerified,  bool speakerSamplesVerified,  bool volumeConfigured,  bool volumeOutputVerified)  $default,) {final _that = this;
switch (_that) {
case _AudioOutputReceipt():
return $default(_that.sourceId,_that.deviceId,_that.relayId,_that.backend,_that.nativeReady,_that.bytesWritten,_that.revision,_that.applied,_that.playState,_that.manualPaused,_that.focusPaused,_that.backgroundPaused,_that.requiresUserResume,_that.reason,_that.sampleRate,_that.channels,_that.mediaInfoReady,_that.playingConfirmed,_that.sourcePcmReceived,_that.sourcePcmPackets,_that.playbackClockAdvanced,_that.clockStartMs,_that.clockEndMs,_that.positionMs,_that.volume,_that.muted,_that.focusEpoch,_that.focusSignal,_that.audibleContentVerified,_that.speakerSamplesVerified,_that.volumeConfigured,_that.volumeOutputVerified);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sourceId,  String deviceId,  String? relayId,  String backend,  bool nativeReady,  int bytesWritten,  int revision,  bool applied,  AudioPlayState playState,  bool manualPaused,  bool focusPaused,  bool backgroundPaused,  bool requiresUserResume,  String reason,  int sampleRate,  int channels,  bool mediaInfoReady,  bool playingConfirmed,  bool sourcePcmReceived,  int sourcePcmPackets,  bool playbackClockAdvanced,  int? clockStartMs,  int? clockEndMs,  int? positionMs,  double volume,  bool muted,  int? focusEpoch,  String focusSignal,  bool audibleContentVerified,  bool speakerSamplesVerified,  bool volumeConfigured,  bool volumeOutputVerified)?  $default,) {final _that = this;
switch (_that) {
case _AudioOutputReceipt() when $default != null:
return $default(_that.sourceId,_that.deviceId,_that.relayId,_that.backend,_that.nativeReady,_that.bytesWritten,_that.revision,_that.applied,_that.playState,_that.manualPaused,_that.focusPaused,_that.backgroundPaused,_that.requiresUserResume,_that.reason,_that.sampleRate,_that.channels,_that.mediaInfoReady,_that.playingConfirmed,_that.sourcePcmReceived,_that.sourcePcmPackets,_that.playbackClockAdvanced,_that.clockStartMs,_that.clockEndMs,_that.positionMs,_that.volume,_that.muted,_that.focusEpoch,_that.focusSignal,_that.audibleContentVerified,_that.speakerSamplesVerified,_that.volumeConfigured,_that.volumeOutputVerified);case _:
  return null;

}
}

}

/// @nodoc


class _AudioOutputReceipt implements AudioOutputReceipt {
  const _AudioOutputReceipt({required this.sourceId, required this.deviceId, this.relayId, this.backend = 'media_codec', required this.nativeReady, required this.bytesWritten, required this.revision, required this.applied, required this.playState, required this.manualPaused, required this.focusPaused, required this.backgroundPaused, required this.requiresUserResume, required this.reason, this.sampleRate = 48000, this.channels = 2, required this.mediaInfoReady, required this.playingConfirmed, required this.sourcePcmReceived, required this.sourcePcmPackets, required this.playbackClockAdvanced, this.clockStartMs, this.clockEndMs, this.positionMs, required this.volume, required this.muted, this.focusEpoch, required this.focusSignal, this.audibleContentVerified = false, this.speakerSamplesVerified = false, this.volumeConfigured = false, this.volumeOutputVerified = false});
  

@override final  String sourceId;
@override final  String deviceId;
@override final  String? relayId;
@override@JsonKey() final  String backend;
@override final  bool nativeReady;
@override final  int bytesWritten;
@override final  int revision;
@override final  bool applied;
@override final  AudioPlayState playState;
@override final  bool manualPaused;
@override final  bool focusPaused;
@override final  bool backgroundPaused;
@override final  bool requiresUserResume;
@override final  String reason;
@override@JsonKey() final  int sampleRate;
@override@JsonKey() final  int channels;
@override final  bool mediaInfoReady;
@override final  bool playingConfirmed;
@override final  bool sourcePcmReceived;
@override final  int sourcePcmPackets;
@override final  bool playbackClockAdvanced;
@override final  int? clockStartMs;
@override final  int? clockEndMs;
@override final  int? positionMs;
@override final  double volume;
@override final  bool muted;
@override final  int? focusEpoch;
@override final  String focusSignal;
@override@JsonKey() final  bool audibleContentVerified;
@override@JsonKey() final  bool speakerSamplesVerified;
@override@JsonKey() final  bool volumeConfigured;
@override@JsonKey() final  bool volumeOutputVerified;

/// Create a copy of AudioOutputReceipt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AudioOutputReceiptCopyWith<_AudioOutputReceipt> get copyWith => __$AudioOutputReceiptCopyWithImpl<_AudioOutputReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AudioOutputReceipt&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.relayId, relayId) || other.relayId == relayId)&&(identical(other.backend, backend) || other.backend == backend)&&(identical(other.nativeReady, nativeReady) || other.nativeReady == nativeReady)&&(identical(other.bytesWritten, bytesWritten) || other.bytesWritten == bytesWritten)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.applied, applied) || other.applied == applied)&&(identical(other.playState, playState) || other.playState == playState)&&(identical(other.manualPaused, manualPaused) || other.manualPaused == manualPaused)&&(identical(other.focusPaused, focusPaused) || other.focusPaused == focusPaused)&&(identical(other.backgroundPaused, backgroundPaused) || other.backgroundPaused == backgroundPaused)&&(identical(other.requiresUserResume, requiresUserResume) || other.requiresUserResume == requiresUserResume)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.sampleRate, sampleRate) || other.sampleRate == sampleRate)&&(identical(other.channels, channels) || other.channels == channels)&&(identical(other.mediaInfoReady, mediaInfoReady) || other.mediaInfoReady == mediaInfoReady)&&(identical(other.playingConfirmed, playingConfirmed) || other.playingConfirmed == playingConfirmed)&&(identical(other.sourcePcmReceived, sourcePcmReceived) || other.sourcePcmReceived == sourcePcmReceived)&&(identical(other.sourcePcmPackets, sourcePcmPackets) || other.sourcePcmPackets == sourcePcmPackets)&&(identical(other.playbackClockAdvanced, playbackClockAdvanced) || other.playbackClockAdvanced == playbackClockAdvanced)&&(identical(other.clockStartMs, clockStartMs) || other.clockStartMs == clockStartMs)&&(identical(other.clockEndMs, clockEndMs) || other.clockEndMs == clockEndMs)&&(identical(other.positionMs, positionMs) || other.positionMs == positionMs)&&(identical(other.volume, volume) || other.volume == volume)&&(identical(other.muted, muted) || other.muted == muted)&&(identical(other.focusEpoch, focusEpoch) || other.focusEpoch == focusEpoch)&&(identical(other.focusSignal, focusSignal) || other.focusSignal == focusSignal)&&(identical(other.audibleContentVerified, audibleContentVerified) || other.audibleContentVerified == audibleContentVerified)&&(identical(other.speakerSamplesVerified, speakerSamplesVerified) || other.speakerSamplesVerified == speakerSamplesVerified)&&(identical(other.volumeConfigured, volumeConfigured) || other.volumeConfigured == volumeConfigured)&&(identical(other.volumeOutputVerified, volumeOutputVerified) || other.volumeOutputVerified == volumeOutputVerified));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,sourceId,deviceId,relayId,backend,nativeReady,bytesWritten,revision,applied,playState,manualPaused,focusPaused,backgroundPaused,requiresUserResume,reason,sampleRate,channels,mediaInfoReady,playingConfirmed,sourcePcmReceived,sourcePcmPackets,playbackClockAdvanced,clockStartMs,clockEndMs,positionMs,volume,muted,focusEpoch,focusSignal,audibleContentVerified,speakerSamplesVerified,volumeConfigured,volumeOutputVerified]);
}

@override
String toString() {
    return 'AudioOutputReceipt(sourceId: $sourceId, deviceId: $deviceId, relayId: $relayId, backend: $backend, nativeReady: $nativeReady, bytesWritten: $bytesWritten, revision: $revision, applied: $applied, playState: $playState, manualPaused: $manualPaused, focusPaused: $focusPaused, backgroundPaused: $backgroundPaused, requiresUserResume: $requiresUserResume, reason: $reason, sampleRate: $sampleRate, channels: $channels, mediaInfoReady: $mediaInfoReady, playingConfirmed: $playingConfirmed, sourcePcmReceived: $sourcePcmReceived, sourcePcmPackets: $sourcePcmPackets, playbackClockAdvanced: $playbackClockAdvanced, clockStartMs: $clockStartMs, clockEndMs: $clockEndMs, positionMs: $positionMs, volume: $volume, muted: $muted, focusEpoch: $focusEpoch, focusSignal: $focusSignal, audibleContentVerified: $audibleContentVerified, speakerSamplesVerified: $speakerSamplesVerified, volumeConfigured: $volumeConfigured, volumeOutputVerified: $volumeOutputVerified)';
}


}

/// @nodoc
abstract mixin class _$AudioOutputReceiptCopyWith<$Res> implements $AudioOutputReceiptCopyWith<$Res> {
  factory _$AudioOutputReceiptCopyWith(_AudioOutputReceipt value, $Res Function(_AudioOutputReceipt) _then) = __$AudioOutputReceiptCopyWithImpl;
@override @useResult
$Res call({
 String sourceId, String deviceId, String? relayId, String backend, bool nativeReady, int bytesWritten, int revision, bool applied, AudioPlayState playState, bool manualPaused, bool focusPaused, bool backgroundPaused, bool requiresUserResume, String reason, int sampleRate, int channels, bool mediaInfoReady, bool playingConfirmed, bool sourcePcmReceived, int sourcePcmPackets, bool playbackClockAdvanced, int? clockStartMs, int? clockEndMs, int? positionMs, double volume, bool muted, int? focusEpoch, String focusSignal, bool audibleContentVerified, bool speakerSamplesVerified, bool volumeConfigured, bool volumeOutputVerified
});




}
/// @nodoc
class __$AudioOutputReceiptCopyWithImpl<$Res>
    implements _$AudioOutputReceiptCopyWith<$Res> {
  __$AudioOutputReceiptCopyWithImpl(this._self, this._then);

  final _AudioOutputReceipt _self;
  final $Res Function(_AudioOutputReceipt) _then;

/// Create a copy of AudioOutputReceipt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourceId = null,Object? deviceId = null,Object? relayId = freezed,Object? backend = null,Object? nativeReady = null,Object? bytesWritten = null,Object? revision = null,Object? applied = null,Object? playState = null,Object? manualPaused = null,Object? focusPaused = null,Object? backgroundPaused = null,Object? requiresUserResume = null,Object? reason = null,Object? sampleRate = null,Object? channels = null,Object? mediaInfoReady = null,Object? playingConfirmed = null,Object? sourcePcmReceived = null,Object? sourcePcmPackets = null,Object? playbackClockAdvanced = null,Object? clockStartMs = freezed,Object? clockEndMs = freezed,Object? positionMs = freezed,Object? volume = null,Object? muted = null,Object? focusEpoch = freezed,Object? focusSignal = null,Object? audibleContentVerified = null,Object? speakerSamplesVerified = null,Object? volumeConfigured = null,Object? volumeOutputVerified = null,}) {
  return _then(_AudioOutputReceipt(
sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,relayId: freezed == relayId ? _self.relayId : relayId // ignore: cast_nullable_to_non_nullable
as String?,backend: null == backend ? _self.backend : backend // ignore: cast_nullable_to_non_nullable
as String,nativeReady: null == nativeReady ? _self.nativeReady : nativeReady // ignore: cast_nullable_to_non_nullable
as bool,bytesWritten: null == bytesWritten ? _self.bytesWritten : bytesWritten // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,applied: null == applied ? _self.applied : applied // ignore: cast_nullable_to_non_nullable
as bool,playState: null == playState ? _self.playState : playState // ignore: cast_nullable_to_non_nullable
as AudioPlayState,manualPaused: null == manualPaused ? _self.manualPaused : manualPaused // ignore: cast_nullable_to_non_nullable
as bool,focusPaused: null == focusPaused ? _self.focusPaused : focusPaused // ignore: cast_nullable_to_non_nullable
as bool,backgroundPaused: null == backgroundPaused ? _self.backgroundPaused : backgroundPaused // ignore: cast_nullable_to_non_nullable
as bool,requiresUserResume: null == requiresUserResume ? _self.requiresUserResume : requiresUserResume // ignore: cast_nullable_to_non_nullable
as bool,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,sampleRate: null == sampleRate ? _self.sampleRate : sampleRate // ignore: cast_nullable_to_non_nullable
as int,channels: null == channels ? _self.channels : channels // ignore: cast_nullable_to_non_nullable
as int,mediaInfoReady: null == mediaInfoReady ? _self.mediaInfoReady : mediaInfoReady // ignore: cast_nullable_to_non_nullable
as bool,playingConfirmed: null == playingConfirmed ? _self.playingConfirmed : playingConfirmed // ignore: cast_nullable_to_non_nullable
as bool,sourcePcmReceived: null == sourcePcmReceived ? _self.sourcePcmReceived : sourcePcmReceived // ignore: cast_nullable_to_non_nullable
as bool,sourcePcmPackets: null == sourcePcmPackets ? _self.sourcePcmPackets : sourcePcmPackets // ignore: cast_nullable_to_non_nullable
as int,playbackClockAdvanced: null == playbackClockAdvanced ? _self.playbackClockAdvanced : playbackClockAdvanced // ignore: cast_nullable_to_non_nullable
as bool,clockStartMs: freezed == clockStartMs ? _self.clockStartMs : clockStartMs // ignore: cast_nullable_to_non_nullable
as int?,clockEndMs: freezed == clockEndMs ? _self.clockEndMs : clockEndMs // ignore: cast_nullable_to_non_nullable
as int?,positionMs: freezed == positionMs ? _self.positionMs : positionMs // ignore: cast_nullable_to_non_nullable
as int?,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,focusEpoch: freezed == focusEpoch ? _self.focusEpoch : focusEpoch // ignore: cast_nullable_to_non_nullable
as int?,focusSignal: null == focusSignal ? _self.focusSignal : focusSignal // ignore: cast_nullable_to_non_nullable
as String,audibleContentVerified: null == audibleContentVerified ? _self.audibleContentVerified : audibleContentVerified // ignore: cast_nullable_to_non_nullable
as bool,speakerSamplesVerified: null == speakerSamplesVerified ? _self.speakerSamplesVerified : speakerSamplesVerified // ignore: cast_nullable_to_non_nullable
as bool,volumeConfigured: null == volumeConfigured ? _self.volumeConfigured : volumeConfigured // ignore: cast_nullable_to_non_nullable
as bool,volumeOutputVerified: null == volumeOutputVerified ? _self.volumeOutputVerified : volumeOutputVerified // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
