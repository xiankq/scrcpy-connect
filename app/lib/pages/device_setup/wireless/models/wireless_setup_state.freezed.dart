// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'wireless_setup_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WirelessSwitchRequest {

 String get attemptId; String get deviceId; String get connectionId; String get address; int get port;
/// Create a copy of WirelessSwitchRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WirelessSwitchRequestCopyWith<WirelessSwitchRequest> get copyWith => _$WirelessSwitchRequestCopyWithImpl<WirelessSwitchRequest>(this as WirelessSwitchRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WirelessSwitchRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WirelessSwitchRequest&&(identical(other.attemptId, _this.attemptId) || other.attemptId == _this.attemptId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.connectionId, _this.connectionId) || other.connectionId == _this.connectionId)&&(identical(other.address, _this.address) || other.address == _this.address)&&(identical(other.port, _this.port) || other.port == _this.port));
}


@override
int get hashCode {
  final _this = this as WirelessSwitchRequest;
  return Object.hash(runtimeType,_this.attemptId,_this.deviceId,_this.connectionId,_this.address,_this.port);
}

@override
String toString() {
  final _this = this as WirelessSwitchRequest;
  return 'WirelessSwitchRequest(attemptId: ${_this.attemptId}, deviceId: ${_this.deviceId}, connectionId: ${_this.connectionId}, address: ${_this.address}, port: ${_this.port})';
}


}

/// @nodoc
abstract mixin class $WirelessSwitchRequestCopyWith<$Res>  {
  factory $WirelessSwitchRequestCopyWith(WirelessSwitchRequest value, $Res Function(WirelessSwitchRequest) _then) = _$WirelessSwitchRequestCopyWithImpl;
@useResult
$Res call({
 String attemptId, String deviceId, String connectionId, String address, int port
});




}
/// @nodoc
class _$WirelessSwitchRequestCopyWithImpl<$Res>
    implements $WirelessSwitchRequestCopyWith<$Res> {
  _$WirelessSwitchRequestCopyWithImpl(this._self, this._then);

  final WirelessSwitchRequest _self;
  final $Res Function(WirelessSwitchRequest) _then;

/// Create a copy of WirelessSwitchRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? attemptId = null,Object? deviceId = null,Object? connectionId = null,Object? address = null,Object? port = null,}) {
  return _then(WirelessSwitchRequest(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,connectionId: null == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [WirelessSwitchRequest].
extension WirelessSwitchRequestPatterns on WirelessSwitchRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WirelessSwitchRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WirelessSwitchRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WirelessSwitchRequest value)  $default,){
final _that = this;
switch (_that) {
case _WirelessSwitchRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WirelessSwitchRequest value)?  $default,){
final _that = this;
switch (_that) {
case _WirelessSwitchRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String attemptId,  String deviceId,  String connectionId,  String address,  int port)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WirelessSwitchRequest() when $default != null:
return $default(_that.attemptId,_that.deviceId,_that.connectionId,_that.address,_that.port);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String attemptId,  String deviceId,  String connectionId,  String address,  int port)  $default,) {final _that = this;
switch (_that) {
case _WirelessSwitchRequest():
return $default(_that.attemptId,_that.deviceId,_that.connectionId,_that.address,_that.port);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String attemptId,  String deviceId,  String connectionId,  String address,  int port)?  $default,) {final _that = this;
switch (_that) {
case _WirelessSwitchRequest() when $default != null:
return $default(_that.attemptId,_that.deviceId,_that.connectionId,_that.address,_that.port);case _:
  return null;

}
}

}

/// @nodoc


class _WirelessSwitchRequest implements WirelessSwitchRequest {
  const _WirelessSwitchRequest({required this.attemptId, required this.deviceId, required this.connectionId, required this.address, required this.port});
  

@override final  String attemptId;
@override final  String deviceId;
@override final  String connectionId;
@override final  String address;
@override final  int port;

/// Create a copy of WirelessSwitchRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WirelessSwitchRequestCopyWith<_WirelessSwitchRequest> get copyWith => __$WirelessSwitchRequestCopyWithImpl<_WirelessSwitchRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WirelessSwitchRequest&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId)&&(identical(other.address, address) || other.address == address)&&(identical(other.port, port) || other.port == port));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,deviceId,connectionId,address,port);
}

@override
String toString() {
    return 'WirelessSwitchRequest(attemptId: $attemptId, deviceId: $deviceId, connectionId: $connectionId, address: $address, port: $port)';
}


}

/// @nodoc
abstract mixin class _$WirelessSwitchRequestCopyWith<$Res> implements $WirelessSwitchRequestCopyWith<$Res> {
  factory _$WirelessSwitchRequestCopyWith(_WirelessSwitchRequest value, $Res Function(_WirelessSwitchRequest) _then) = __$WirelessSwitchRequestCopyWithImpl;
@override @useResult
$Res call({
 String attemptId, String deviceId, String connectionId, String address, int port
});




}
/// @nodoc
class __$WirelessSwitchRequestCopyWithImpl<$Res>
    implements _$WirelessSwitchRequestCopyWith<$Res> {
  __$WirelessSwitchRequestCopyWithImpl(this._self, this._then);

  final _WirelessSwitchRequest _self;
  final $Res Function(_WirelessSwitchRequest) _then;

/// Create a copy of WirelessSwitchRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? deviceId = null,Object? connectionId = null,Object? address = null,Object? port = null,}) {
  return _then(_WirelessSwitchRequest(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,connectionId: null == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$WirelessSetupState {

 WirelessSetupPhase get phase; List<DeviceNetworkAddress> get addresses; WirelessSwitchRequest? get confirmation; WirelessReceipt? get result; String? get error; String? get notice;
/// Create a copy of WirelessSetupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WirelessSetupStateCopyWith<WirelessSetupState> get copyWith => _$WirelessSetupStateCopyWithImpl<WirelessSetupState>(this as WirelessSetupState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WirelessSetupState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WirelessSetupState&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&const DeepCollectionEquality().equals(other.addresses, _this.addresses)&&(identical(other.confirmation, _this.confirmation) || other.confirmation == _this.confirmation)&&(identical(other.result, _this.result) || other.result == _this.result)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.notice, _this.notice) || other.notice == _this.notice));
}


@override
int get hashCode {
  final _this = this as WirelessSetupState;
  return Object.hash(runtimeType,_this.phase,const DeepCollectionEquality().hash(_this.addresses),_this.confirmation,_this.result,_this.error,_this.notice);
}

@override
String toString() {
  final _this = this as WirelessSetupState;
  return 'WirelessSetupState(phase: ${_this.phase}, addresses: ${_this.addresses}, confirmation: ${_this.confirmation}, result: ${_this.result}, error: ${_this.error}, notice: ${_this.notice})';
}


}

/// @nodoc
abstract mixin class $WirelessSetupStateCopyWith<$Res>  {
  factory $WirelessSetupStateCopyWith(WirelessSetupState value, $Res Function(WirelessSetupState) _then) = _$WirelessSetupStateCopyWithImpl;
@useResult
$Res call({
 WirelessSetupPhase phase, List<DeviceNetworkAddress> addresses, WirelessSwitchRequest? confirmation, WirelessReceipt? result, String? error, String? notice
});


$WirelessSwitchRequestCopyWith<$Res>? get confirmation;$WirelessReceiptCopyWith<$Res>? get result;

}
/// @nodoc
class _$WirelessSetupStateCopyWithImpl<$Res>
    implements $WirelessSetupStateCopyWith<$Res> {
  _$WirelessSetupStateCopyWithImpl(this._self, this._then);

  final WirelessSetupState _self;
  final $Res Function(WirelessSetupState) _then;

/// Create a copy of WirelessSetupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? addresses = null,Object? confirmation = freezed,Object? result = freezed,Object? error = freezed,Object? notice = freezed,}) {
  return _then(WirelessSetupState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as WirelessSetupPhase,addresses: null == addresses ? _self.addresses : addresses // ignore: cast_nullable_to_non_nullable
as List<DeviceNetworkAddress>,confirmation: freezed == confirmation ? _self.confirmation : confirmation // ignore: cast_nullable_to_non_nullable
as WirelessSwitchRequest?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as WirelessReceipt?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,notice: freezed == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of WirelessSetupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WirelessSwitchRequestCopyWith<$Res>? get confirmation {
    if (_self.confirmation == null) {
    return null;
  }

  return $WirelessSwitchRequestCopyWith<$Res>(_self.confirmation!, (value) {
    return _then(_self.copyWith(confirmation: value));
  });
}/// Create a copy of WirelessSetupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WirelessReceiptCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $WirelessReceiptCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}


/// Adds pattern-matching-related methods to [WirelessSetupState].
extension WirelessSetupStatePatterns on WirelessSetupState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WirelessSetupState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WirelessSetupState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WirelessSetupState value)  $default,){
final _that = this;
switch (_that) {
case _WirelessSetupState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WirelessSetupState value)?  $default,){
final _that = this;
switch (_that) {
case _WirelessSetupState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WirelessSetupPhase phase,  List<DeviceNetworkAddress> addresses,  WirelessSwitchRequest? confirmation,  WirelessReceipt? result,  String? error,  String? notice)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WirelessSetupState() when $default != null:
return $default(_that.phase,_that.addresses,_that.confirmation,_that.result,_that.error,_that.notice);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WirelessSetupPhase phase,  List<DeviceNetworkAddress> addresses,  WirelessSwitchRequest? confirmation,  WirelessReceipt? result,  String? error,  String? notice)  $default,) {final _that = this;
switch (_that) {
case _WirelessSetupState():
return $default(_that.phase,_that.addresses,_that.confirmation,_that.result,_that.error,_that.notice);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WirelessSetupPhase phase,  List<DeviceNetworkAddress> addresses,  WirelessSwitchRequest? confirmation,  WirelessReceipt? result,  String? error,  String? notice)?  $default,) {final _that = this;
switch (_that) {
case _WirelessSetupState() when $default != null:
return $default(_that.phase,_that.addresses,_that.confirmation,_that.result,_that.error,_that.notice);case _:
  return null;

}
}

}

/// @nodoc


class _WirelessSetupState extends WirelessSetupState {
  const _WirelessSetupState({this.phase = WirelessSetupPhase.reading,  List<DeviceNetworkAddress> addresses = const [], this.confirmation, this.result, this.error, this.notice}): _addresses = addresses,super._();
  

@override@JsonKey() final  WirelessSetupPhase phase;
 final  List<DeviceNetworkAddress> _addresses;
@override@JsonKey() List<DeviceNetworkAddress> get addresses {
  if (_addresses is EqualUnmodifiableListView) return _addresses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_addresses);
}

@override final  WirelessSwitchRequest? confirmation;
@override final  WirelessReceipt? result;
@override final  String? error;
@override final  String? notice;

/// Create a copy of WirelessSetupState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WirelessSetupStateCopyWith<_WirelessSetupState> get copyWith => __$WirelessSetupStateCopyWithImpl<_WirelessSetupState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WirelessSetupState&&(identical(other.phase, phase) || other.phase == phase)&&const DeepCollectionEquality().equals(other.addresses, _addresses)&&(identical(other.confirmation, confirmation) || other.confirmation == confirmation)&&(identical(other.result, result) || other.result == result)&&(identical(other.error, error) || other.error == error)&&(identical(other.notice, notice) || other.notice == notice));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,const DeepCollectionEquality().hash(_addresses),confirmation,result,error,notice);
}

@override
String toString() {
    return 'WirelessSetupState(phase: $phase, addresses: $addresses, confirmation: $confirmation, result: $result, error: $error, notice: $notice)';
}


}

/// @nodoc
abstract mixin class _$WirelessSetupStateCopyWith<$Res> implements $WirelessSetupStateCopyWith<$Res> {
  factory _$WirelessSetupStateCopyWith(_WirelessSetupState value, $Res Function(_WirelessSetupState) _then) = __$WirelessSetupStateCopyWithImpl;
@override @useResult
$Res call({
 WirelessSetupPhase phase, List<DeviceNetworkAddress> addresses, WirelessSwitchRequest? confirmation, WirelessReceipt? result, String? error, String? notice
});


@override $WirelessSwitchRequestCopyWith<$Res>? get confirmation;@override $WirelessReceiptCopyWith<$Res>? get result;

}
/// @nodoc
class __$WirelessSetupStateCopyWithImpl<$Res>
    implements _$WirelessSetupStateCopyWith<$Res> {
  __$WirelessSetupStateCopyWithImpl(this._self, this._then);

  final _WirelessSetupState _self;
  final $Res Function(_WirelessSetupState) _then;

/// Create a copy of WirelessSetupState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? addresses = null,Object? confirmation = freezed,Object? result = freezed,Object? error = freezed,Object? notice = freezed,}) {
  return _then(_WirelessSetupState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as WirelessSetupPhase,addresses: null == addresses ? _self._addresses : addresses // ignore: cast_nullable_to_non_nullable
as List<DeviceNetworkAddress>,confirmation: freezed == confirmation ? _self.confirmation : confirmation // ignore: cast_nullable_to_non_nullable
as WirelessSwitchRequest?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as WirelessReceipt?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,notice: freezed == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of WirelessSetupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WirelessSwitchRequestCopyWith<$Res>? get confirmation {
    if (_self.confirmation == null) {
    return null;
  }

  return $WirelessSwitchRequestCopyWith<$Res>(_self.confirmation!, (value) {
    return _then(_self.copyWith(confirmation: value));
  });
}/// Create a copy of WirelessSetupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WirelessReceiptCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $WirelessReceiptCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

// dart format on
