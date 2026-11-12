// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'connection_attempt_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConnectionAttemptState {

 ConnectionAttemptPhase get phase; String? get deviceId; String? get address; String? get connectedDeviceId; PairingReceipt? get pairing; SetupIssue? get failure; String? get notice;
/// Create a copy of ConnectionAttemptState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionAttemptStateCopyWith<ConnectionAttemptState> get copyWith => _$ConnectionAttemptStateCopyWithImpl<ConnectionAttemptState>(this as ConnectionAttemptState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConnectionAttemptState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionAttemptState&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.address, _this.address) || other.address == _this.address)&&(identical(other.connectedDeviceId, _this.connectedDeviceId) || other.connectedDeviceId == _this.connectedDeviceId)&&(identical(other.pairing, _this.pairing) || other.pairing == _this.pairing)&&(identical(other.failure, _this.failure) || other.failure == _this.failure)&&(identical(other.notice, _this.notice) || other.notice == _this.notice));
}


@override
int get hashCode {
  final _this = this as ConnectionAttemptState;
  return Object.hash(runtimeType,_this.phase,_this.deviceId,_this.address,_this.connectedDeviceId,_this.pairing,_this.failure,_this.notice);
}

@override
String toString() {
  final _this = this as ConnectionAttemptState;
  return 'ConnectionAttemptState(phase: ${_this.phase}, deviceId: ${_this.deviceId}, address: ${_this.address}, connectedDeviceId: ${_this.connectedDeviceId}, pairing: ${_this.pairing}, failure: ${_this.failure}, notice: ${_this.notice})';
}


}

/// @nodoc
abstract mixin class $ConnectionAttemptStateCopyWith<$Res>  {
  factory $ConnectionAttemptStateCopyWith(ConnectionAttemptState value, $Res Function(ConnectionAttemptState) _then) = _$ConnectionAttemptStateCopyWithImpl;
@useResult
$Res call({
 ConnectionAttemptPhase phase, String? deviceId, String? address, String? connectedDeviceId, PairingReceipt? pairing, SetupIssue? failure, String? notice
});


$PairingReceiptCopyWith<$Res>? get pairing;$SetupIssueCopyWith<$Res>? get failure;

}
/// @nodoc
class _$ConnectionAttemptStateCopyWithImpl<$Res>
    implements $ConnectionAttemptStateCopyWith<$Res> {
  _$ConnectionAttemptStateCopyWithImpl(this._self, this._then);

  final ConnectionAttemptState _self;
  final $Res Function(ConnectionAttemptState) _then;

/// Create a copy of ConnectionAttemptState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? deviceId = freezed,Object? address = freezed,Object? connectedDeviceId = freezed,Object? pairing = freezed,Object? failure = freezed,Object? notice = freezed,}) {
  return _then(ConnectionAttemptState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as ConnectionAttemptPhase,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,address: freezed == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String?,connectedDeviceId: freezed == connectedDeviceId ? _self.connectedDeviceId : connectedDeviceId // ignore: cast_nullable_to_non_nullable
as String?,pairing: freezed == pairing ? _self.pairing : pairing // ignore: cast_nullable_to_non_nullable
as PairingReceipt?,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as SetupIssue?,notice: freezed == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of ConnectionAttemptState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PairingReceiptCopyWith<$Res>? get pairing {
    if (_self.pairing == null) {
    return null;
  }

  return $PairingReceiptCopyWith<$Res>(_self.pairing!, (value) {
    return _then(_self.copyWith(pairing: value));
  });
}/// Create a copy of ConnectionAttemptState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SetupIssueCopyWith<$Res>? get failure {
    if (_self.failure == null) {
    return null;
  }

  return $SetupIssueCopyWith<$Res>(_self.failure!, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConnectionAttemptState].
extension ConnectionAttemptStatePatterns on ConnectionAttemptState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConnectionAttemptState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConnectionAttemptState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConnectionAttemptState value)  $default,){
final _that = this;
switch (_that) {
case _ConnectionAttemptState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConnectionAttemptState value)?  $default,){
final _that = this;
switch (_that) {
case _ConnectionAttemptState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConnectionAttemptPhase phase,  String? deviceId,  String? address,  String? connectedDeviceId,  PairingReceipt? pairing,  SetupIssue? failure,  String? notice)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConnectionAttemptState() when $default != null:
return $default(_that.phase,_that.deviceId,_that.address,_that.connectedDeviceId,_that.pairing,_that.failure,_that.notice);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConnectionAttemptPhase phase,  String? deviceId,  String? address,  String? connectedDeviceId,  PairingReceipt? pairing,  SetupIssue? failure,  String? notice)  $default,) {final _that = this;
switch (_that) {
case _ConnectionAttemptState():
return $default(_that.phase,_that.deviceId,_that.address,_that.connectedDeviceId,_that.pairing,_that.failure,_that.notice);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConnectionAttemptPhase phase,  String? deviceId,  String? address,  String? connectedDeviceId,  PairingReceipt? pairing,  SetupIssue? failure,  String? notice)?  $default,) {final _that = this;
switch (_that) {
case _ConnectionAttemptState() when $default != null:
return $default(_that.phase,_that.deviceId,_that.address,_that.connectedDeviceId,_that.pairing,_that.failure,_that.notice);case _:
  return null;

}
}

}

/// @nodoc


class _ConnectionAttemptState extends ConnectionAttemptState {
  const _ConnectionAttemptState({this.phase = ConnectionAttemptPhase.idle, this.deviceId, this.address, this.connectedDeviceId, this.pairing, this.failure, this.notice}): super._();
  

@override@JsonKey() final  ConnectionAttemptPhase phase;
@override final  String? deviceId;
@override final  String? address;
@override final  String? connectedDeviceId;
@override final  PairingReceipt? pairing;
@override final  SetupIssue? failure;
@override final  String? notice;

/// Create a copy of ConnectionAttemptState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConnectionAttemptStateCopyWith<_ConnectionAttemptState> get copyWith => __$ConnectionAttemptStateCopyWithImpl<_ConnectionAttemptState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConnectionAttemptState&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.address, address) || other.address == address)&&(identical(other.connectedDeviceId, connectedDeviceId) || other.connectedDeviceId == connectedDeviceId)&&(identical(other.pairing, pairing) || other.pairing == pairing)&&(identical(other.failure, failure) || other.failure == failure)&&(identical(other.notice, notice) || other.notice == notice));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,deviceId,address,connectedDeviceId,pairing,failure,notice);
}

@override
String toString() {
    return 'ConnectionAttemptState(phase: $phase, deviceId: $deviceId, address: $address, connectedDeviceId: $connectedDeviceId, pairing: $pairing, failure: $failure, notice: $notice)';
}


}

/// @nodoc
abstract mixin class _$ConnectionAttemptStateCopyWith<$Res> implements $ConnectionAttemptStateCopyWith<$Res> {
  factory _$ConnectionAttemptStateCopyWith(_ConnectionAttemptState value, $Res Function(_ConnectionAttemptState) _then) = __$ConnectionAttemptStateCopyWithImpl;
@override @useResult
$Res call({
 ConnectionAttemptPhase phase, String? deviceId, String? address, String? connectedDeviceId, PairingReceipt? pairing, SetupIssue? failure, String? notice
});


@override $PairingReceiptCopyWith<$Res>? get pairing;@override $SetupIssueCopyWith<$Res>? get failure;

}
/// @nodoc
class __$ConnectionAttemptStateCopyWithImpl<$Res>
    implements _$ConnectionAttemptStateCopyWith<$Res> {
  __$ConnectionAttemptStateCopyWithImpl(this._self, this._then);

  final _ConnectionAttemptState _self;
  final $Res Function(_ConnectionAttemptState) _then;

/// Create a copy of ConnectionAttemptState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? deviceId = freezed,Object? address = freezed,Object? connectedDeviceId = freezed,Object? pairing = freezed,Object? failure = freezed,Object? notice = freezed,}) {
  return _then(_ConnectionAttemptState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as ConnectionAttemptPhase,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,address: freezed == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String?,connectedDeviceId: freezed == connectedDeviceId ? _self.connectedDeviceId : connectedDeviceId // ignore: cast_nullable_to_non_nullable
as String?,pairing: freezed == pairing ? _self.pairing : pairing // ignore: cast_nullable_to_non_nullable
as PairingReceipt?,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as SetupIssue?,notice: freezed == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of ConnectionAttemptState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PairingReceiptCopyWith<$Res>? get pairing {
    if (_self.pairing == null) {
    return null;
  }

  return $PairingReceiptCopyWith<$Res>(_self.pairing!, (value) {
    return _then(_self.copyWith(pairing: value));
  });
}/// Create a copy of ConnectionAttemptState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SetupIssueCopyWith<$Res>? get failure {
    if (_self.failure == null) {
    return null;
  }

  return $SetupIssueCopyWith<$Res>(_self.failure!, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

// dart format on
