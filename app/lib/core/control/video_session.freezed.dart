// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'video_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VideoSessionSnapshot {

 String get sessionId; String get deviceId; String get name; VideoSessionKind get kind; VideoSessionStatus get status; String? get packageName; int get captureGeneration; int get generation; int get createdAt; VideoQuality? get quality; VideoCodec? get videoCodec; String? get videoEncoder; String? get captureRef; String? get videoSourceId; int? get width; int? get height; int? get textureId; bool get paused; bool get awaitingSession; bool get capturePaused; bool get audio; int? get apiLevel; bool get displayAuto; int? get displayWidth; int? get displayHeight; int? get displayDensity; int? get displayId; String? get launchOperationId; VideoLaunchOutcome? get launchOutcome; int? get taskId; String? get failureCode; String? get reason; int? get frameCount; int? get lastFrameAt; int? get framesDecoded; int? get presentationTimeUs; String? get decoder; String? get renderer; bool? get hardwareAccelerated; String? get hardwareAcceleration; int? get decodedWidth; int? get decodedHeight; int? get processId; int? get processStarted; bool get qualityRebuilding; int? get qualityRebuildTarget; VideoQualityRebuildOutcome? get qualityRebuildOutcome; bool get qualityRetryable; String? get qualityFailureCode; VideoDisplayOutcome? get displayOutcome; String? get displayFailureCode; bool get recordOnly; String? get linkedSessionId;
/// Create a copy of VideoSessionSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoSessionSnapshotCopyWith<VideoSessionSnapshot> get copyWith => _$VideoSessionSnapshotCopyWithImpl<VideoSessionSnapshot>(this as VideoSessionSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoSessionSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoSessionSnapshot&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.packageName, _this.packageName) || other.packageName == _this.packageName)&&(identical(other.captureGeneration, _this.captureGeneration) || other.captureGeneration == _this.captureGeneration)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.quality, _this.quality) || other.quality == _this.quality)&&(identical(other.videoCodec, _this.videoCodec) || other.videoCodec == _this.videoCodec)&&(identical(other.videoEncoder, _this.videoEncoder) || other.videoEncoder == _this.videoEncoder)&&(identical(other.captureRef, _this.captureRef) || other.captureRef == _this.captureRef)&&(identical(other.videoSourceId, _this.videoSourceId) || other.videoSourceId == _this.videoSourceId)&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.height, _this.height) || other.height == _this.height)&&(identical(other.textureId, _this.textureId) || other.textureId == _this.textureId)&&(identical(other.paused, _this.paused) || other.paused == _this.paused)&&(identical(other.awaitingSession, _this.awaitingSession) || other.awaitingSession == _this.awaitingSession)&&(identical(other.capturePaused, _this.capturePaused) || other.capturePaused == _this.capturePaused)&&(identical(other.audio, _this.audio) || other.audio == _this.audio)&&(identical(other.apiLevel, _this.apiLevel) || other.apiLevel == _this.apiLevel)&&(identical(other.displayAuto, _this.displayAuto) || other.displayAuto == _this.displayAuto)&&(identical(other.displayWidth, _this.displayWidth) || other.displayWidth == _this.displayWidth)&&(identical(other.displayHeight, _this.displayHeight) || other.displayHeight == _this.displayHeight)&&(identical(other.displayDensity, _this.displayDensity) || other.displayDensity == _this.displayDensity)&&(identical(other.displayId, _this.displayId) || other.displayId == _this.displayId)&&(identical(other.launchOperationId, _this.launchOperationId) || other.launchOperationId == _this.launchOperationId)&&(identical(other.launchOutcome, _this.launchOutcome) || other.launchOutcome == _this.launchOutcome)&&(identical(other.taskId, _this.taskId) || other.taskId == _this.taskId)&&(identical(other.failureCode, _this.failureCode) || other.failureCode == _this.failureCode)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.frameCount, _this.frameCount) || other.frameCount == _this.frameCount)&&(identical(other.lastFrameAt, _this.lastFrameAt) || other.lastFrameAt == _this.lastFrameAt)&&(identical(other.framesDecoded, _this.framesDecoded) || other.framesDecoded == _this.framesDecoded)&&(identical(other.presentationTimeUs, _this.presentationTimeUs) || other.presentationTimeUs == _this.presentationTimeUs)&&(identical(other.decoder, _this.decoder) || other.decoder == _this.decoder)&&(identical(other.renderer, _this.renderer) || other.renderer == _this.renderer)&&(identical(other.hardwareAccelerated, _this.hardwareAccelerated) || other.hardwareAccelerated == _this.hardwareAccelerated)&&(identical(other.hardwareAcceleration, _this.hardwareAcceleration) || other.hardwareAcceleration == _this.hardwareAcceleration)&&(identical(other.decodedWidth, _this.decodedWidth) || other.decodedWidth == _this.decodedWidth)&&(identical(other.decodedHeight, _this.decodedHeight) || other.decodedHeight == _this.decodedHeight)&&(identical(other.processId, _this.processId) || other.processId == _this.processId)&&(identical(other.processStarted, _this.processStarted) || other.processStarted == _this.processStarted)&&(identical(other.qualityRebuilding, _this.qualityRebuilding) || other.qualityRebuilding == _this.qualityRebuilding)&&(identical(other.qualityRebuildTarget, _this.qualityRebuildTarget) || other.qualityRebuildTarget == _this.qualityRebuildTarget)&&(identical(other.qualityRebuildOutcome, _this.qualityRebuildOutcome) || other.qualityRebuildOutcome == _this.qualityRebuildOutcome)&&(identical(other.qualityRetryable, _this.qualityRetryable) || other.qualityRetryable == _this.qualityRetryable)&&(identical(other.qualityFailureCode, _this.qualityFailureCode) || other.qualityFailureCode == _this.qualityFailureCode)&&(identical(other.displayOutcome, _this.displayOutcome) || other.displayOutcome == _this.displayOutcome)&&(identical(other.displayFailureCode, _this.displayFailureCode) || other.displayFailureCode == _this.displayFailureCode)&&(identical(other.recordOnly, _this.recordOnly) || other.recordOnly == _this.recordOnly)&&(identical(other.linkedSessionId, _this.linkedSessionId) || other.linkedSessionId == _this.linkedSessionId));
}


@override
int get hashCode {
  final _this = this as VideoSessionSnapshot;
  return Object.hashAll([runtimeType,_this.sessionId,_this.deviceId,_this.name,_this.kind,_this.status,_this.packageName,_this.captureGeneration,_this.generation,_this.createdAt,_this.quality,_this.videoCodec,_this.videoEncoder,_this.captureRef,_this.videoSourceId,_this.width,_this.height,_this.textureId,_this.paused,_this.awaitingSession,_this.capturePaused,_this.audio,_this.apiLevel,_this.displayAuto,_this.displayWidth,_this.displayHeight,_this.displayDensity,_this.displayId,_this.launchOperationId,_this.launchOutcome,_this.taskId,_this.failureCode,_this.reason,_this.frameCount,_this.lastFrameAt,_this.framesDecoded,_this.presentationTimeUs,_this.decoder,_this.renderer,_this.hardwareAccelerated,_this.hardwareAcceleration,_this.decodedWidth,_this.decodedHeight,_this.processId,_this.processStarted,_this.qualityRebuilding,_this.qualityRebuildTarget,_this.qualityRebuildOutcome,_this.qualityRetryable,_this.qualityFailureCode,_this.displayOutcome,_this.displayFailureCode,_this.recordOnly,_this.linkedSessionId]);
}

@override
String toString() {
  final _this = this as VideoSessionSnapshot;
  return 'VideoSessionSnapshot(sessionId: ${_this.sessionId}, deviceId: ${_this.deviceId}, name: ${_this.name}, kind: ${_this.kind}, status: ${_this.status}, packageName: ${_this.packageName}, captureGeneration: ${_this.captureGeneration}, generation: ${_this.generation}, createdAt: ${_this.createdAt}, quality: ${_this.quality}, videoCodec: ${_this.videoCodec}, videoEncoder: ${_this.videoEncoder}, captureRef: ${_this.captureRef}, videoSourceId: ${_this.videoSourceId}, width: ${_this.width}, height: ${_this.height}, textureId: ${_this.textureId}, paused: ${_this.paused}, awaitingSession: ${_this.awaitingSession}, capturePaused: ${_this.capturePaused}, audio: ${_this.audio}, apiLevel: ${_this.apiLevel}, displayAuto: ${_this.displayAuto}, displayWidth: ${_this.displayWidth}, displayHeight: ${_this.displayHeight}, displayDensity: ${_this.displayDensity}, displayId: ${_this.displayId}, launchOperationId: ${_this.launchOperationId}, launchOutcome: ${_this.launchOutcome}, taskId: ${_this.taskId}, failureCode: ${_this.failureCode}, reason: ${_this.reason}, frameCount: ${_this.frameCount}, lastFrameAt: ${_this.lastFrameAt}, framesDecoded: ${_this.framesDecoded}, presentationTimeUs: ${_this.presentationTimeUs}, decoder: ${_this.decoder}, renderer: ${_this.renderer}, hardwareAccelerated: ${_this.hardwareAccelerated}, hardwareAcceleration: ${_this.hardwareAcceleration}, decodedWidth: ${_this.decodedWidth}, decodedHeight: ${_this.decodedHeight}, processId: ${_this.processId}, processStarted: ${_this.processStarted}, qualityRebuilding: ${_this.qualityRebuilding}, qualityRebuildTarget: ${_this.qualityRebuildTarget}, qualityRebuildOutcome: ${_this.qualityRebuildOutcome}, qualityRetryable: ${_this.qualityRetryable}, qualityFailureCode: ${_this.qualityFailureCode}, displayOutcome: ${_this.displayOutcome}, displayFailureCode: ${_this.displayFailureCode}, recordOnly: ${_this.recordOnly}, linkedSessionId: ${_this.linkedSessionId})';
}


}

/// @nodoc
abstract mixin class $VideoSessionSnapshotCopyWith<$Res>  {
  factory $VideoSessionSnapshotCopyWith(VideoSessionSnapshot value, $Res Function(VideoSessionSnapshot) _then) = _$VideoSessionSnapshotCopyWithImpl;
@useResult
$Res call({
 String sessionId, String deviceId, String name, VideoSessionKind kind, VideoSessionStatus status, String? packageName, int captureGeneration, int generation, int createdAt, VideoQuality? quality, VideoCodec? videoCodec, String? videoEncoder, String? captureRef, String? videoSourceId, int? width, int? height, int? textureId, bool paused, bool awaitingSession, bool capturePaused, bool audio, int? apiLevel, bool displayAuto, int? displayWidth, int? displayHeight, int? displayDensity, int? displayId, String? launchOperationId, VideoLaunchOutcome? launchOutcome, int? taskId, String? failureCode, String? reason, int? frameCount, int? lastFrameAt, int? framesDecoded, int? presentationTimeUs, String? decoder, String? renderer, bool? hardwareAccelerated, String? hardwareAcceleration, int? decodedWidth, int? decodedHeight, int? processId, int? processStarted, bool qualityRebuilding, int? qualityRebuildTarget, VideoQualityRebuildOutcome? qualityRebuildOutcome, bool qualityRetryable, String? qualityFailureCode, VideoDisplayOutcome? displayOutcome, String? displayFailureCode, bool recordOnly, String? linkedSessionId
});


$VideoQualityCopyWith<$Res>? get quality;

}
/// @nodoc
class _$VideoSessionSnapshotCopyWithImpl<$Res>
    implements $VideoSessionSnapshotCopyWith<$Res> {
  _$VideoSessionSnapshotCopyWithImpl(this._self, this._then);

  final VideoSessionSnapshot _self;
  final $Res Function(VideoSessionSnapshot) _then;

/// Create a copy of VideoSessionSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? deviceId = null,Object? name = null,Object? kind = null,Object? status = null,Object? packageName = freezed,Object? captureGeneration = null,Object? generation = null,Object? createdAt = null,Object? quality = freezed,Object? videoCodec = freezed,Object? videoEncoder = freezed,Object? captureRef = freezed,Object? videoSourceId = freezed,Object? width = freezed,Object? height = freezed,Object? textureId = freezed,Object? paused = null,Object? awaitingSession = null,Object? capturePaused = null,Object? audio = null,Object? apiLevel = freezed,Object? displayAuto = null,Object? displayWidth = freezed,Object? displayHeight = freezed,Object? displayDensity = freezed,Object? displayId = freezed,Object? launchOperationId = freezed,Object? launchOutcome = freezed,Object? taskId = freezed,Object? failureCode = freezed,Object? reason = freezed,Object? frameCount = freezed,Object? lastFrameAt = freezed,Object? framesDecoded = freezed,Object? presentationTimeUs = freezed,Object? decoder = freezed,Object? renderer = freezed,Object? hardwareAccelerated = freezed,Object? hardwareAcceleration = freezed,Object? decodedWidth = freezed,Object? decodedHeight = freezed,Object? processId = freezed,Object? processStarted = freezed,Object? qualityRebuilding = null,Object? qualityRebuildTarget = freezed,Object? qualityRebuildOutcome = freezed,Object? qualityRetryable = null,Object? qualityFailureCode = freezed,Object? displayOutcome = freezed,Object? displayFailureCode = freezed,Object? recordOnly = null,Object? linkedSessionId = freezed,}) {
  return _then(VideoSessionSnapshot(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as VideoSessionKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as VideoSessionStatus,packageName: freezed == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String?,captureGeneration: null == captureGeneration ? _self.captureGeneration : captureGeneration // ignore: cast_nullable_to_non_nullable
as int,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as VideoQuality?,videoCodec: freezed == videoCodec ? _self.videoCodec : videoCodec // ignore: cast_nullable_to_non_nullable
as VideoCodec?,videoEncoder: freezed == videoEncoder ? _self.videoEncoder : videoEncoder // ignore: cast_nullable_to_non_nullable
as String?,captureRef: freezed == captureRef ? _self.captureRef : captureRef // ignore: cast_nullable_to_non_nullable
as String?,videoSourceId: freezed == videoSourceId ? _self.videoSourceId : videoSourceId // ignore: cast_nullable_to_non_nullable
as String?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,textureId: freezed == textureId ? _self.textureId : textureId // ignore: cast_nullable_to_non_nullable
as int?,paused: null == paused ? _self.paused : paused // ignore: cast_nullable_to_non_nullable
as bool,awaitingSession: null == awaitingSession ? _self.awaitingSession : awaitingSession // ignore: cast_nullable_to_non_nullable
as bool,capturePaused: null == capturePaused ? _self.capturePaused : capturePaused // ignore: cast_nullable_to_non_nullable
as bool,audio: null == audio ? _self.audio : audio // ignore: cast_nullable_to_non_nullable
as bool,apiLevel: freezed == apiLevel ? _self.apiLevel : apiLevel // ignore: cast_nullable_to_non_nullable
as int?,displayAuto: null == displayAuto ? _self.displayAuto : displayAuto // ignore: cast_nullable_to_non_nullable
as bool,displayWidth: freezed == displayWidth ? _self.displayWidth : displayWidth // ignore: cast_nullable_to_non_nullable
as int?,displayHeight: freezed == displayHeight ? _self.displayHeight : displayHeight // ignore: cast_nullable_to_non_nullable
as int?,displayDensity: freezed == displayDensity ? _self.displayDensity : displayDensity // ignore: cast_nullable_to_non_nullable
as int?,displayId: freezed == displayId ? _self.displayId : displayId // ignore: cast_nullable_to_non_nullable
as int?,launchOperationId: freezed == launchOperationId ? _self.launchOperationId : launchOperationId // ignore: cast_nullable_to_non_nullable
as String?,launchOutcome: freezed == launchOutcome ? _self.launchOutcome : launchOutcome // ignore: cast_nullable_to_non_nullable
as VideoLaunchOutcome?,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as int?,failureCode: freezed == failureCode ? _self.failureCode : failureCode // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,frameCount: freezed == frameCount ? _self.frameCount : frameCount // ignore: cast_nullable_to_non_nullable
as int?,lastFrameAt: freezed == lastFrameAt ? _self.lastFrameAt : lastFrameAt // ignore: cast_nullable_to_non_nullable
as int?,framesDecoded: freezed == framesDecoded ? _self.framesDecoded : framesDecoded // ignore: cast_nullable_to_non_nullable
as int?,presentationTimeUs: freezed == presentationTimeUs ? _self.presentationTimeUs : presentationTimeUs // ignore: cast_nullable_to_non_nullable
as int?,decoder: freezed == decoder ? _self.decoder : decoder // ignore: cast_nullable_to_non_nullable
as String?,renderer: freezed == renderer ? _self.renderer : renderer // ignore: cast_nullable_to_non_nullable
as String?,hardwareAccelerated: freezed == hardwareAccelerated ? _self.hardwareAccelerated : hardwareAccelerated // ignore: cast_nullable_to_non_nullable
as bool?,hardwareAcceleration: freezed == hardwareAcceleration ? _self.hardwareAcceleration : hardwareAcceleration // ignore: cast_nullable_to_non_nullable
as String?,decodedWidth: freezed == decodedWidth ? _self.decodedWidth : decodedWidth // ignore: cast_nullable_to_non_nullable
as int?,decodedHeight: freezed == decodedHeight ? _self.decodedHeight : decodedHeight // ignore: cast_nullable_to_non_nullable
as int?,processId: freezed == processId ? _self.processId : processId // ignore: cast_nullable_to_non_nullable
as int?,processStarted: freezed == processStarted ? _self.processStarted : processStarted // ignore: cast_nullable_to_non_nullable
as int?,qualityRebuilding: null == qualityRebuilding ? _self.qualityRebuilding : qualityRebuilding // ignore: cast_nullable_to_non_nullable
as bool,qualityRebuildTarget: freezed == qualityRebuildTarget ? _self.qualityRebuildTarget : qualityRebuildTarget // ignore: cast_nullable_to_non_nullable
as int?,qualityRebuildOutcome: freezed == qualityRebuildOutcome ? _self.qualityRebuildOutcome : qualityRebuildOutcome // ignore: cast_nullable_to_non_nullable
as VideoQualityRebuildOutcome?,qualityRetryable: null == qualityRetryable ? _self.qualityRetryable : qualityRetryable // ignore: cast_nullable_to_non_nullable
as bool,qualityFailureCode: freezed == qualityFailureCode ? _self.qualityFailureCode : qualityFailureCode // ignore: cast_nullable_to_non_nullable
as String?,displayOutcome: freezed == displayOutcome ? _self.displayOutcome : displayOutcome // ignore: cast_nullable_to_non_nullable
as VideoDisplayOutcome?,displayFailureCode: freezed == displayFailureCode ? _self.displayFailureCode : displayFailureCode // ignore: cast_nullable_to_non_nullable
as String?,recordOnly: null == recordOnly ? _self.recordOnly : recordOnly // ignore: cast_nullable_to_non_nullable
as bool,linkedSessionId: freezed == linkedSessionId ? _self.linkedSessionId : linkedSessionId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of VideoSessionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoQualityCopyWith<$Res>? get quality {
    if (_self.quality == null) {
    return null;
  }

  return $VideoQualityCopyWith<$Res>(_self.quality!, (value) {
    return _then(_self.copyWith(quality: value));
  });
}
}


/// Adds pattern-matching-related methods to [VideoSessionSnapshot].
extension VideoSessionSnapshotPatterns on VideoSessionSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoSessionSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoSessionSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoSessionSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _VideoSessionSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoSessionSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _VideoSessionSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sessionId,  String deviceId,  String name,  VideoSessionKind kind,  VideoSessionStatus status,  String? packageName,  int captureGeneration,  int generation,  int createdAt,  VideoQuality? quality,  VideoCodec? videoCodec,  String? videoEncoder,  String? captureRef,  String? videoSourceId,  int? width,  int? height,  int? textureId,  bool paused,  bool awaitingSession,  bool capturePaused,  bool audio,  int? apiLevel,  bool displayAuto,  int? displayWidth,  int? displayHeight,  int? displayDensity,  int? displayId,  String? launchOperationId,  VideoLaunchOutcome? launchOutcome,  int? taskId,  String? failureCode,  String? reason,  int? frameCount,  int? lastFrameAt,  int? framesDecoded,  int? presentationTimeUs,  String? decoder,  String? renderer,  bool? hardwareAccelerated,  String? hardwareAcceleration,  int? decodedWidth,  int? decodedHeight,  int? processId,  int? processStarted,  bool qualityRebuilding,  int? qualityRebuildTarget,  VideoQualityRebuildOutcome? qualityRebuildOutcome,  bool qualityRetryable,  String? qualityFailureCode,  VideoDisplayOutcome? displayOutcome,  String? displayFailureCode,  bool recordOnly,  String? linkedSessionId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoSessionSnapshot() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.name,_that.kind,_that.status,_that.packageName,_that.captureGeneration,_that.generation,_that.createdAt,_that.quality,_that.videoCodec,_that.videoEncoder,_that.captureRef,_that.videoSourceId,_that.width,_that.height,_that.textureId,_that.paused,_that.awaitingSession,_that.capturePaused,_that.audio,_that.apiLevel,_that.displayAuto,_that.displayWidth,_that.displayHeight,_that.displayDensity,_that.displayId,_that.launchOperationId,_that.launchOutcome,_that.taskId,_that.failureCode,_that.reason,_that.frameCount,_that.lastFrameAt,_that.framesDecoded,_that.presentationTimeUs,_that.decoder,_that.renderer,_that.hardwareAccelerated,_that.hardwareAcceleration,_that.decodedWidth,_that.decodedHeight,_that.processId,_that.processStarted,_that.qualityRebuilding,_that.qualityRebuildTarget,_that.qualityRebuildOutcome,_that.qualityRetryable,_that.qualityFailureCode,_that.displayOutcome,_that.displayFailureCode,_that.recordOnly,_that.linkedSessionId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sessionId,  String deviceId,  String name,  VideoSessionKind kind,  VideoSessionStatus status,  String? packageName,  int captureGeneration,  int generation,  int createdAt,  VideoQuality? quality,  VideoCodec? videoCodec,  String? videoEncoder,  String? captureRef,  String? videoSourceId,  int? width,  int? height,  int? textureId,  bool paused,  bool awaitingSession,  bool capturePaused,  bool audio,  int? apiLevel,  bool displayAuto,  int? displayWidth,  int? displayHeight,  int? displayDensity,  int? displayId,  String? launchOperationId,  VideoLaunchOutcome? launchOutcome,  int? taskId,  String? failureCode,  String? reason,  int? frameCount,  int? lastFrameAt,  int? framesDecoded,  int? presentationTimeUs,  String? decoder,  String? renderer,  bool? hardwareAccelerated,  String? hardwareAcceleration,  int? decodedWidth,  int? decodedHeight,  int? processId,  int? processStarted,  bool qualityRebuilding,  int? qualityRebuildTarget,  VideoQualityRebuildOutcome? qualityRebuildOutcome,  bool qualityRetryable,  String? qualityFailureCode,  VideoDisplayOutcome? displayOutcome,  String? displayFailureCode,  bool recordOnly,  String? linkedSessionId)  $default,) {final _that = this;
switch (_that) {
case _VideoSessionSnapshot():
return $default(_that.sessionId,_that.deviceId,_that.name,_that.kind,_that.status,_that.packageName,_that.captureGeneration,_that.generation,_that.createdAt,_that.quality,_that.videoCodec,_that.videoEncoder,_that.captureRef,_that.videoSourceId,_that.width,_that.height,_that.textureId,_that.paused,_that.awaitingSession,_that.capturePaused,_that.audio,_that.apiLevel,_that.displayAuto,_that.displayWidth,_that.displayHeight,_that.displayDensity,_that.displayId,_that.launchOperationId,_that.launchOutcome,_that.taskId,_that.failureCode,_that.reason,_that.frameCount,_that.lastFrameAt,_that.framesDecoded,_that.presentationTimeUs,_that.decoder,_that.renderer,_that.hardwareAccelerated,_that.hardwareAcceleration,_that.decodedWidth,_that.decodedHeight,_that.processId,_that.processStarted,_that.qualityRebuilding,_that.qualityRebuildTarget,_that.qualityRebuildOutcome,_that.qualityRetryable,_that.qualityFailureCode,_that.displayOutcome,_that.displayFailureCode,_that.recordOnly,_that.linkedSessionId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sessionId,  String deviceId,  String name,  VideoSessionKind kind,  VideoSessionStatus status,  String? packageName,  int captureGeneration,  int generation,  int createdAt,  VideoQuality? quality,  VideoCodec? videoCodec,  String? videoEncoder,  String? captureRef,  String? videoSourceId,  int? width,  int? height,  int? textureId,  bool paused,  bool awaitingSession,  bool capturePaused,  bool audio,  int? apiLevel,  bool displayAuto,  int? displayWidth,  int? displayHeight,  int? displayDensity,  int? displayId,  String? launchOperationId,  VideoLaunchOutcome? launchOutcome,  int? taskId,  String? failureCode,  String? reason,  int? frameCount,  int? lastFrameAt,  int? framesDecoded,  int? presentationTimeUs,  String? decoder,  String? renderer,  bool? hardwareAccelerated,  String? hardwareAcceleration,  int? decodedWidth,  int? decodedHeight,  int? processId,  int? processStarted,  bool qualityRebuilding,  int? qualityRebuildTarget,  VideoQualityRebuildOutcome? qualityRebuildOutcome,  bool qualityRetryable,  String? qualityFailureCode,  VideoDisplayOutcome? displayOutcome,  String? displayFailureCode,  bool recordOnly,  String? linkedSessionId)?  $default,) {final _that = this;
switch (_that) {
case _VideoSessionSnapshot() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.name,_that.kind,_that.status,_that.packageName,_that.captureGeneration,_that.generation,_that.createdAt,_that.quality,_that.videoCodec,_that.videoEncoder,_that.captureRef,_that.videoSourceId,_that.width,_that.height,_that.textureId,_that.paused,_that.awaitingSession,_that.capturePaused,_that.audio,_that.apiLevel,_that.displayAuto,_that.displayWidth,_that.displayHeight,_that.displayDensity,_that.displayId,_that.launchOperationId,_that.launchOutcome,_that.taskId,_that.failureCode,_that.reason,_that.frameCount,_that.lastFrameAt,_that.framesDecoded,_that.presentationTimeUs,_that.decoder,_that.renderer,_that.hardwareAccelerated,_that.hardwareAcceleration,_that.decodedWidth,_that.decodedHeight,_that.processId,_that.processStarted,_that.qualityRebuilding,_that.qualityRebuildTarget,_that.qualityRebuildOutcome,_that.qualityRetryable,_that.qualityFailureCode,_that.displayOutcome,_that.displayFailureCode,_that.recordOnly,_that.linkedSessionId);case _:
  return null;

}
}

}

/// @nodoc


class _VideoSessionSnapshot extends VideoSessionSnapshot {
  const _VideoSessionSnapshot({required this.sessionId, required this.deviceId, required this.name, required this.kind, required this.status, this.packageName, this.captureGeneration = 0, this.generation = 0, this.createdAt = 0, this.quality, this.videoCodec, this.videoEncoder, this.captureRef, this.videoSourceId, this.width, this.height, this.textureId, this.paused = false, this.awaitingSession = false, this.capturePaused = false, this.audio = false, this.apiLevel, this.displayAuto = false, this.displayWidth, this.displayHeight, this.displayDensity, this.displayId, this.launchOperationId, this.launchOutcome, this.taskId, this.failureCode, this.reason, this.frameCount, this.lastFrameAt, this.framesDecoded, this.presentationTimeUs, this.decoder, this.renderer, this.hardwareAccelerated, this.hardwareAcceleration, this.decodedWidth, this.decodedHeight, this.processId, this.processStarted, this.qualityRebuilding = false, this.qualityRebuildTarget, this.qualityRebuildOutcome, this.qualityRetryable = false, this.qualityFailureCode, this.displayOutcome, this.displayFailureCode, this.recordOnly = false, this.linkedSessionId}): super._();
  

@override final  String sessionId;
@override final  String deviceId;
@override final  String name;
@override final  VideoSessionKind kind;
@override final  VideoSessionStatus status;
@override final  String? packageName;
@override@JsonKey() final  int captureGeneration;
@override@JsonKey() final  int generation;
@override@JsonKey() final  int createdAt;
@override final  VideoQuality? quality;
@override final  VideoCodec? videoCodec;
@override final  String? videoEncoder;
@override final  String? captureRef;
@override final  String? videoSourceId;
@override final  int? width;
@override final  int? height;
@override final  int? textureId;
@override@JsonKey() final  bool paused;
@override@JsonKey() final  bool awaitingSession;
@override@JsonKey() final  bool capturePaused;
@override@JsonKey() final  bool audio;
@override final  int? apiLevel;
@override@JsonKey() final  bool displayAuto;
@override final  int? displayWidth;
@override final  int? displayHeight;
@override final  int? displayDensity;
@override final  int? displayId;
@override final  String? launchOperationId;
@override final  VideoLaunchOutcome? launchOutcome;
@override final  int? taskId;
@override final  String? failureCode;
@override final  String? reason;
@override final  int? frameCount;
@override final  int? lastFrameAt;
@override final  int? framesDecoded;
@override final  int? presentationTimeUs;
@override final  String? decoder;
@override final  String? renderer;
@override final  bool? hardwareAccelerated;
@override final  String? hardwareAcceleration;
@override final  int? decodedWidth;
@override final  int? decodedHeight;
@override final  int? processId;
@override final  int? processStarted;
@override@JsonKey() final  bool qualityRebuilding;
@override final  int? qualityRebuildTarget;
@override final  VideoQualityRebuildOutcome? qualityRebuildOutcome;
@override@JsonKey() final  bool qualityRetryable;
@override final  String? qualityFailureCode;
@override final  VideoDisplayOutcome? displayOutcome;
@override final  String? displayFailureCode;
@override@JsonKey() final  bool recordOnly;
@override final  String? linkedSessionId;

/// Create a copy of VideoSessionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoSessionSnapshotCopyWith<_VideoSessionSnapshot> get copyWith => __$VideoSessionSnapshotCopyWithImpl<_VideoSessionSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoSessionSnapshot&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.name, name) || other.name == name)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&(identical(other.packageName, packageName) || other.packageName == packageName)&&(identical(other.captureGeneration, captureGeneration) || other.captureGeneration == captureGeneration)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.videoCodec, videoCodec) || other.videoCodec == videoCodec)&&(identical(other.videoEncoder, videoEncoder) || other.videoEncoder == videoEncoder)&&(identical(other.captureRef, captureRef) || other.captureRef == captureRef)&&(identical(other.videoSourceId, videoSourceId) || other.videoSourceId == videoSourceId)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.textureId, textureId) || other.textureId == textureId)&&(identical(other.paused, paused) || other.paused == paused)&&(identical(other.awaitingSession, awaitingSession) || other.awaitingSession == awaitingSession)&&(identical(other.capturePaused, capturePaused) || other.capturePaused == capturePaused)&&(identical(other.audio, audio) || other.audio == audio)&&(identical(other.apiLevel, apiLevel) || other.apiLevel == apiLevel)&&(identical(other.displayAuto, displayAuto) || other.displayAuto == displayAuto)&&(identical(other.displayWidth, displayWidth) || other.displayWidth == displayWidth)&&(identical(other.displayHeight, displayHeight) || other.displayHeight == displayHeight)&&(identical(other.displayDensity, displayDensity) || other.displayDensity == displayDensity)&&(identical(other.displayId, displayId) || other.displayId == displayId)&&(identical(other.launchOperationId, launchOperationId) || other.launchOperationId == launchOperationId)&&(identical(other.launchOutcome, launchOutcome) || other.launchOutcome == launchOutcome)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.failureCode, failureCode) || other.failureCode == failureCode)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.frameCount, frameCount) || other.frameCount == frameCount)&&(identical(other.lastFrameAt, lastFrameAt) || other.lastFrameAt == lastFrameAt)&&(identical(other.framesDecoded, framesDecoded) || other.framesDecoded == framesDecoded)&&(identical(other.presentationTimeUs, presentationTimeUs) || other.presentationTimeUs == presentationTimeUs)&&(identical(other.decoder, decoder) || other.decoder == decoder)&&(identical(other.renderer, renderer) || other.renderer == renderer)&&(identical(other.hardwareAccelerated, hardwareAccelerated) || other.hardwareAccelerated == hardwareAccelerated)&&(identical(other.hardwareAcceleration, hardwareAcceleration) || other.hardwareAcceleration == hardwareAcceleration)&&(identical(other.decodedWidth, decodedWidth) || other.decodedWidth == decodedWidth)&&(identical(other.decodedHeight, decodedHeight) || other.decodedHeight == decodedHeight)&&(identical(other.processId, processId) || other.processId == processId)&&(identical(other.processStarted, processStarted) || other.processStarted == processStarted)&&(identical(other.qualityRebuilding, qualityRebuilding) || other.qualityRebuilding == qualityRebuilding)&&(identical(other.qualityRebuildTarget, qualityRebuildTarget) || other.qualityRebuildTarget == qualityRebuildTarget)&&(identical(other.qualityRebuildOutcome, qualityRebuildOutcome) || other.qualityRebuildOutcome == qualityRebuildOutcome)&&(identical(other.qualityRetryable, qualityRetryable) || other.qualityRetryable == qualityRetryable)&&(identical(other.qualityFailureCode, qualityFailureCode) || other.qualityFailureCode == qualityFailureCode)&&(identical(other.displayOutcome, displayOutcome) || other.displayOutcome == displayOutcome)&&(identical(other.displayFailureCode, displayFailureCode) || other.displayFailureCode == displayFailureCode)&&(identical(other.recordOnly, recordOnly) || other.recordOnly == recordOnly)&&(identical(other.linkedSessionId, linkedSessionId) || other.linkedSessionId == linkedSessionId));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,sessionId,deviceId,name,kind,status,packageName,captureGeneration,generation,createdAt,quality,videoCodec,videoEncoder,captureRef,videoSourceId,width,height,textureId,paused,awaitingSession,capturePaused,audio,apiLevel,displayAuto,displayWidth,displayHeight,displayDensity,displayId,launchOperationId,launchOutcome,taskId,failureCode,reason,frameCount,lastFrameAt,framesDecoded,presentationTimeUs,decoder,renderer,hardwareAccelerated,hardwareAcceleration,decodedWidth,decodedHeight,processId,processStarted,qualityRebuilding,qualityRebuildTarget,qualityRebuildOutcome,qualityRetryable,qualityFailureCode,displayOutcome,displayFailureCode,recordOnly,linkedSessionId]);
}

@override
String toString() {
    return 'VideoSessionSnapshot(sessionId: $sessionId, deviceId: $deviceId, name: $name, kind: $kind, status: $status, packageName: $packageName, captureGeneration: $captureGeneration, generation: $generation, createdAt: $createdAt, quality: $quality, videoCodec: $videoCodec, videoEncoder: $videoEncoder, captureRef: $captureRef, videoSourceId: $videoSourceId, width: $width, height: $height, textureId: $textureId, paused: $paused, awaitingSession: $awaitingSession, capturePaused: $capturePaused, audio: $audio, apiLevel: $apiLevel, displayAuto: $displayAuto, displayWidth: $displayWidth, displayHeight: $displayHeight, displayDensity: $displayDensity, displayId: $displayId, launchOperationId: $launchOperationId, launchOutcome: $launchOutcome, taskId: $taskId, failureCode: $failureCode, reason: $reason, frameCount: $frameCount, lastFrameAt: $lastFrameAt, framesDecoded: $framesDecoded, presentationTimeUs: $presentationTimeUs, decoder: $decoder, renderer: $renderer, hardwareAccelerated: $hardwareAccelerated, hardwareAcceleration: $hardwareAcceleration, decodedWidth: $decodedWidth, decodedHeight: $decodedHeight, processId: $processId, processStarted: $processStarted, qualityRebuilding: $qualityRebuilding, qualityRebuildTarget: $qualityRebuildTarget, qualityRebuildOutcome: $qualityRebuildOutcome, qualityRetryable: $qualityRetryable, qualityFailureCode: $qualityFailureCode, displayOutcome: $displayOutcome, displayFailureCode: $displayFailureCode, recordOnly: $recordOnly, linkedSessionId: $linkedSessionId)';
}


}

/// @nodoc
abstract mixin class _$VideoSessionSnapshotCopyWith<$Res> implements $VideoSessionSnapshotCopyWith<$Res> {
  factory _$VideoSessionSnapshotCopyWith(_VideoSessionSnapshot value, $Res Function(_VideoSessionSnapshot) _then) = __$VideoSessionSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String sessionId, String deviceId, String name, VideoSessionKind kind, VideoSessionStatus status, String? packageName, int captureGeneration, int generation, int createdAt, VideoQuality? quality, VideoCodec? videoCodec, String? videoEncoder, String? captureRef, String? videoSourceId, int? width, int? height, int? textureId, bool paused, bool awaitingSession, bool capturePaused, bool audio, int? apiLevel, bool displayAuto, int? displayWidth, int? displayHeight, int? displayDensity, int? displayId, String? launchOperationId, VideoLaunchOutcome? launchOutcome, int? taskId, String? failureCode, String? reason, int? frameCount, int? lastFrameAt, int? framesDecoded, int? presentationTimeUs, String? decoder, String? renderer, bool? hardwareAccelerated, String? hardwareAcceleration, int? decodedWidth, int? decodedHeight, int? processId, int? processStarted, bool qualityRebuilding, int? qualityRebuildTarget, VideoQualityRebuildOutcome? qualityRebuildOutcome, bool qualityRetryable, String? qualityFailureCode, VideoDisplayOutcome? displayOutcome, String? displayFailureCode, bool recordOnly, String? linkedSessionId
});


@override $VideoQualityCopyWith<$Res>? get quality;

}
/// @nodoc
class __$VideoSessionSnapshotCopyWithImpl<$Res>
    implements _$VideoSessionSnapshotCopyWith<$Res> {
  __$VideoSessionSnapshotCopyWithImpl(this._self, this._then);

  final _VideoSessionSnapshot _self;
  final $Res Function(_VideoSessionSnapshot) _then;

/// Create a copy of VideoSessionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? deviceId = null,Object? name = null,Object? kind = null,Object? status = null,Object? packageName = freezed,Object? captureGeneration = null,Object? generation = null,Object? createdAt = null,Object? quality = freezed,Object? videoCodec = freezed,Object? videoEncoder = freezed,Object? captureRef = freezed,Object? videoSourceId = freezed,Object? width = freezed,Object? height = freezed,Object? textureId = freezed,Object? paused = null,Object? awaitingSession = null,Object? capturePaused = null,Object? audio = null,Object? apiLevel = freezed,Object? displayAuto = null,Object? displayWidth = freezed,Object? displayHeight = freezed,Object? displayDensity = freezed,Object? displayId = freezed,Object? launchOperationId = freezed,Object? launchOutcome = freezed,Object? taskId = freezed,Object? failureCode = freezed,Object? reason = freezed,Object? frameCount = freezed,Object? lastFrameAt = freezed,Object? framesDecoded = freezed,Object? presentationTimeUs = freezed,Object? decoder = freezed,Object? renderer = freezed,Object? hardwareAccelerated = freezed,Object? hardwareAcceleration = freezed,Object? decodedWidth = freezed,Object? decodedHeight = freezed,Object? processId = freezed,Object? processStarted = freezed,Object? qualityRebuilding = null,Object? qualityRebuildTarget = freezed,Object? qualityRebuildOutcome = freezed,Object? qualityRetryable = null,Object? qualityFailureCode = freezed,Object? displayOutcome = freezed,Object? displayFailureCode = freezed,Object? recordOnly = null,Object? linkedSessionId = freezed,}) {
  return _then(_VideoSessionSnapshot(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as VideoSessionKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as VideoSessionStatus,packageName: freezed == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String?,captureGeneration: null == captureGeneration ? _self.captureGeneration : captureGeneration // ignore: cast_nullable_to_non_nullable
as int,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as VideoQuality?,videoCodec: freezed == videoCodec ? _self.videoCodec : videoCodec // ignore: cast_nullable_to_non_nullable
as VideoCodec?,videoEncoder: freezed == videoEncoder ? _self.videoEncoder : videoEncoder // ignore: cast_nullable_to_non_nullable
as String?,captureRef: freezed == captureRef ? _self.captureRef : captureRef // ignore: cast_nullable_to_non_nullable
as String?,videoSourceId: freezed == videoSourceId ? _self.videoSourceId : videoSourceId // ignore: cast_nullable_to_non_nullable
as String?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,textureId: freezed == textureId ? _self.textureId : textureId // ignore: cast_nullable_to_non_nullable
as int?,paused: null == paused ? _self.paused : paused // ignore: cast_nullable_to_non_nullable
as bool,awaitingSession: null == awaitingSession ? _self.awaitingSession : awaitingSession // ignore: cast_nullable_to_non_nullable
as bool,capturePaused: null == capturePaused ? _self.capturePaused : capturePaused // ignore: cast_nullable_to_non_nullable
as bool,audio: null == audio ? _self.audio : audio // ignore: cast_nullable_to_non_nullable
as bool,apiLevel: freezed == apiLevel ? _self.apiLevel : apiLevel // ignore: cast_nullable_to_non_nullable
as int?,displayAuto: null == displayAuto ? _self.displayAuto : displayAuto // ignore: cast_nullable_to_non_nullable
as bool,displayWidth: freezed == displayWidth ? _self.displayWidth : displayWidth // ignore: cast_nullable_to_non_nullable
as int?,displayHeight: freezed == displayHeight ? _self.displayHeight : displayHeight // ignore: cast_nullable_to_non_nullable
as int?,displayDensity: freezed == displayDensity ? _self.displayDensity : displayDensity // ignore: cast_nullable_to_non_nullable
as int?,displayId: freezed == displayId ? _self.displayId : displayId // ignore: cast_nullable_to_non_nullable
as int?,launchOperationId: freezed == launchOperationId ? _self.launchOperationId : launchOperationId // ignore: cast_nullable_to_non_nullable
as String?,launchOutcome: freezed == launchOutcome ? _self.launchOutcome : launchOutcome // ignore: cast_nullable_to_non_nullable
as VideoLaunchOutcome?,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as int?,failureCode: freezed == failureCode ? _self.failureCode : failureCode // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,frameCount: freezed == frameCount ? _self.frameCount : frameCount // ignore: cast_nullable_to_non_nullable
as int?,lastFrameAt: freezed == lastFrameAt ? _self.lastFrameAt : lastFrameAt // ignore: cast_nullable_to_non_nullable
as int?,framesDecoded: freezed == framesDecoded ? _self.framesDecoded : framesDecoded // ignore: cast_nullable_to_non_nullable
as int?,presentationTimeUs: freezed == presentationTimeUs ? _self.presentationTimeUs : presentationTimeUs // ignore: cast_nullable_to_non_nullable
as int?,decoder: freezed == decoder ? _self.decoder : decoder // ignore: cast_nullable_to_non_nullable
as String?,renderer: freezed == renderer ? _self.renderer : renderer // ignore: cast_nullable_to_non_nullable
as String?,hardwareAccelerated: freezed == hardwareAccelerated ? _self.hardwareAccelerated : hardwareAccelerated // ignore: cast_nullable_to_non_nullable
as bool?,hardwareAcceleration: freezed == hardwareAcceleration ? _self.hardwareAcceleration : hardwareAcceleration // ignore: cast_nullable_to_non_nullable
as String?,decodedWidth: freezed == decodedWidth ? _self.decodedWidth : decodedWidth // ignore: cast_nullable_to_non_nullable
as int?,decodedHeight: freezed == decodedHeight ? _self.decodedHeight : decodedHeight // ignore: cast_nullable_to_non_nullable
as int?,processId: freezed == processId ? _self.processId : processId // ignore: cast_nullable_to_non_nullable
as int?,processStarted: freezed == processStarted ? _self.processStarted : processStarted // ignore: cast_nullable_to_non_nullable
as int?,qualityRebuilding: null == qualityRebuilding ? _self.qualityRebuilding : qualityRebuilding // ignore: cast_nullable_to_non_nullable
as bool,qualityRebuildTarget: freezed == qualityRebuildTarget ? _self.qualityRebuildTarget : qualityRebuildTarget // ignore: cast_nullable_to_non_nullable
as int?,qualityRebuildOutcome: freezed == qualityRebuildOutcome ? _self.qualityRebuildOutcome : qualityRebuildOutcome // ignore: cast_nullable_to_non_nullable
as VideoQualityRebuildOutcome?,qualityRetryable: null == qualityRetryable ? _self.qualityRetryable : qualityRetryable // ignore: cast_nullable_to_non_nullable
as bool,qualityFailureCode: freezed == qualityFailureCode ? _self.qualityFailureCode : qualityFailureCode // ignore: cast_nullable_to_non_nullable
as String?,displayOutcome: freezed == displayOutcome ? _self.displayOutcome : displayOutcome // ignore: cast_nullable_to_non_nullable
as VideoDisplayOutcome?,displayFailureCode: freezed == displayFailureCode ? _self.displayFailureCode : displayFailureCode // ignore: cast_nullable_to_non_nullable
as String?,recordOnly: null == recordOnly ? _self.recordOnly : recordOnly // ignore: cast_nullable_to_non_nullable
as bool,linkedSessionId: freezed == linkedSessionId ? _self.linkedSessionId : linkedSessionId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of VideoSessionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoQualityCopyWith<$Res>? get quality {
    if (_self.quality == null) {
    return null;
  }

  return $VideoQualityCopyWith<$Res>(_self.quality!, (value) {
    return _then(_self.copyWith(quality: value));
  });
}
}

/// @nodoc
mixin _$VideoSessionPlan {

 String get deviceId; String? get sessionId; String? get name; String? get packageName; VideoDisplaySize? get displaySize; bool get displayAuto;
/// Create a copy of VideoSessionPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoSessionPlanCopyWith<VideoSessionPlan> get copyWith => _$VideoSessionPlanCopyWithImpl<VideoSessionPlan>(this as VideoSessionPlan, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoSessionPlan;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoSessionPlan&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.packageName, _this.packageName) || other.packageName == _this.packageName)&&(identical(other.displaySize, _this.displaySize) || other.displaySize == _this.displaySize)&&(identical(other.displayAuto, _this.displayAuto) || other.displayAuto == _this.displayAuto));
}


@override
int get hashCode {
  final _this = this as VideoSessionPlan;
  return Object.hash(runtimeType,_this.deviceId,_this.sessionId,_this.name,_this.packageName,_this.displaySize,_this.displayAuto);
}

@override
String toString() {
  final _this = this as VideoSessionPlan;
  return 'VideoSessionPlan(deviceId: ${_this.deviceId}, sessionId: ${_this.sessionId}, name: ${_this.name}, packageName: ${_this.packageName}, displaySize: ${_this.displaySize}, displayAuto: ${_this.displayAuto})';
}


}

/// @nodoc
abstract mixin class $VideoSessionPlanCopyWith<$Res>  {
  factory $VideoSessionPlanCopyWith(VideoSessionPlan value, $Res Function(VideoSessionPlan) _then) = _$VideoSessionPlanCopyWithImpl;
@useResult
$Res call({
 String deviceId, String? sessionId, String? name, String? packageName, VideoDisplaySize? displaySize, bool displayAuto
});




}
/// @nodoc
class _$VideoSessionPlanCopyWithImpl<$Res>
    implements $VideoSessionPlanCopyWith<$Res> {
  _$VideoSessionPlanCopyWithImpl(this._self, this._then);

  final VideoSessionPlan _self;
  final $Res Function(VideoSessionPlan) _then;

/// Create a copy of VideoSessionPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? sessionId = freezed,Object? name = freezed,Object? packageName = freezed,Object? displaySize = freezed,Object? displayAuto = null,}) {
  return _then(VideoSessionPlan(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,packageName: freezed == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String?,displaySize: freezed == displaySize ? _self.displaySize : displaySize // ignore: cast_nullable_to_non_nullable
as VideoDisplaySize?,displayAuto: null == displayAuto ? _self.displayAuto : displayAuto // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoSessionPlan].
extension VideoSessionPlanPatterns on VideoSessionPlan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoSessionPlan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoSessionPlan() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoSessionPlan value)  $default,){
final _that = this;
switch (_that) {
case _VideoSessionPlan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoSessionPlan value)?  $default,){
final _that = this;
switch (_that) {
case _VideoSessionPlan() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  String? sessionId,  String? name,  String? packageName,  VideoDisplaySize? displaySize,  bool displayAuto)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoSessionPlan() when $default != null:
return $default(_that.deviceId,_that.sessionId,_that.name,_that.packageName,_that.displaySize,_that.displayAuto);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  String? sessionId,  String? name,  String? packageName,  VideoDisplaySize? displaySize,  bool displayAuto)  $default,) {final _that = this;
switch (_that) {
case _VideoSessionPlan():
return $default(_that.deviceId,_that.sessionId,_that.name,_that.packageName,_that.displaySize,_that.displayAuto);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  String? sessionId,  String? name,  String? packageName,  VideoDisplaySize? displaySize,  bool displayAuto)?  $default,) {final _that = this;
switch (_that) {
case _VideoSessionPlan() when $default != null:
return $default(_that.deviceId,_that.sessionId,_that.name,_that.packageName,_that.displaySize,_that.displayAuto);case _:
  return null;

}
}

}

/// @nodoc


class _VideoSessionPlan implements VideoSessionPlan {
  const _VideoSessionPlan({required this.deviceId, this.sessionId, this.name, this.packageName, this.displaySize, this.displayAuto = false});
  

@override final  String deviceId;
@override final  String? sessionId;
@override final  String? name;
@override final  String? packageName;
@override final  VideoDisplaySize? displaySize;
@override@JsonKey() final  bool displayAuto;

/// Create a copy of VideoSessionPlan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoSessionPlanCopyWith<_VideoSessionPlan> get copyWith => __$VideoSessionPlanCopyWithImpl<_VideoSessionPlan>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoSessionPlan&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.name, name) || other.name == name)&&(identical(other.packageName, packageName) || other.packageName == packageName)&&(identical(other.displaySize, displaySize) || other.displaySize == displaySize)&&(identical(other.displayAuto, displayAuto) || other.displayAuto == displayAuto));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,sessionId,name,packageName,displaySize,displayAuto);
}

@override
String toString() {
    return 'VideoSessionPlan(deviceId: $deviceId, sessionId: $sessionId, name: $name, packageName: $packageName, displaySize: $displaySize, displayAuto: $displayAuto)';
}


}

/// @nodoc
abstract mixin class _$VideoSessionPlanCopyWith<$Res> implements $VideoSessionPlanCopyWith<$Res> {
  factory _$VideoSessionPlanCopyWith(_VideoSessionPlan value, $Res Function(_VideoSessionPlan) _then) = __$VideoSessionPlanCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, String? sessionId, String? name, String? packageName, VideoDisplaySize? displaySize, bool displayAuto
});




}
/// @nodoc
class __$VideoSessionPlanCopyWithImpl<$Res>
    implements _$VideoSessionPlanCopyWith<$Res> {
  __$VideoSessionPlanCopyWithImpl(this._self, this._then);

  final _VideoSessionPlan _self;
  final $Res Function(_VideoSessionPlan) _then;

/// Create a copy of VideoSessionPlan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? sessionId = freezed,Object? name = freezed,Object? packageName = freezed,Object? displaySize = freezed,Object? displayAuto = null,}) {
  return _then(_VideoSessionPlan(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,packageName: freezed == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String?,displaySize: freezed == displaySize ? _self.displaySize : displaySize // ignore: cast_nullable_to_non_nullable
as VideoDisplaySize?,displayAuto: null == displayAuto ? _self.displayAuto : displayAuto // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
