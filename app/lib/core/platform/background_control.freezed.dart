// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'background_control.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BackgroundStatus {

 bool get supported; bool get canRequest; bool get running; bool get stopped; bool? get connectionRequested; bool? get audioRequested; bool? get mediaPlaybackReady; bool? get notificationPermission; bool? get requested; String? get platform; String get title; String get reason;
/// Create a copy of BackgroundStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackgroundStatusCopyWith<BackgroundStatus> get copyWith => _$BackgroundStatusCopyWithImpl<BackgroundStatus>(this as BackgroundStatus, _$identity);

  /// Serializes this BackgroundStatus to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BackgroundStatus;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackgroundStatus&&(identical(other.supported, _this.supported) || other.supported == _this.supported)&&(identical(other.canRequest, _this.canRequest) || other.canRequest == _this.canRequest)&&(identical(other.running, _this.running) || other.running == _this.running)&&(identical(other.stopped, _this.stopped) || other.stopped == _this.stopped)&&(identical(other.connectionRequested, _this.connectionRequested) || other.connectionRequested == _this.connectionRequested)&&(identical(other.audioRequested, _this.audioRequested) || other.audioRequested == _this.audioRequested)&&(identical(other.mediaPlaybackReady, _this.mediaPlaybackReady) || other.mediaPlaybackReady == _this.mediaPlaybackReady)&&(identical(other.notificationPermission, _this.notificationPermission) || other.notificationPermission == _this.notificationPermission)&&(identical(other.requested, _this.requested) || other.requested == _this.requested)&&(identical(other.platform, _this.platform) || other.platform == _this.platform)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BackgroundStatus;
  return Object.hash(runtimeType,_this.supported,_this.canRequest,_this.running,_this.stopped,_this.connectionRequested,_this.audioRequested,_this.mediaPlaybackReady,_this.notificationPermission,_this.requested,_this.platform,_this.title,_this.reason);
}

@override
String toString() {
  final _this = this as BackgroundStatus;
  return 'BackgroundStatus(supported: ${_this.supported}, canRequest: ${_this.canRequest}, running: ${_this.running}, stopped: ${_this.stopped}, connectionRequested: ${_this.connectionRequested}, audioRequested: ${_this.audioRequested}, mediaPlaybackReady: ${_this.mediaPlaybackReady}, notificationPermission: ${_this.notificationPermission}, requested: ${_this.requested}, platform: ${_this.platform}, title: ${_this.title}, reason: ${_this.reason})';
}


}

/// @nodoc
abstract mixin class $BackgroundStatusCopyWith<$Res>  {
  factory $BackgroundStatusCopyWith(BackgroundStatus value, $Res Function(BackgroundStatus) _then) = _$BackgroundStatusCopyWithImpl;
@useResult
$Res call({
 bool supported, bool canRequest, bool running, bool stopped, bool? connectionRequested, bool? audioRequested, bool? mediaPlaybackReady, bool? notificationPermission, bool? requested, String? platform, String title, String reason
});




}
/// @nodoc
class _$BackgroundStatusCopyWithImpl<$Res>
    implements $BackgroundStatusCopyWith<$Res> {
  _$BackgroundStatusCopyWithImpl(this._self, this._then);

  final BackgroundStatus _self;
  final $Res Function(BackgroundStatus) _then;

/// Create a copy of BackgroundStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? supported = null,Object? canRequest = null,Object? running = null,Object? stopped = null,Object? connectionRequested = freezed,Object? audioRequested = freezed,Object? mediaPlaybackReady = freezed,Object? notificationPermission = freezed,Object? requested = freezed,Object? platform = freezed,Object? title = null,Object? reason = null,}) {
  return _then(BackgroundStatus(
supported: null == supported ? _self.supported : supported // ignore: cast_nullable_to_non_nullable
as bool,canRequest: null == canRequest ? _self.canRequest : canRequest // ignore: cast_nullable_to_non_nullable
as bool,running: null == running ? _self.running : running // ignore: cast_nullable_to_non_nullable
as bool,stopped: null == stopped ? _self.stopped : stopped // ignore: cast_nullable_to_non_nullable
as bool,connectionRequested: freezed == connectionRequested ? _self.connectionRequested : connectionRequested // ignore: cast_nullable_to_non_nullable
as bool?,audioRequested: freezed == audioRequested ? _self.audioRequested : audioRequested // ignore: cast_nullable_to_non_nullable
as bool?,mediaPlaybackReady: freezed == mediaPlaybackReady ? _self.mediaPlaybackReady : mediaPlaybackReady // ignore: cast_nullable_to_non_nullable
as bool?,notificationPermission: freezed == notificationPermission ? _self.notificationPermission : notificationPermission // ignore: cast_nullable_to_non_nullable
as bool?,requested: freezed == requested ? _self.requested : requested // ignore: cast_nullable_to_non_nullable
as bool?,platform: freezed == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BackgroundStatus].
extension BackgroundStatusPatterns on BackgroundStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BackgroundStatus value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BackgroundStatus() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BackgroundStatus value)  $default,){
final _that = this;
switch (_that) {
case _BackgroundStatus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BackgroundStatus value)?  $default,){
final _that = this;
switch (_that) {
case _BackgroundStatus() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool supported,  bool canRequest,  bool running,  bool stopped,  bool? connectionRequested,  bool? audioRequested,  bool? mediaPlaybackReady,  bool? notificationPermission,  bool? requested,  String? platform,  String title,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BackgroundStatus() when $default != null:
return $default(_that.supported,_that.canRequest,_that.running,_that.stopped,_that.connectionRequested,_that.audioRequested,_that.mediaPlaybackReady,_that.notificationPermission,_that.requested,_that.platform,_that.title,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool supported,  bool canRequest,  bool running,  bool stopped,  bool? connectionRequested,  bool? audioRequested,  bool? mediaPlaybackReady,  bool? notificationPermission,  bool? requested,  String? platform,  String title,  String reason)  $default,) {final _that = this;
switch (_that) {
case _BackgroundStatus():
return $default(_that.supported,_that.canRequest,_that.running,_that.stopped,_that.connectionRequested,_that.audioRequested,_that.mediaPlaybackReady,_that.notificationPermission,_that.requested,_that.platform,_that.title,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool supported,  bool canRequest,  bool running,  bool stopped,  bool? connectionRequested,  bool? audioRequested,  bool? mediaPlaybackReady,  bool? notificationPermission,  bool? requested,  String? platform,  String title,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _BackgroundStatus() when $default != null:
return $default(_that.supported,_that.canRequest,_that.running,_that.stopped,_that.connectionRequested,_that.audioRequested,_that.mediaPlaybackReady,_that.notificationPermission,_that.requested,_that.platform,_that.title,_that.reason);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(checked: true)
class _BackgroundStatus implements BackgroundStatus {
  const _BackgroundStatus({this.supported = false, this.canRequest = false, this.running = false, this.stopped = false, this.connectionRequested, this.audioRequested, this.mediaPlaybackReady, this.notificationPermission, this.requested, this.platform, this.title = '系统后台条件', this.reason = '尚未确认本机后台能力。请保持 App 在前台，并核对活动的实际状态。'});
  factory _BackgroundStatus.fromJson(Map<String, dynamic> json) => _$BackgroundStatusFromJson(json);

@override@JsonKey() final  bool supported;
@override@JsonKey() final  bool canRequest;
@override@JsonKey() final  bool running;
@override@JsonKey() final  bool stopped;
@override final  bool? connectionRequested;
@override final  bool? audioRequested;
@override final  bool? mediaPlaybackReady;
@override final  bool? notificationPermission;
@override final  bool? requested;
@override final  String? platform;
@override@JsonKey() final  String title;
@override@JsonKey() final  String reason;

/// Create a copy of BackgroundStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BackgroundStatusCopyWith<_BackgroundStatus> get copyWith => __$BackgroundStatusCopyWithImpl<_BackgroundStatus>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BackgroundStatusToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BackgroundStatus&&(identical(other.supported, supported) || other.supported == supported)&&(identical(other.canRequest, canRequest) || other.canRequest == canRequest)&&(identical(other.running, running) || other.running == running)&&(identical(other.stopped, stopped) || other.stopped == stopped)&&(identical(other.connectionRequested, connectionRequested) || other.connectionRequested == connectionRequested)&&(identical(other.audioRequested, audioRequested) || other.audioRequested == audioRequested)&&(identical(other.mediaPlaybackReady, mediaPlaybackReady) || other.mediaPlaybackReady == mediaPlaybackReady)&&(identical(other.notificationPermission, notificationPermission) || other.notificationPermission == notificationPermission)&&(identical(other.requested, requested) || other.requested == requested)&&(identical(other.platform, platform) || other.platform == platform)&&(identical(other.title, title) || other.title == title)&&(identical(other.reason, reason) || other.reason == reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,supported,canRequest,running,stopped,connectionRequested,audioRequested,mediaPlaybackReady,notificationPermission,requested,platform,title,reason);
}

@override
String toString() {
    return 'BackgroundStatus(supported: $supported, canRequest: $canRequest, running: $running, stopped: $stopped, connectionRequested: $connectionRequested, audioRequested: $audioRequested, mediaPlaybackReady: $mediaPlaybackReady, notificationPermission: $notificationPermission, requested: $requested, platform: $platform, title: $title, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$BackgroundStatusCopyWith<$Res> implements $BackgroundStatusCopyWith<$Res> {
  factory _$BackgroundStatusCopyWith(_BackgroundStatus value, $Res Function(_BackgroundStatus) _then) = __$BackgroundStatusCopyWithImpl;
@override @useResult
$Res call({
 bool supported, bool canRequest, bool running, bool stopped, bool? connectionRequested, bool? audioRequested, bool? mediaPlaybackReady, bool? notificationPermission, bool? requested, String? platform, String title, String reason
});




}
/// @nodoc
class __$BackgroundStatusCopyWithImpl<$Res>
    implements _$BackgroundStatusCopyWith<$Res> {
  __$BackgroundStatusCopyWithImpl(this._self, this._then);

  final _BackgroundStatus _self;
  final $Res Function(_BackgroundStatus) _then;

/// Create a copy of BackgroundStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? supported = null,Object? canRequest = null,Object? running = null,Object? stopped = null,Object? connectionRequested = freezed,Object? audioRequested = freezed,Object? mediaPlaybackReady = freezed,Object? notificationPermission = freezed,Object? requested = freezed,Object? platform = freezed,Object? title = null,Object? reason = null,}) {
  return _then(_BackgroundStatus(
supported: null == supported ? _self.supported : supported // ignore: cast_nullable_to_non_nullable
as bool,canRequest: null == canRequest ? _self.canRequest : canRequest // ignore: cast_nullable_to_non_nullable
as bool,running: null == running ? _self.running : running // ignore: cast_nullable_to_non_nullable
as bool,stopped: null == stopped ? _self.stopped : stopped // ignore: cast_nullable_to_non_nullable
as bool,connectionRequested: freezed == connectionRequested ? _self.connectionRequested : connectionRequested // ignore: cast_nullable_to_non_nullable
as bool?,audioRequested: freezed == audioRequested ? _self.audioRequested : audioRequested // ignore: cast_nullable_to_non_nullable
as bool?,mediaPlaybackReady: freezed == mediaPlaybackReady ? _self.mediaPlaybackReady : mediaPlaybackReady // ignore: cast_nullable_to_non_nullable
as bool?,notificationPermission: freezed == notificationPermission ? _self.notificationPermission : notificationPermission // ignore: cast_nullable_to_non_nullable
as bool?,requested: freezed == requested ? _self.requested : requested // ignore: cast_nullable_to_non_nullable
as bool?,platform: freezed == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
