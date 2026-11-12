// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'activities.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ActivityTarget {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityTarget);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ActivityTarget()';
}


}

/// @nodoc
class $ActivityTargetCopyWith<$Res>  {
$ActivityTargetCopyWith(ActivityTarget _, $Res Function(ActivityTarget) __);
}


/// Adds pattern-matching-related methods to [ActivityTarget].
extension ActivityTargetPatterns on ActivityTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ConnectionActivity value)?  connection,TResult Function( SessionActivityTarget value)?  session,TResult Function( ObservationActivity value)?  observation,TResult Function( TransferActivity value)?  transfer,TResult Function( AudioActivity value)?  audio,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ConnectionActivity() when connection != null:
return connection(_that);case SessionActivityTarget() when session != null:
return session(_that);case ObservationActivity() when observation != null:
return observation(_that);case TransferActivity() when transfer != null:
return transfer(_that);case AudioActivity() when audio != null:
return audio(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ConnectionActivity value)  connection,required TResult Function( SessionActivityTarget value)  session,required TResult Function( ObservationActivity value)  observation,required TResult Function( TransferActivity value)  transfer,required TResult Function( AudioActivity value)  audio,}){
final _that = this;
switch (_that) {
case ConnectionActivity():
return connection(_that);case SessionActivityTarget():
return session(_that);case ObservationActivity():
return observation(_that);case TransferActivity():
return transfer(_that);case AudioActivity():
return audio(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ConnectionActivity value)?  connection,TResult? Function( SessionActivityTarget value)?  session,TResult? Function( ObservationActivity value)?  observation,TResult? Function( TransferActivity value)?  transfer,TResult? Function( AudioActivity value)?  audio,}){
final _that = this;
switch (_that) {
case ConnectionActivity() when connection != null:
return connection(_that);case SessionActivityTarget() when session != null:
return session(_that);case ObservationActivity() when observation != null:
return observation(_that);case TransferActivity() when transfer != null:
return transfer(_that);case AudioActivity() when audio != null:
return audio(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String deviceId)?  connection,TResult Function( String sessionId)?  session,TResult Function( String deviceId)?  observation,TResult Function( String transferId)?  transfer,TResult Function( DeviceAudioTarget source)?  audio,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ConnectionActivity() when connection != null:
return connection(_that.deviceId);case SessionActivityTarget() when session != null:
return session(_that.sessionId);case ObservationActivity() when observation != null:
return observation(_that.deviceId);case TransferActivity() when transfer != null:
return transfer(_that.transferId);case AudioActivity() when audio != null:
return audio(_that.source);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String deviceId)  connection,required TResult Function( String sessionId)  session,required TResult Function( String deviceId)  observation,required TResult Function( String transferId)  transfer,required TResult Function( DeviceAudioTarget source)  audio,}) {final _that = this;
switch (_that) {
case ConnectionActivity():
return connection(_that.deviceId);case SessionActivityTarget():
return session(_that.sessionId);case ObservationActivity():
return observation(_that.deviceId);case TransferActivity():
return transfer(_that.transferId);case AudioActivity():
return audio(_that.source);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String deviceId)?  connection,TResult? Function( String sessionId)?  session,TResult? Function( String deviceId)?  observation,TResult? Function( String transferId)?  transfer,TResult? Function( DeviceAudioTarget source)?  audio,}) {final _that = this;
switch (_that) {
case ConnectionActivity() when connection != null:
return connection(_that.deviceId);case SessionActivityTarget() when session != null:
return session(_that.sessionId);case ObservationActivity() when observation != null:
return observation(_that.deviceId);case TransferActivity() when transfer != null:
return transfer(_that.transferId);case AudioActivity() when audio != null:
return audio(_that.source);case _:
  return null;

}
}

}

/// @nodoc


class ConnectionActivity extends ActivityTarget {
  const ConnectionActivity(this.deviceId): super._();
  

 final  String deviceId;

/// Create a copy of ActivityTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionActivityCopyWith<ConnectionActivity> get copyWith => _$ConnectionActivityCopyWithImpl<ConnectionActivity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionActivity&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId);
}

@override
String toString() {
    return 'ActivityTarget.connection(deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $ConnectionActivityCopyWith<$Res> implements $ActivityTargetCopyWith<$Res> {
  factory $ConnectionActivityCopyWith(ConnectionActivity value, $Res Function(ConnectionActivity) _then) = _$ConnectionActivityCopyWithImpl;
@useResult
$Res call({
 String deviceId
});




}
/// @nodoc
class _$ConnectionActivityCopyWithImpl<$Res>
    implements $ConnectionActivityCopyWith<$Res> {
  _$ConnectionActivityCopyWithImpl(this._self, this._then);

  final ConnectionActivity _self;
  final $Res Function(ConnectionActivity) _then;

/// Create a copy of ActivityTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,}) {
  return _then(ConnectionActivity(
null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SessionActivityTarget extends ActivityTarget {
  const SessionActivityTarget(this.sessionId): super._();
  

 final  String sessionId;

/// Create a copy of ActivityTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionActivityTargetCopyWith<SessionActivityTarget> get copyWith => _$SessionActivityTargetCopyWithImpl<SessionActivityTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionActivityTarget&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId);
}

@override
String toString() {
    return 'ActivityTarget.session(sessionId: $sessionId)';
}


}

/// @nodoc
abstract mixin class $SessionActivityTargetCopyWith<$Res> implements $ActivityTargetCopyWith<$Res> {
  factory $SessionActivityTargetCopyWith(SessionActivityTarget value, $Res Function(SessionActivityTarget) _then) = _$SessionActivityTargetCopyWithImpl;
@useResult
$Res call({
 String sessionId
});




}
/// @nodoc
class _$SessionActivityTargetCopyWithImpl<$Res>
    implements $SessionActivityTargetCopyWith<$Res> {
  _$SessionActivityTargetCopyWithImpl(this._self, this._then);

  final SessionActivityTarget _self;
  final $Res Function(SessionActivityTarget) _then;

/// Create a copy of ActivityTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,}) {
  return _then(SessionActivityTarget(
null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ObservationActivity extends ActivityTarget {
  const ObservationActivity(this.deviceId): super._();
  

 final  String deviceId;

/// Create a copy of ActivityTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ObservationActivityCopyWith<ObservationActivity> get copyWith => _$ObservationActivityCopyWithImpl<ObservationActivity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ObservationActivity&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId);
}

@override
String toString() {
    return 'ActivityTarget.observation(deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $ObservationActivityCopyWith<$Res> implements $ActivityTargetCopyWith<$Res> {
  factory $ObservationActivityCopyWith(ObservationActivity value, $Res Function(ObservationActivity) _then) = _$ObservationActivityCopyWithImpl;
@useResult
$Res call({
 String deviceId
});




}
/// @nodoc
class _$ObservationActivityCopyWithImpl<$Res>
    implements $ObservationActivityCopyWith<$Res> {
  _$ObservationActivityCopyWithImpl(this._self, this._then);

  final ObservationActivity _self;
  final $Res Function(ObservationActivity) _then;

/// Create a copy of ActivityTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,}) {
  return _then(ObservationActivity(
null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TransferActivity extends ActivityTarget {
  const TransferActivity(this.transferId): super._();
  

 final  String transferId;

/// Create a copy of ActivityTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransferActivityCopyWith<TransferActivity> get copyWith => _$TransferActivityCopyWithImpl<TransferActivity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TransferActivity&&(identical(other.transferId, transferId) || other.transferId == transferId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,transferId);
}

@override
String toString() {
    return 'ActivityTarget.transfer(transferId: $transferId)';
}


}

/// @nodoc
abstract mixin class $TransferActivityCopyWith<$Res> implements $ActivityTargetCopyWith<$Res> {
  factory $TransferActivityCopyWith(TransferActivity value, $Res Function(TransferActivity) _then) = _$TransferActivityCopyWithImpl;
@useResult
$Res call({
 String transferId
});




}
/// @nodoc
class _$TransferActivityCopyWithImpl<$Res>
    implements $TransferActivityCopyWith<$Res> {
  _$TransferActivityCopyWithImpl(this._self, this._then);

  final TransferActivity _self;
  final $Res Function(TransferActivity) _then;

/// Create a copy of ActivityTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? transferId = null,}) {
  return _then(TransferActivity(
null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AudioActivity extends ActivityTarget {
  const AudioActivity(this.source): super._();
  

 final  DeviceAudioTarget source;

/// Create a copy of ActivityTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AudioActivityCopyWith<AudioActivity> get copyWith => _$AudioActivityCopyWithImpl<AudioActivity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AudioActivity&&(identical(other.source, source) || other.source == source));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source);
}

@override
String toString() {
    return 'ActivityTarget.audio(source: $source)';
}


}

/// @nodoc
abstract mixin class $AudioActivityCopyWith<$Res> implements $ActivityTargetCopyWith<$Res> {
  factory $AudioActivityCopyWith(AudioActivity value, $Res Function(AudioActivity) _then) = _$AudioActivityCopyWithImpl;
@useResult
$Res call({
 DeviceAudioTarget source
});


$DeviceAudioTargetCopyWith<$Res> get source;

}
/// @nodoc
class _$AudioActivityCopyWithImpl<$Res>
    implements $AudioActivityCopyWith<$Res> {
  _$AudioActivityCopyWithImpl(this._self, this._then);

  final AudioActivity _self;
  final $Res Function(AudioActivity) _then;

/// Create a copy of ActivityTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? source = null,}) {
  return _then(AudioActivity(
null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as DeviceAudioTarget,
  ));
}

/// Create a copy of ActivityTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceAudioTargetCopyWith<$Res> get source {
  
  return $DeviceAudioTargetCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}

/// @nodoc
mixin _$ActivitySnapshot {

 ActivityTarget get target; String get deviceId; String get deviceName; String get name; String get status; String get stopImpact;
/// Create a copy of ActivitySnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivitySnapshotCopyWith<ActivitySnapshot> get copyWith => _$ActivitySnapshotCopyWithImpl<ActivitySnapshot>(this as ActivitySnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActivitySnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivitySnapshot&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.deviceName, _this.deviceName) || other.deviceName == _this.deviceName)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.stopImpact, _this.stopImpact) || other.stopImpact == _this.stopImpact));
}


@override
int get hashCode {
  final _this = this as ActivitySnapshot;
  return Object.hash(runtimeType,_this.target,_this.deviceId,_this.deviceName,_this.name,_this.status,_this.stopImpact);
}

@override
String toString() {
  final _this = this as ActivitySnapshot;
  return 'ActivitySnapshot(target: ${_this.target}, deviceId: ${_this.deviceId}, deviceName: ${_this.deviceName}, name: ${_this.name}, status: ${_this.status}, stopImpact: ${_this.stopImpact})';
}


}

/// @nodoc
abstract mixin class $ActivitySnapshotCopyWith<$Res>  {
  factory $ActivitySnapshotCopyWith(ActivitySnapshot value, $Res Function(ActivitySnapshot) _then) = _$ActivitySnapshotCopyWithImpl;
@useResult
$Res call({
 ActivityTarget target, String deviceId, String deviceName, String name, String status, String stopImpact
});


$ActivityTargetCopyWith<$Res> get target;

}
/// @nodoc
class _$ActivitySnapshotCopyWithImpl<$Res>
    implements $ActivitySnapshotCopyWith<$Res> {
  _$ActivitySnapshotCopyWithImpl(this._self, this._then);

  final ActivitySnapshot _self;
  final $Res Function(ActivitySnapshot) _then;

/// Create a copy of ActivitySnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? target = null,Object? deviceId = null,Object? deviceName = null,Object? name = null,Object? status = null,Object? stopImpact = null,}) {
  return _then(ActivitySnapshot(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as ActivityTarget,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,deviceName: null == deviceName ? _self.deviceName : deviceName // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,stopImpact: null == stopImpact ? _self.stopImpact : stopImpact // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of ActivitySnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityTargetCopyWith<$Res> get target {
  
  return $ActivityTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}


/// Adds pattern-matching-related methods to [ActivitySnapshot].
extension ActivitySnapshotPatterns on ActivitySnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActivitySnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActivitySnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActivitySnapshot value)  $default,){
final _that = this;
switch (_that) {
case _ActivitySnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActivitySnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _ActivitySnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ActivityTarget target,  String deviceId,  String deviceName,  String name,  String status,  String stopImpact)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivitySnapshot() when $default != null:
return $default(_that.target,_that.deviceId,_that.deviceName,_that.name,_that.status,_that.stopImpact);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ActivityTarget target,  String deviceId,  String deviceName,  String name,  String status,  String stopImpact)  $default,) {final _that = this;
switch (_that) {
case _ActivitySnapshot():
return $default(_that.target,_that.deviceId,_that.deviceName,_that.name,_that.status,_that.stopImpact);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ActivityTarget target,  String deviceId,  String deviceName,  String name,  String status,  String stopImpact)?  $default,) {final _that = this;
switch (_that) {
case _ActivitySnapshot() when $default != null:
return $default(_that.target,_that.deviceId,_that.deviceName,_that.name,_that.status,_that.stopImpact);case _:
  return null;

}
}

}

/// @nodoc


class _ActivitySnapshot implements ActivitySnapshot {
  const _ActivitySnapshot({required this.target, required this.deviceId, required this.deviceName, required this.name, required this.status, required this.stopImpact});
  

@override final  ActivityTarget target;
@override final  String deviceId;
@override final  String deviceName;
@override final  String name;
@override final  String status;
@override final  String stopImpact;

/// Create a copy of ActivitySnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivitySnapshotCopyWith<_ActivitySnapshot> get copyWith => __$ActivitySnapshotCopyWithImpl<_ActivitySnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivitySnapshot&&(identical(other.target, target) || other.target == target)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.deviceName, deviceName) || other.deviceName == deviceName)&&(identical(other.name, name) || other.name == name)&&(identical(other.status, status) || other.status == status)&&(identical(other.stopImpact, stopImpact) || other.stopImpact == stopImpact));
}


@override
int get hashCode {
    return Object.hash(runtimeType,target,deviceId,deviceName,name,status,stopImpact);
}

@override
String toString() {
    return 'ActivitySnapshot(target: $target, deviceId: $deviceId, deviceName: $deviceName, name: $name, status: $status, stopImpact: $stopImpact)';
}


}

/// @nodoc
abstract mixin class _$ActivitySnapshotCopyWith<$Res> implements $ActivitySnapshotCopyWith<$Res> {
  factory _$ActivitySnapshotCopyWith(_ActivitySnapshot value, $Res Function(_ActivitySnapshot) _then) = __$ActivitySnapshotCopyWithImpl;
@override @useResult
$Res call({
 ActivityTarget target, String deviceId, String deviceName, String name, String status, String stopImpact
});


@override $ActivityTargetCopyWith<$Res> get target;

}
/// @nodoc
class __$ActivitySnapshotCopyWithImpl<$Res>
    implements _$ActivitySnapshotCopyWith<$Res> {
  __$ActivitySnapshotCopyWithImpl(this._self, this._then);

  final _ActivitySnapshot _self;
  final $Res Function(_ActivitySnapshot) _then;

/// Create a copy of ActivitySnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? target = null,Object? deviceId = null,Object? deviceName = null,Object? name = null,Object? status = null,Object? stopImpact = null,}) {
  return _then(_ActivitySnapshot(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as ActivityTarget,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,deviceName: null == deviceName ? _self.deviceName : deviceName // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,stopImpact: null == stopImpact ? _self.stopImpact : stopImpact // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of ActivitySnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityTargetCopyWith<$Res> get target {
  
  return $ActivityTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}

/// @nodoc
mixin _$ActivityCollection {

 List<ActivitySnapshot> get activities; List<SessionActivity> get pendingApplications;
/// Create a copy of ActivityCollection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityCollectionCopyWith<ActivityCollection> get copyWith => _$ActivityCollectionCopyWithImpl<ActivityCollection>(this as ActivityCollection, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActivityCollection;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityCollection&&const DeepCollectionEquality().equals(other.activities, _this.activities)&&const DeepCollectionEquality().equals(other.pendingApplications, _this.pendingApplications));
}


@override
int get hashCode {
  final _this = this as ActivityCollection;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.activities),const DeepCollectionEquality().hash(_this.pendingApplications));
}

@override
String toString() {
  final _this = this as ActivityCollection;
  return 'ActivityCollection(activities: ${_this.activities}, pendingApplications: ${_this.pendingApplications})';
}


}

/// @nodoc
abstract mixin class $ActivityCollectionCopyWith<$Res>  {
  factory $ActivityCollectionCopyWith(ActivityCollection value, $Res Function(ActivityCollection) _then) = _$ActivityCollectionCopyWithImpl;
@useResult
$Res call({
 List<ActivitySnapshot> activities, List<SessionActivity> pendingApplications
});




}
/// @nodoc
class _$ActivityCollectionCopyWithImpl<$Res>
    implements $ActivityCollectionCopyWith<$Res> {
  _$ActivityCollectionCopyWithImpl(this._self, this._then);

  final ActivityCollection _self;
  final $Res Function(ActivityCollection) _then;

/// Create a copy of ActivityCollection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? activities = null,Object? pendingApplications = null,}) {
  return _then(ActivityCollection(
activities: null == activities ? _self.activities : activities // ignore: cast_nullable_to_non_nullable
as List<ActivitySnapshot>,pendingApplications: null == pendingApplications ? _self.pendingApplications : pendingApplications // ignore: cast_nullable_to_non_nullable
as List<SessionActivity>,
  ));
}

}


/// Adds pattern-matching-related methods to [ActivityCollection].
extension ActivityCollectionPatterns on ActivityCollection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActivityCollection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActivityCollection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActivityCollection value)  $default,){
final _that = this;
switch (_that) {
case _ActivityCollection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActivityCollection value)?  $default,){
final _that = this;
switch (_that) {
case _ActivityCollection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<ActivitySnapshot> activities,  List<SessionActivity> pendingApplications)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivityCollection() when $default != null:
return $default(_that.activities,_that.pendingApplications);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<ActivitySnapshot> activities,  List<SessionActivity> pendingApplications)  $default,) {final _that = this;
switch (_that) {
case _ActivityCollection():
return $default(_that.activities,_that.pendingApplications);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<ActivitySnapshot> activities,  List<SessionActivity> pendingApplications)?  $default,) {final _that = this;
switch (_that) {
case _ActivityCollection() when $default != null:
return $default(_that.activities,_that.pendingApplications);case _:
  return null;

}
}

}

/// @nodoc


class _ActivityCollection implements ActivityCollection {
  const _ActivityCollection({required  List<ActivitySnapshot> activities, required  List<SessionActivity> pendingApplications}): _activities = activities,_pendingApplications = pendingApplications;
  

 final  List<ActivitySnapshot> _activities;
@override List<ActivitySnapshot> get activities {
  if (_activities is EqualUnmodifiableListView) return _activities;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activities);
}

 final  List<SessionActivity> _pendingApplications;
@override List<SessionActivity> get pendingApplications {
  if (_pendingApplications is EqualUnmodifiableListView) return _pendingApplications;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_pendingApplications);
}


/// Create a copy of ActivityCollection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityCollectionCopyWith<_ActivityCollection> get copyWith => __$ActivityCollectionCopyWithImpl<_ActivityCollection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityCollection&&const DeepCollectionEquality().equals(other.activities, _activities)&&const DeepCollectionEquality().equals(other.pendingApplications, _pendingApplications));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_activities),const DeepCollectionEquality().hash(_pendingApplications));
}

@override
String toString() {
    return 'ActivityCollection(activities: $activities, pendingApplications: $pendingApplications)';
}


}

/// @nodoc
abstract mixin class _$ActivityCollectionCopyWith<$Res> implements $ActivityCollectionCopyWith<$Res> {
  factory _$ActivityCollectionCopyWith(_ActivityCollection value, $Res Function(_ActivityCollection) _then) = __$ActivityCollectionCopyWithImpl;
@override @useResult
$Res call({
 List<ActivitySnapshot> activities, List<SessionActivity> pendingApplications
});




}
/// @nodoc
class __$ActivityCollectionCopyWithImpl<$Res>
    implements _$ActivityCollectionCopyWith<$Res> {
  __$ActivityCollectionCopyWithImpl(this._self, this._then);

  final _ActivityCollection _self;
  final $Res Function(_ActivityCollection) _then;

/// Create a copy of ActivityCollection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? activities = null,Object? pendingApplications = null,}) {
  return _then(_ActivityCollection(
activities: null == activities ? _self._activities : activities // ignore: cast_nullable_to_non_nullable
as List<ActivitySnapshot>,pendingApplications: null == pendingApplications ? _self._pendingApplications : pendingApplications // ignore: cast_nullable_to_non_nullable
as List<SessionActivity>,
  ));
}


}

/// @nodoc
mixin _$ActivitiesState {

 bool get loading; ActivityCollection? get data; Object? get error; int get revision;
/// Create a copy of ActivitiesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivitiesStateCopyWith<ActivitiesState> get copyWith => _$ActivitiesStateCopyWithImpl<ActivitiesState>(this as ActivitiesState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActivitiesState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivitiesState&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.data, _this.data) || other.data == _this.data)&&const DeepCollectionEquality().equals(other.error, _this.error)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ActivitiesState;
  return Object.hash(runtimeType,_this.loading,_this.data,const DeepCollectionEquality().hash(_this.error),_this.revision);
}

@override
String toString() {
  final _this = this as ActivitiesState;
  return 'ActivitiesState(loading: ${_this.loading}, data: ${_this.data}, error: ${_this.error}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ActivitiesStateCopyWith<$Res>  {
  factory $ActivitiesStateCopyWith(ActivitiesState value, $Res Function(ActivitiesState) _then) = _$ActivitiesStateCopyWithImpl;
@useResult
$Res call({
 bool loading, ActivityCollection? data, Object? error, int revision
});


$ActivityCollectionCopyWith<$Res>? get data;

}
/// @nodoc
class _$ActivitiesStateCopyWithImpl<$Res>
    implements $ActivitiesStateCopyWith<$Res> {
  _$ActivitiesStateCopyWithImpl(this._self, this._then);

  final ActivitiesState _self;
  final $Res Function(ActivitiesState) _then;

/// Create a copy of ActivitiesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? loading = null,Object? data = freezed,Object? error = freezed,Object? revision = null,}) {
  return _then(ActivitiesState(
loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as ActivityCollection?,error: freezed == error ? _self.error : error ,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ActivitiesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityCollectionCopyWith<$Res>? get data {
    if (_self.data == null) {
    return null;
  }

  return $ActivityCollectionCopyWith<$Res>(_self.data!, (value) {
    return _then(_self.copyWith(data: value));
  });
}
}


/// Adds pattern-matching-related methods to [ActivitiesState].
extension ActivitiesStatePatterns on ActivitiesState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActivitiesState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActivitiesState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActivitiesState value)  $default,){
final _that = this;
switch (_that) {
case _ActivitiesState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActivitiesState value)?  $default,){
final _that = this;
switch (_that) {
case _ActivitiesState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool loading,  ActivityCollection? data,  Object? error,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivitiesState() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool loading,  ActivityCollection? data,  Object? error,  int revision)  $default,) {final _that = this;
switch (_that) {
case _ActivitiesState():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool loading,  ActivityCollection? data,  Object? error,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _ActivitiesState() when $default != null:
return $default(_that.loading,_that.data,_that.error,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ActivitiesState implements ActivitiesState {
  const _ActivitiesState({this.loading = true, this.data, this.error, this.revision = 0});
  

@override@JsonKey() final  bool loading;
@override final  ActivityCollection? data;
@override final  Object? error;
@override@JsonKey() final  int revision;

/// Create a copy of ActivitiesState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivitiesStateCopyWith<_ActivitiesState> get copyWith => __$ActivitiesStateCopyWithImpl<_ActivitiesState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivitiesState&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.data, data) || other.data == data)&&const DeepCollectionEquality().equals(other.error, error)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,loading,data,const DeepCollectionEquality().hash(error),revision);
}

@override
String toString() {
    return 'ActivitiesState(loading: $loading, data: $data, error: $error, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ActivitiesStateCopyWith<$Res> implements $ActivitiesStateCopyWith<$Res> {
  factory _$ActivitiesStateCopyWith(_ActivitiesState value, $Res Function(_ActivitiesState) _then) = __$ActivitiesStateCopyWithImpl;
@override @useResult
$Res call({
 bool loading, ActivityCollection? data, Object? error, int revision
});


@override $ActivityCollectionCopyWith<$Res>? get data;

}
/// @nodoc
class __$ActivitiesStateCopyWithImpl<$Res>
    implements _$ActivitiesStateCopyWith<$Res> {
  __$ActivitiesStateCopyWithImpl(this._self, this._then);

  final _ActivitiesState _self;
  final $Res Function(_ActivitiesState) _then;

/// Create a copy of ActivitiesState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? loading = null,Object? data = freezed,Object? error = freezed,Object? revision = null,}) {
  return _then(_ActivitiesState(
loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as ActivityCollection?,error: freezed == error ? _self.error : error ,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of ActivitiesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityCollectionCopyWith<$Res>? get data {
    if (_self.data == null) {
    return null;
  }

  return $ActivityCollectionCopyWith<$Res>(_self.data!, (value) {
    return _then(_self.copyWith(data: value));
  });
}
}

// dart format on
