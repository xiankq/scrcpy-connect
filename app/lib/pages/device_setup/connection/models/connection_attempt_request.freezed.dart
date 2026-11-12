// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'connection_attempt_request.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConnectionAttemptRequest {

 String? get deviceId;
/// Create a copy of ConnectionAttemptRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionAttemptRequestCopyWith<ConnectionAttemptRequest> get copyWith => _$ConnectionAttemptRequestCopyWithImpl<ConnectionAttemptRequest>(this as ConnectionAttemptRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConnectionAttemptRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionAttemptRequest&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId));
}


@override
int get hashCode {
  final _this = this as ConnectionAttemptRequest;
  return Object.hash(runtimeType,_this.deviceId);
}

@override
String toString() {
  final _this = this as ConnectionAttemptRequest;
  return 'ConnectionAttemptRequest(deviceId: ${_this.deviceId})';
}


}

/// @nodoc
abstract mixin class $ConnectionAttemptRequestCopyWith<$Res>  {
  factory $ConnectionAttemptRequestCopyWith(ConnectionAttemptRequest value, $Res Function(ConnectionAttemptRequest) _then) = _$ConnectionAttemptRequestCopyWithImpl;
@useResult
$Res call({
 String? deviceId
});




}
/// @nodoc
class _$ConnectionAttemptRequestCopyWithImpl<$Res>
    implements $ConnectionAttemptRequestCopyWith<$Res> {
  _$ConnectionAttemptRequestCopyWithImpl(this._self, this._then);

  final ConnectionAttemptRequest _self;
  final $Res Function(ConnectionAttemptRequest) _then;

/// Create a copy of ConnectionAttemptRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = freezed,}) {
  return _then(_self.copyWith(
deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ConnectionAttemptRequest].
extension ConnectionAttemptRequestPatterns on ConnectionAttemptRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PairDeviceRequest value)?  pair,TResult Function( ConnectDeviceRequest value)?  connect,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PairDeviceRequest() when pair != null:
return pair(_that);case ConnectDeviceRequest() when connect != null:
return connect(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PairDeviceRequest value)  pair,required TResult Function( ConnectDeviceRequest value)  connect,}){
final _that = this;
switch (_that) {
case PairDeviceRequest():
return pair(_that);case ConnectDeviceRequest():
return connect(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PairDeviceRequest value)?  pair,TResult? Function( ConnectDeviceRequest value)?  connect,}){
final _that = this;
switch (_that) {
case PairDeviceRequest() when pair != null:
return pair(_that);case ConnectDeviceRequest() when connect != null:
return connect(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String address,  int port,  String code,  String? deviceId)?  pair,TResult Function( DeviceEndpoint endpoint,  String? deviceId,  bool configure)?  connect,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PairDeviceRequest() when pair != null:
return pair(_that.address,_that.port,_that.code,_that.deviceId);case ConnectDeviceRequest() when connect != null:
return connect(_that.endpoint,_that.deviceId,_that.configure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String address,  int port,  String code,  String? deviceId)  pair,required TResult Function( DeviceEndpoint endpoint,  String? deviceId,  bool configure)  connect,}) {final _that = this;
switch (_that) {
case PairDeviceRequest():
return pair(_that.address,_that.port,_that.code,_that.deviceId);case ConnectDeviceRequest():
return connect(_that.endpoint,_that.deviceId,_that.configure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String address,  int port,  String code,  String? deviceId)?  pair,TResult? Function( DeviceEndpoint endpoint,  String? deviceId,  bool configure)?  connect,}) {final _that = this;
switch (_that) {
case PairDeviceRequest() when pair != null:
return pair(_that.address,_that.port,_that.code,_that.deviceId);case ConnectDeviceRequest() when connect != null:
return connect(_that.endpoint,_that.deviceId,_that.configure);case _:
  return null;

}
}

}

/// @nodoc


class PairDeviceRequest extends ConnectionAttemptRequest {
  const PairDeviceRequest({required this.address, required this.port, required this.code, this.deviceId}): super._();
  

 final  String address;
 final  int port;
 final  String code;
@override final  String? deviceId;

/// Create a copy of ConnectionAttemptRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PairDeviceRequestCopyWith<PairDeviceRequest> get copyWith => _$PairDeviceRequestCopyWithImpl<PairDeviceRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PairDeviceRequest&&(identical(other.address, address) || other.address == address)&&(identical(other.port, port) || other.port == port)&&(identical(other.code, code) || other.code == code)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,address,port,code,deviceId);
}

@override
String toString() {
    return 'ConnectionAttemptRequest.pair(address: $address, port: $port, code: $code, deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $PairDeviceRequestCopyWith<$Res> implements $ConnectionAttemptRequestCopyWith<$Res> {
  factory $PairDeviceRequestCopyWith(PairDeviceRequest value, $Res Function(PairDeviceRequest) _then) = _$PairDeviceRequestCopyWithImpl;
@override @useResult
$Res call({
 String address, int port, String code, String? deviceId
});




}
/// @nodoc
class _$PairDeviceRequestCopyWithImpl<$Res>
    implements $PairDeviceRequestCopyWith<$Res> {
  _$PairDeviceRequestCopyWithImpl(this._self, this._then);

  final PairDeviceRequest _self;
  final $Res Function(PairDeviceRequest) _then;

/// Create a copy of ConnectionAttemptRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? address = null,Object? port = null,Object? code = null,Object? deviceId = freezed,}) {
  return _then(PairDeviceRequest(
address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class ConnectDeviceRequest extends ConnectionAttemptRequest {
  const ConnectDeviceRequest({required this.endpoint, this.deviceId, this.configure = false}): super._();
  

 final  DeviceEndpoint endpoint;
@override final  String? deviceId;
@JsonKey() final  bool configure;

/// Create a copy of ConnectionAttemptRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectDeviceRequestCopyWith<ConnectDeviceRequest> get copyWith => _$ConnectDeviceRequestCopyWithImpl<ConnectDeviceRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectDeviceRequest&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.configure, configure) || other.configure == configure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,endpoint,deviceId,configure);
}

@override
String toString() {
    return 'ConnectionAttemptRequest.connect(endpoint: $endpoint, deviceId: $deviceId, configure: $configure)';
}


}

/// @nodoc
abstract mixin class $ConnectDeviceRequestCopyWith<$Res> implements $ConnectionAttemptRequestCopyWith<$Res> {
  factory $ConnectDeviceRequestCopyWith(ConnectDeviceRequest value, $Res Function(ConnectDeviceRequest) _then) = _$ConnectDeviceRequestCopyWithImpl;
@override @useResult
$Res call({
 DeviceEndpoint endpoint, String? deviceId, bool configure
});


$DeviceEndpointCopyWith<$Res> get endpoint;

}
/// @nodoc
class _$ConnectDeviceRequestCopyWithImpl<$Res>
    implements $ConnectDeviceRequestCopyWith<$Res> {
  _$ConnectDeviceRequestCopyWithImpl(this._self, this._then);

  final ConnectDeviceRequest _self;
  final $Res Function(ConnectDeviceRequest) _then;

/// Create a copy of ConnectionAttemptRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? endpoint = null,Object? deviceId = freezed,Object? configure = null,}) {
  return _then(ConnectDeviceRequest(
endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as DeviceEndpoint,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,configure: null == configure ? _self.configure : configure // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ConnectionAttemptRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceEndpointCopyWith<$Res> get endpoint {
  
  return $DeviceEndpointCopyWith<$Res>(_self.endpoint, (value) {
    return _then(_self.copyWith(endpoint: value));
  });
}
}

// dart format on
