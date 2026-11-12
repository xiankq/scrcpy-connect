// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_observation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DeviceObservationSnapshot {

 String get deviceId; bool get wanted; DeviceObservationPhase get phase; int get generation; bool get notificationsLive; bool get callsLive;
/// Create a copy of DeviceObservationSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceObservationSnapshotCopyWith<DeviceObservationSnapshot> get copyWith => _$DeviceObservationSnapshotCopyWithImpl<DeviceObservationSnapshot>(this as DeviceObservationSnapshot, _$identity);

  /// Serializes this DeviceObservationSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DeviceObservationSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceObservationSnapshot&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.wanted, _this.wanted) || other.wanted == _this.wanted)&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.notificationsLive, _this.notificationsLive) || other.notificationsLive == _this.notificationsLive)&&(identical(other.callsLive, _this.callsLive) || other.callsLive == _this.callsLive));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DeviceObservationSnapshot;
  return Object.hash(runtimeType,_this.deviceId,_this.wanted,_this.phase,_this.generation,_this.notificationsLive,_this.callsLive);
}

@override
String toString() {
  final _this = this as DeviceObservationSnapshot;
  return 'DeviceObservationSnapshot(deviceId: ${_this.deviceId}, wanted: ${_this.wanted}, phase: ${_this.phase}, generation: ${_this.generation}, notificationsLive: ${_this.notificationsLive}, callsLive: ${_this.callsLive})';
}


}

/// @nodoc
abstract mixin class $DeviceObservationSnapshotCopyWith<$Res>  {
  factory $DeviceObservationSnapshotCopyWith(DeviceObservationSnapshot value, $Res Function(DeviceObservationSnapshot) _then) = _$DeviceObservationSnapshotCopyWithImpl;
@useResult
$Res call({
 String deviceId, bool wanted, DeviceObservationPhase phase, int generation, bool notificationsLive, bool callsLive
});




}
/// @nodoc
class _$DeviceObservationSnapshotCopyWithImpl<$Res>
    implements $DeviceObservationSnapshotCopyWith<$Res> {
  _$DeviceObservationSnapshotCopyWithImpl(this._self, this._then);

  final DeviceObservationSnapshot _self;
  final $Res Function(DeviceObservationSnapshot) _then;

/// Create a copy of DeviceObservationSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? wanted = null,Object? phase = null,Object? generation = null,Object? notificationsLive = null,Object? callsLive = null,}) {
  return _then(DeviceObservationSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,wanted: null == wanted ? _self.wanted : wanted // ignore: cast_nullable_to_non_nullable
as bool,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as DeviceObservationPhase,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,notificationsLive: null == notificationsLive ? _self.notificationsLive : notificationsLive // ignore: cast_nullable_to_non_nullable
as bool,callsLive: null == callsLive ? _self.callsLive : callsLive // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceObservationSnapshot].
extension DeviceObservationSnapshotPatterns on DeviceObservationSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceObservationSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceObservationSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceObservationSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _DeviceObservationSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceObservationSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceObservationSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  bool wanted,  DeviceObservationPhase phase,  int generation,  bool notificationsLive,  bool callsLive)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceObservationSnapshot() when $default != null:
return $default(_that.deviceId,_that.wanted,_that.phase,_that.generation,_that.notificationsLive,_that.callsLive);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  bool wanted,  DeviceObservationPhase phase,  int generation,  bool notificationsLive,  bool callsLive)  $default,) {final _that = this;
switch (_that) {
case _DeviceObservationSnapshot():
return $default(_that.deviceId,_that.wanted,_that.phase,_that.generation,_that.notificationsLive,_that.callsLive);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  bool wanted,  DeviceObservationPhase phase,  int generation,  bool notificationsLive,  bool callsLive)?  $default,) {final _that = this;
switch (_that) {
case _DeviceObservationSnapshot() when $default != null:
return $default(_that.deviceId,_that.wanted,_that.phase,_that.generation,_that.notificationsLive,_that.callsLive);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DeviceObservationSnapshot implements DeviceObservationSnapshot {
  const _DeviceObservationSnapshot({required this.deviceId, required this.wanted, required this.phase, required this.generation, this.notificationsLive = false, this.callsLive = false});
  factory _DeviceObservationSnapshot.fromJson(Map<String, dynamic> json) => _$DeviceObservationSnapshotFromJson(json);

@override final  String deviceId;
@override final  bool wanted;
@override final  DeviceObservationPhase phase;
@override final  int generation;
@override@JsonKey() final  bool notificationsLive;
@override@JsonKey() final  bool callsLive;

/// Create a copy of DeviceObservationSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceObservationSnapshotCopyWith<_DeviceObservationSnapshot> get copyWith => __$DeviceObservationSnapshotCopyWithImpl<_DeviceObservationSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DeviceObservationSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceObservationSnapshot&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.wanted, wanted) || other.wanted == wanted)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.notificationsLive, notificationsLive) || other.notificationsLive == notificationsLive)&&(identical(other.callsLive, callsLive) || other.callsLive == callsLive));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,wanted,phase,generation,notificationsLive,callsLive);
}

@override
String toString() {
    return 'DeviceObservationSnapshot(deviceId: $deviceId, wanted: $wanted, phase: $phase, generation: $generation, notificationsLive: $notificationsLive, callsLive: $callsLive)';
}


}

/// @nodoc
abstract mixin class _$DeviceObservationSnapshotCopyWith<$Res> implements $DeviceObservationSnapshotCopyWith<$Res> {
  factory _$DeviceObservationSnapshotCopyWith(_DeviceObservationSnapshot value, $Res Function(_DeviceObservationSnapshot) _then) = __$DeviceObservationSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, bool wanted, DeviceObservationPhase phase, int generation, bool notificationsLive, bool callsLive
});




}
/// @nodoc
class __$DeviceObservationSnapshotCopyWithImpl<$Res>
    implements _$DeviceObservationSnapshotCopyWith<$Res> {
  __$DeviceObservationSnapshotCopyWithImpl(this._self, this._then);

  final _DeviceObservationSnapshot _self;
  final $Res Function(_DeviceObservationSnapshot) _then;

/// Create a copy of DeviceObservationSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? wanted = null,Object? phase = null,Object? generation = null,Object? notificationsLive = null,Object? callsLive = null,}) {
  return _then(_DeviceObservationSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,wanted: null == wanted ? _self.wanted : wanted // ignore: cast_nullable_to_non_nullable
as bool,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as DeviceObservationPhase,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,notificationsLive: null == notificationsLive ? _self.notificationsLive : notificationsLive // ignore: cast_nullable_to_non_nullable
as bool,callsLive: null == callsLive ? _self.callsLive : callsLive // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
