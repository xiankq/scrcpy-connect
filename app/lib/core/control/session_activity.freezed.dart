// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_activity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionActivity {

 String get sessionId; String get deviceId; String get name; String get status; bool get needsLaunchReview; bool get recordOnly; String? get linkedSessionId; String? get reason;
/// Create a copy of SessionActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionActivityCopyWith<SessionActivity> get copyWith => _$SessionActivityCopyWithImpl<SessionActivity>(this as SessionActivity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionActivity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionActivity&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.needsLaunchReview, _this.needsLaunchReview) || other.needsLaunchReview == _this.needsLaunchReview)&&(identical(other.recordOnly, _this.recordOnly) || other.recordOnly == _this.recordOnly)&&(identical(other.linkedSessionId, _this.linkedSessionId) || other.linkedSessionId == _this.linkedSessionId)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}


@override
int get hashCode {
  final _this = this as SessionActivity;
  return Object.hash(runtimeType,_this.sessionId,_this.deviceId,_this.name,_this.status,_this.needsLaunchReview,_this.recordOnly,_this.linkedSessionId,_this.reason);
}

@override
String toString() {
  final _this = this as SessionActivity;
  return 'SessionActivity(sessionId: ${_this.sessionId}, deviceId: ${_this.deviceId}, name: ${_this.name}, status: ${_this.status}, needsLaunchReview: ${_this.needsLaunchReview}, recordOnly: ${_this.recordOnly}, linkedSessionId: ${_this.linkedSessionId}, reason: ${_this.reason})';
}


}

/// @nodoc
abstract mixin class $SessionActivityCopyWith<$Res>  {
  factory $SessionActivityCopyWith(SessionActivity value, $Res Function(SessionActivity) _then) = _$SessionActivityCopyWithImpl;
@useResult
$Res call({
 String sessionId, String deviceId, String name, String status, bool needsLaunchReview, bool recordOnly, String? linkedSessionId, String? reason
});




}
/// @nodoc
class _$SessionActivityCopyWithImpl<$Res>
    implements $SessionActivityCopyWith<$Res> {
  _$SessionActivityCopyWithImpl(this._self, this._then);

  final SessionActivity _self;
  final $Res Function(SessionActivity) _then;

/// Create a copy of SessionActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? deviceId = null,Object? name = null,Object? status = null,Object? needsLaunchReview = null,Object? recordOnly = null,Object? linkedSessionId = freezed,Object? reason = freezed,}) {
  return _then(SessionActivity(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,needsLaunchReview: null == needsLaunchReview ? _self.needsLaunchReview : needsLaunchReview // ignore: cast_nullable_to_non_nullable
as bool,recordOnly: null == recordOnly ? _self.recordOnly : recordOnly // ignore: cast_nullable_to_non_nullable
as bool,linkedSessionId: freezed == linkedSessionId ? _self.linkedSessionId : linkedSessionId // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionActivity].
extension SessionActivityPatterns on SessionActivity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionActivity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionActivity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionActivity value)  $default,){
final _that = this;
switch (_that) {
case _SessionActivity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionActivity value)?  $default,){
final _that = this;
switch (_that) {
case _SessionActivity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sessionId,  String deviceId,  String name,  String status,  bool needsLaunchReview,  bool recordOnly,  String? linkedSessionId,  String? reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionActivity() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.name,_that.status,_that.needsLaunchReview,_that.recordOnly,_that.linkedSessionId,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sessionId,  String deviceId,  String name,  String status,  bool needsLaunchReview,  bool recordOnly,  String? linkedSessionId,  String? reason)  $default,) {final _that = this;
switch (_that) {
case _SessionActivity():
return $default(_that.sessionId,_that.deviceId,_that.name,_that.status,_that.needsLaunchReview,_that.recordOnly,_that.linkedSessionId,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sessionId,  String deviceId,  String name,  String status,  bool needsLaunchReview,  bool recordOnly,  String? linkedSessionId,  String? reason)?  $default,) {final _that = this;
switch (_that) {
case _SessionActivity() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.name,_that.status,_that.needsLaunchReview,_that.recordOnly,_that.linkedSessionId,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _SessionActivity implements SessionActivity {
  const _SessionActivity({required this.sessionId, required this.deviceId, required this.name, required this.status, this.needsLaunchReview = false, this.recordOnly = false, this.linkedSessionId, this.reason});
  

@override final  String sessionId;
@override final  String deviceId;
@override final  String name;
@override final  String status;
@override@JsonKey() final  bool needsLaunchReview;
@override@JsonKey() final  bool recordOnly;
@override final  String? linkedSessionId;
@override final  String? reason;

/// Create a copy of SessionActivity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionActivityCopyWith<_SessionActivity> get copyWith => __$SessionActivityCopyWithImpl<_SessionActivity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionActivity&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.name, name) || other.name == name)&&(identical(other.status, status) || other.status == status)&&(identical(other.needsLaunchReview, needsLaunchReview) || other.needsLaunchReview == needsLaunchReview)&&(identical(other.recordOnly, recordOnly) || other.recordOnly == recordOnly)&&(identical(other.linkedSessionId, linkedSessionId) || other.linkedSessionId == linkedSessionId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId,deviceId,name,status,needsLaunchReview,recordOnly,linkedSessionId,reason);
}

@override
String toString() {
    return 'SessionActivity(sessionId: $sessionId, deviceId: $deviceId, name: $name, status: $status, needsLaunchReview: $needsLaunchReview, recordOnly: $recordOnly, linkedSessionId: $linkedSessionId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$SessionActivityCopyWith<$Res> implements $SessionActivityCopyWith<$Res> {
  factory _$SessionActivityCopyWith(_SessionActivity value, $Res Function(_SessionActivity) _then) = __$SessionActivityCopyWithImpl;
@override @useResult
$Res call({
 String sessionId, String deviceId, String name, String status, bool needsLaunchReview, bool recordOnly, String? linkedSessionId, String? reason
});




}
/// @nodoc
class __$SessionActivityCopyWithImpl<$Res>
    implements _$SessionActivityCopyWith<$Res> {
  __$SessionActivityCopyWithImpl(this._self, this._then);

  final _SessionActivity _self;
  final $Res Function(_SessionActivity) _then;

/// Create a copy of SessionActivity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? deviceId = null,Object? name = null,Object? status = null,Object? needsLaunchReview = null,Object? recordOnly = null,Object? linkedSessionId = freezed,Object? reason = freezed,}) {
  return _then(_SessionActivity(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,needsLaunchReview: null == needsLaunchReview ? _self.needsLaunchReview : needsLaunchReview // ignore: cast_nullable_to_non_nullable
as bool,recordOnly: null == recordOnly ? _self.recordOnly : recordOnly // ignore: cast_nullable_to_non_nullable
as bool,linkedSessionId: freezed == linkedSessionId ? _self.linkedSessionId : linkedSessionId // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$VideoStopReceipt {

 String get sessionId; String? get deviceId; bool get recordOnly; KeepAwakeSnapshot? get wakeCleanup;
/// Create a copy of VideoStopReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoStopReceiptCopyWith<VideoStopReceipt> get copyWith => _$VideoStopReceiptCopyWithImpl<VideoStopReceipt>(this as VideoStopReceipt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoStopReceipt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoStopReceipt&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.recordOnly, _this.recordOnly) || other.recordOnly == _this.recordOnly)&&(identical(other.wakeCleanup, _this.wakeCleanup) || other.wakeCleanup == _this.wakeCleanup));
}


@override
int get hashCode {
  final _this = this as VideoStopReceipt;
  return Object.hash(runtimeType,_this.sessionId,_this.deviceId,_this.recordOnly,_this.wakeCleanup);
}

@override
String toString() {
  final _this = this as VideoStopReceipt;
  return 'VideoStopReceipt(sessionId: ${_this.sessionId}, deviceId: ${_this.deviceId}, recordOnly: ${_this.recordOnly}, wakeCleanup: ${_this.wakeCleanup})';
}


}

/// @nodoc
abstract mixin class $VideoStopReceiptCopyWith<$Res>  {
  factory $VideoStopReceiptCopyWith(VideoStopReceipt value, $Res Function(VideoStopReceipt) _then) = _$VideoStopReceiptCopyWithImpl;
@useResult
$Res call({
 String sessionId, String? deviceId, bool recordOnly, KeepAwakeSnapshot? wakeCleanup
});


$KeepAwakeSnapshotCopyWith<$Res>? get wakeCleanup;

}
/// @nodoc
class _$VideoStopReceiptCopyWithImpl<$Res>
    implements $VideoStopReceiptCopyWith<$Res> {
  _$VideoStopReceiptCopyWithImpl(this._self, this._then);

  final VideoStopReceipt _self;
  final $Res Function(VideoStopReceipt) _then;

/// Create a copy of VideoStopReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? deviceId = freezed,Object? recordOnly = null,Object? wakeCleanup = freezed,}) {
  return _then(VideoStopReceipt(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,recordOnly: null == recordOnly ? _self.recordOnly : recordOnly // ignore: cast_nullable_to_non_nullable
as bool,wakeCleanup: freezed == wakeCleanup ? _self.wakeCleanup : wakeCleanup // ignore: cast_nullable_to_non_nullable
as KeepAwakeSnapshot?,
  ));
}
/// Create a copy of VideoStopReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$KeepAwakeSnapshotCopyWith<$Res>? get wakeCleanup {
    if (_self.wakeCleanup == null) {
    return null;
  }

  return $KeepAwakeSnapshotCopyWith<$Res>(_self.wakeCleanup!, (value) {
    return _then(_self.copyWith(wakeCleanup: value));
  });
}
}


/// Adds pattern-matching-related methods to [VideoStopReceipt].
extension VideoStopReceiptPatterns on VideoStopReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoStopReceipt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoStopReceipt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoStopReceipt value)  $default,){
final _that = this;
switch (_that) {
case _VideoStopReceipt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoStopReceipt value)?  $default,){
final _that = this;
switch (_that) {
case _VideoStopReceipt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sessionId,  String? deviceId,  bool recordOnly,  KeepAwakeSnapshot? wakeCleanup)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoStopReceipt() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.recordOnly,_that.wakeCleanup);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sessionId,  String? deviceId,  bool recordOnly,  KeepAwakeSnapshot? wakeCleanup)  $default,) {final _that = this;
switch (_that) {
case _VideoStopReceipt():
return $default(_that.sessionId,_that.deviceId,_that.recordOnly,_that.wakeCleanup);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sessionId,  String? deviceId,  bool recordOnly,  KeepAwakeSnapshot? wakeCleanup)?  $default,) {final _that = this;
switch (_that) {
case _VideoStopReceipt() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.recordOnly,_that.wakeCleanup);case _:
  return null;

}
}

}

/// @nodoc


class _VideoStopReceipt implements VideoStopReceipt {
  const _VideoStopReceipt({required this.sessionId, this.deviceId, this.recordOnly = false, this.wakeCleanup});
  

@override final  String sessionId;
@override final  String? deviceId;
@override@JsonKey() final  bool recordOnly;
@override final  KeepAwakeSnapshot? wakeCleanup;

/// Create a copy of VideoStopReceipt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoStopReceiptCopyWith<_VideoStopReceipt> get copyWith => __$VideoStopReceiptCopyWithImpl<_VideoStopReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoStopReceipt&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.recordOnly, recordOnly) || other.recordOnly == recordOnly)&&(identical(other.wakeCleanup, wakeCleanup) || other.wakeCleanup == wakeCleanup));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId,deviceId,recordOnly,wakeCleanup);
}

@override
String toString() {
    return 'VideoStopReceipt(sessionId: $sessionId, deviceId: $deviceId, recordOnly: $recordOnly, wakeCleanup: $wakeCleanup)';
}


}

/// @nodoc
abstract mixin class _$VideoStopReceiptCopyWith<$Res> implements $VideoStopReceiptCopyWith<$Res> {
  factory _$VideoStopReceiptCopyWith(_VideoStopReceipt value, $Res Function(_VideoStopReceipt) _then) = __$VideoStopReceiptCopyWithImpl;
@override @useResult
$Res call({
 String sessionId, String? deviceId, bool recordOnly, KeepAwakeSnapshot? wakeCleanup
});


@override $KeepAwakeSnapshotCopyWith<$Res>? get wakeCleanup;

}
/// @nodoc
class __$VideoStopReceiptCopyWithImpl<$Res>
    implements _$VideoStopReceiptCopyWith<$Res> {
  __$VideoStopReceiptCopyWithImpl(this._self, this._then);

  final _VideoStopReceipt _self;
  final $Res Function(_VideoStopReceipt) _then;

/// Create a copy of VideoStopReceipt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? deviceId = freezed,Object? recordOnly = null,Object? wakeCleanup = freezed,}) {
  return _then(_VideoStopReceipt(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,recordOnly: null == recordOnly ? _self.recordOnly : recordOnly // ignore: cast_nullable_to_non_nullable
as bool,wakeCleanup: freezed == wakeCleanup ? _self.wakeCleanup : wakeCleanup // ignore: cast_nullable_to_non_nullable
as KeepAwakeSnapshot?,
  ));
}

/// Create a copy of VideoStopReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$KeepAwakeSnapshotCopyWith<$Res>? get wakeCleanup {
    if (_self.wakeCleanup == null) {
    return null;
  }

  return $KeepAwakeSnapshotCopyWith<$Res>(_self.wakeCleanup!, (value) {
    return _then(_self.copyWith(wakeCleanup: value));
  });
}
}

// dart format on
