// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_setup.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DiscoveredDevice {

 DiscoveredDeviceKind get kind; String get instance; String get serviceName; String get hostname; List<DiscoveredEndpoint> get endpoints; String? get deviceId;
/// Create a copy of DiscoveredDevice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiscoveredDeviceCopyWith<DiscoveredDevice> get copyWith => _$DiscoveredDeviceCopyWithImpl<DiscoveredDevice>(this as DiscoveredDevice, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DiscoveredDevice;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiscoveredDevice&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.instance, _this.instance) || other.instance == _this.instance)&&(identical(other.serviceName, _this.serviceName) || other.serviceName == _this.serviceName)&&(identical(other.hostname, _this.hostname) || other.hostname == _this.hostname)&&const DeepCollectionEquality().equals(other.endpoints, _this.endpoints)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId));
}


@override
int get hashCode {
  final _this = this as DiscoveredDevice;
  return Object.hash(runtimeType,_this.kind,_this.instance,_this.serviceName,_this.hostname,const DeepCollectionEquality().hash(_this.endpoints),_this.deviceId);
}

@override
String toString() {
  final _this = this as DiscoveredDevice;
  return 'DiscoveredDevice(kind: ${_this.kind}, instance: ${_this.instance}, serviceName: ${_this.serviceName}, hostname: ${_this.hostname}, endpoints: ${_this.endpoints}, deviceId: ${_this.deviceId})';
}


}

/// @nodoc
abstract mixin class $DiscoveredDeviceCopyWith<$Res>  {
  factory $DiscoveredDeviceCopyWith(DiscoveredDevice value, $Res Function(DiscoveredDevice) _then) = _$DiscoveredDeviceCopyWithImpl;
@useResult
$Res call({
 DiscoveredDeviceKind kind, String instance, String serviceName, String hostname, List<DiscoveredEndpoint> endpoints, String? deviceId
});




}
/// @nodoc
class _$DiscoveredDeviceCopyWithImpl<$Res>
    implements $DiscoveredDeviceCopyWith<$Res> {
  _$DiscoveredDeviceCopyWithImpl(this._self, this._then);

  final DiscoveredDevice _self;
  final $Res Function(DiscoveredDevice) _then;

/// Create a copy of DiscoveredDevice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? instance = null,Object? serviceName = null,Object? hostname = null,Object? endpoints = null,Object? deviceId = freezed,}) {
  return _then(DiscoveredDevice(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as DiscoveredDeviceKind,instance: null == instance ? _self.instance : instance // ignore: cast_nullable_to_non_nullable
as String,serviceName: null == serviceName ? _self.serviceName : serviceName // ignore: cast_nullable_to_non_nullable
as String,hostname: null == hostname ? _self.hostname : hostname // ignore: cast_nullable_to_non_nullable
as String,endpoints: null == endpoints ? _self.endpoints : endpoints // ignore: cast_nullable_to_non_nullable
as List<DiscoveredEndpoint>,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [DiscoveredDevice].
extension DiscoveredDevicePatterns on DiscoveredDevice {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DiscoveredDevice value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DiscoveredDevice() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DiscoveredDevice value)  $default,){
final _that = this;
switch (_that) {
case _DiscoveredDevice():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DiscoveredDevice value)?  $default,){
final _that = this;
switch (_that) {
case _DiscoveredDevice() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DiscoveredDeviceKind kind,  String instance,  String serviceName,  String hostname,  List<DiscoveredEndpoint> endpoints,  String? deviceId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DiscoveredDevice() when $default != null:
return $default(_that.kind,_that.instance,_that.serviceName,_that.hostname,_that.endpoints,_that.deviceId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DiscoveredDeviceKind kind,  String instance,  String serviceName,  String hostname,  List<DiscoveredEndpoint> endpoints,  String? deviceId)  $default,) {final _that = this;
switch (_that) {
case _DiscoveredDevice():
return $default(_that.kind,_that.instance,_that.serviceName,_that.hostname,_that.endpoints,_that.deviceId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DiscoveredDeviceKind kind,  String instance,  String serviceName,  String hostname,  List<DiscoveredEndpoint> endpoints,  String? deviceId)?  $default,) {final _that = this;
switch (_that) {
case _DiscoveredDevice() when $default != null:
return $default(_that.kind,_that.instance,_that.serviceName,_that.hostname,_that.endpoints,_that.deviceId);case _:
  return null;

}
}

}

/// @nodoc


class _DiscoveredDevice extends DiscoveredDevice {
  const _DiscoveredDevice({required this.kind, required this.instance, required this.serviceName, required this.hostname, required  List<DiscoveredEndpoint> endpoints, this.deviceId}): _endpoints = endpoints,super._();
  

@override final  DiscoveredDeviceKind kind;
@override final  String instance;
@override final  String serviceName;
@override final  String hostname;
 final  List<DiscoveredEndpoint> _endpoints;
@override List<DiscoveredEndpoint> get endpoints {
  if (_endpoints is EqualUnmodifiableListView) return _endpoints;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_endpoints);
}

@override final  String? deviceId;

/// Create a copy of DiscoveredDevice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DiscoveredDeviceCopyWith<_DiscoveredDevice> get copyWith => __$DiscoveredDeviceCopyWithImpl<_DiscoveredDevice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DiscoveredDevice&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.instance, instance) || other.instance == instance)&&(identical(other.serviceName, serviceName) || other.serviceName == serviceName)&&(identical(other.hostname, hostname) || other.hostname == hostname)&&const DeepCollectionEquality().equals(other.endpoints, _endpoints)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,instance,serviceName,hostname,const DeepCollectionEquality().hash(_endpoints),deviceId);
}

@override
String toString() {
    return 'DiscoveredDevice(kind: $kind, instance: $instance, serviceName: $serviceName, hostname: $hostname, endpoints: $endpoints, deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class _$DiscoveredDeviceCopyWith<$Res> implements $DiscoveredDeviceCopyWith<$Res> {
  factory _$DiscoveredDeviceCopyWith(_DiscoveredDevice value, $Res Function(_DiscoveredDevice) _then) = __$DiscoveredDeviceCopyWithImpl;
@override @useResult
$Res call({
 DiscoveredDeviceKind kind, String instance, String serviceName, String hostname, List<DiscoveredEndpoint> endpoints, String? deviceId
});




}
/// @nodoc
class __$DiscoveredDeviceCopyWithImpl<$Res>
    implements _$DiscoveredDeviceCopyWith<$Res> {
  __$DiscoveredDeviceCopyWithImpl(this._self, this._then);

  final _DiscoveredDevice _self;
  final $Res Function(_DiscoveredDevice) _then;

/// Create a copy of DiscoveredDevice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? instance = null,Object? serviceName = null,Object? hostname = null,Object? endpoints = null,Object? deviceId = freezed,}) {
  return _then(_DiscoveredDevice(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as DiscoveredDeviceKind,instance: null == instance ? _self.instance : instance // ignore: cast_nullable_to_non_nullable
as String,serviceName: null == serviceName ? _self.serviceName : serviceName // ignore: cast_nullable_to_non_nullable
as String,hostname: null == hostname ? _self.hostname : hostname // ignore: cast_nullable_to_non_nullable
as String,endpoints: null == endpoints ? _self._endpoints : endpoints // ignore: cast_nullable_to_non_nullable
as List<DiscoveredEndpoint>,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$PairingReceipt {

 String get guid; String get address; DeviceSnapshot? get device; DeviceConnectionReceipt? get connection; bool get cancelled; bool get connectionPortRequired; SetupIssue? get connectionFailure;
/// Create a copy of PairingReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PairingReceiptCopyWith<PairingReceipt> get copyWith => _$PairingReceiptCopyWithImpl<PairingReceipt>(this as PairingReceipt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PairingReceipt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PairingReceipt&&(identical(other.guid, _this.guid) || other.guid == _this.guid)&&(identical(other.address, _this.address) || other.address == _this.address)&&(identical(other.device, _this.device) || other.device == _this.device)&&(identical(other.connection, _this.connection) || other.connection == _this.connection)&&(identical(other.cancelled, _this.cancelled) || other.cancelled == _this.cancelled)&&(identical(other.connectionPortRequired, _this.connectionPortRequired) || other.connectionPortRequired == _this.connectionPortRequired)&&(identical(other.connectionFailure, _this.connectionFailure) || other.connectionFailure == _this.connectionFailure));
}


@override
int get hashCode {
  final _this = this as PairingReceipt;
  return Object.hash(runtimeType,_this.guid,_this.address,_this.device,_this.connection,_this.cancelled,_this.connectionPortRequired,_this.connectionFailure);
}

@override
String toString() {
  final _this = this as PairingReceipt;
  return 'PairingReceipt(guid: ${_this.guid}, address: ${_this.address}, device: ${_this.device}, connection: ${_this.connection}, cancelled: ${_this.cancelled}, connectionPortRequired: ${_this.connectionPortRequired}, connectionFailure: ${_this.connectionFailure})';
}


}

/// @nodoc
abstract mixin class $PairingReceiptCopyWith<$Res>  {
  factory $PairingReceiptCopyWith(PairingReceipt value, $Res Function(PairingReceipt) _then) = _$PairingReceiptCopyWithImpl;
@useResult
$Res call({
 String guid, String address, DeviceSnapshot? device, DeviceConnectionReceipt? connection, bool cancelled, bool connectionPortRequired, SetupIssue? connectionFailure
});


$DeviceSnapshotCopyWith<$Res>? get device;$DeviceConnectionReceiptCopyWith<$Res>? get connection;$SetupIssueCopyWith<$Res>? get connectionFailure;

}
/// @nodoc
class _$PairingReceiptCopyWithImpl<$Res>
    implements $PairingReceiptCopyWith<$Res> {
  _$PairingReceiptCopyWithImpl(this._self, this._then);

  final PairingReceipt _self;
  final $Res Function(PairingReceipt) _then;

/// Create a copy of PairingReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? guid = null,Object? address = null,Object? device = freezed,Object? connection = freezed,Object? cancelled = null,Object? connectionPortRequired = null,Object? connectionFailure = freezed,}) {
  return _then(PairingReceipt(
guid: null == guid ? _self.guid : guid // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,device: freezed == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as DeviceSnapshot?,connection: freezed == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as DeviceConnectionReceipt?,cancelled: null == cancelled ? _self.cancelled : cancelled // ignore: cast_nullable_to_non_nullable
as bool,connectionPortRequired: null == connectionPortRequired ? _self.connectionPortRequired : connectionPortRequired // ignore: cast_nullable_to_non_nullable
as bool,connectionFailure: freezed == connectionFailure ? _self.connectionFailure : connectionFailure // ignore: cast_nullable_to_non_nullable
as SetupIssue?,
  ));
}
/// Create a copy of PairingReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceSnapshotCopyWith<$Res>? get device {
    if (_self.device == null) {
    return null;
  }

  return $DeviceSnapshotCopyWith<$Res>(_self.device!, (value) {
    return _then(_self.copyWith(device: value));
  });
}/// Create a copy of PairingReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceConnectionReceiptCopyWith<$Res>? get connection {
    if (_self.connection == null) {
    return null;
  }

  return $DeviceConnectionReceiptCopyWith<$Res>(_self.connection!, (value) {
    return _then(_self.copyWith(connection: value));
  });
}/// Create a copy of PairingReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SetupIssueCopyWith<$Res>? get connectionFailure {
    if (_self.connectionFailure == null) {
    return null;
  }

  return $SetupIssueCopyWith<$Res>(_self.connectionFailure!, (value) {
    return _then(_self.copyWith(connectionFailure: value));
  });
}
}


/// Adds pattern-matching-related methods to [PairingReceipt].
extension PairingReceiptPatterns on PairingReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PairingReceipt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PairingReceipt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PairingReceipt value)  $default,){
final _that = this;
switch (_that) {
case _PairingReceipt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PairingReceipt value)?  $default,){
final _that = this;
switch (_that) {
case _PairingReceipt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String guid,  String address,  DeviceSnapshot? device,  DeviceConnectionReceipt? connection,  bool cancelled,  bool connectionPortRequired,  SetupIssue? connectionFailure)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PairingReceipt() when $default != null:
return $default(_that.guid,_that.address,_that.device,_that.connection,_that.cancelled,_that.connectionPortRequired,_that.connectionFailure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String guid,  String address,  DeviceSnapshot? device,  DeviceConnectionReceipt? connection,  bool cancelled,  bool connectionPortRequired,  SetupIssue? connectionFailure)  $default,) {final _that = this;
switch (_that) {
case _PairingReceipt():
return $default(_that.guid,_that.address,_that.device,_that.connection,_that.cancelled,_that.connectionPortRequired,_that.connectionFailure);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String guid,  String address,  DeviceSnapshot? device,  DeviceConnectionReceipt? connection,  bool cancelled,  bool connectionPortRequired,  SetupIssue? connectionFailure)?  $default,) {final _that = this;
switch (_that) {
case _PairingReceipt() when $default != null:
return $default(_that.guid,_that.address,_that.device,_that.connection,_that.cancelled,_that.connectionPortRequired,_that.connectionFailure);case _:
  return null;

}
}

}

/// @nodoc


class _PairingReceipt extends PairingReceipt {
  const _PairingReceipt({required this.guid, required this.address, this.device, this.connection, this.cancelled = false, this.connectionPortRequired = false, this.connectionFailure}): super._();
  

@override final  String guid;
@override final  String address;
@override final  DeviceSnapshot? device;
@override final  DeviceConnectionReceipt? connection;
@override@JsonKey() final  bool cancelled;
@override@JsonKey() final  bool connectionPortRequired;
@override final  SetupIssue? connectionFailure;

/// Create a copy of PairingReceipt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PairingReceiptCopyWith<_PairingReceipt> get copyWith => __$PairingReceiptCopyWithImpl<_PairingReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PairingReceipt&&(identical(other.guid, guid) || other.guid == guid)&&(identical(other.address, address) || other.address == address)&&(identical(other.device, device) || other.device == device)&&(identical(other.connection, connection) || other.connection == connection)&&(identical(other.cancelled, cancelled) || other.cancelled == cancelled)&&(identical(other.connectionPortRequired, connectionPortRequired) || other.connectionPortRequired == connectionPortRequired)&&(identical(other.connectionFailure, connectionFailure) || other.connectionFailure == connectionFailure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,guid,address,device,connection,cancelled,connectionPortRequired,connectionFailure);
}

@override
String toString() {
    return 'PairingReceipt(guid: $guid, address: $address, device: $device, connection: $connection, cancelled: $cancelled, connectionPortRequired: $connectionPortRequired, connectionFailure: $connectionFailure)';
}


}

/// @nodoc
abstract mixin class _$PairingReceiptCopyWith<$Res> implements $PairingReceiptCopyWith<$Res> {
  factory _$PairingReceiptCopyWith(_PairingReceipt value, $Res Function(_PairingReceipt) _then) = __$PairingReceiptCopyWithImpl;
@override @useResult
$Res call({
 String guid, String address, DeviceSnapshot? device, DeviceConnectionReceipt? connection, bool cancelled, bool connectionPortRequired, SetupIssue? connectionFailure
});


@override $DeviceSnapshotCopyWith<$Res>? get device;@override $DeviceConnectionReceiptCopyWith<$Res>? get connection;@override $SetupIssueCopyWith<$Res>? get connectionFailure;

}
/// @nodoc
class __$PairingReceiptCopyWithImpl<$Res>
    implements _$PairingReceiptCopyWith<$Res> {
  __$PairingReceiptCopyWithImpl(this._self, this._then);

  final _PairingReceipt _self;
  final $Res Function(_PairingReceipt) _then;

/// Create a copy of PairingReceipt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? guid = null,Object? address = null,Object? device = freezed,Object? connection = freezed,Object? cancelled = null,Object? connectionPortRequired = null,Object? connectionFailure = freezed,}) {
  return _then(_PairingReceipt(
guid: null == guid ? _self.guid : guid // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,device: freezed == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as DeviceSnapshot?,connection: freezed == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as DeviceConnectionReceipt?,cancelled: null == cancelled ? _self.cancelled : cancelled // ignore: cast_nullable_to_non_nullable
as bool,connectionPortRequired: null == connectionPortRequired ? _self.connectionPortRequired : connectionPortRequired // ignore: cast_nullable_to_non_nullable
as bool,connectionFailure: freezed == connectionFailure ? _self.connectionFailure : connectionFailure // ignore: cast_nullable_to_non_nullable
as SetupIssue?,
  ));
}

/// Create a copy of PairingReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceSnapshotCopyWith<$Res>? get device {
    if (_self.device == null) {
    return null;
  }

  return $DeviceSnapshotCopyWith<$Res>(_self.device!, (value) {
    return _then(_self.copyWith(device: value));
  });
}/// Create a copy of PairingReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceConnectionReceiptCopyWith<$Res>? get connection {
    if (_self.connection == null) {
    return null;
  }

  return $DeviceConnectionReceiptCopyWith<$Res>(_self.connection!, (value) {
    return _then(_self.copyWith(connection: value));
  });
}/// Create a copy of PairingReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SetupIssueCopyWith<$Res>? get connectionFailure {
    if (_self.connectionFailure == null) {
    return null;
  }

  return $SetupIssueCopyWith<$Res>(_self.connectionFailure!, (value) {
    return _then(_self.copyWith(connectionFailure: value));
  });
}
}

/// @nodoc
mixin _$WirelessReceipt {

 String get deviceId; String get address; int get port; DeviceConnectionReceipt? get connection;
/// Create a copy of WirelessReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WirelessReceiptCopyWith<WirelessReceipt> get copyWith => _$WirelessReceiptCopyWithImpl<WirelessReceipt>(this as WirelessReceipt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WirelessReceipt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WirelessReceipt&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.address, _this.address) || other.address == _this.address)&&(identical(other.port, _this.port) || other.port == _this.port)&&(identical(other.connection, _this.connection) || other.connection == _this.connection));
}


@override
int get hashCode {
  final _this = this as WirelessReceipt;
  return Object.hash(runtimeType,_this.deviceId,_this.address,_this.port,_this.connection);
}

@override
String toString() {
  final _this = this as WirelessReceipt;
  return 'WirelessReceipt(deviceId: ${_this.deviceId}, address: ${_this.address}, port: ${_this.port}, connection: ${_this.connection})';
}


}

/// @nodoc
abstract mixin class $WirelessReceiptCopyWith<$Res>  {
  factory $WirelessReceiptCopyWith(WirelessReceipt value, $Res Function(WirelessReceipt) _then) = _$WirelessReceiptCopyWithImpl;
@useResult
$Res call({
 String deviceId, String address, int port, DeviceConnectionReceipt? connection
});


$DeviceConnectionReceiptCopyWith<$Res>? get connection;

}
/// @nodoc
class _$WirelessReceiptCopyWithImpl<$Res>
    implements $WirelessReceiptCopyWith<$Res> {
  _$WirelessReceiptCopyWithImpl(this._self, this._then);

  final WirelessReceipt _self;
  final $Res Function(WirelessReceipt) _then;

/// Create a copy of WirelessReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? address = null,Object? port = null,Object? connection = freezed,}) {
  return _then(WirelessReceipt(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,connection: freezed == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as DeviceConnectionReceipt?,
  ));
}
/// Create a copy of WirelessReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceConnectionReceiptCopyWith<$Res>? get connection {
    if (_self.connection == null) {
    return null;
  }

  return $DeviceConnectionReceiptCopyWith<$Res>(_self.connection!, (value) {
    return _then(_self.copyWith(connection: value));
  });
}
}


/// Adds pattern-matching-related methods to [WirelessReceipt].
extension WirelessReceiptPatterns on WirelessReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WirelessReceipt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WirelessReceipt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WirelessReceipt value)  $default,){
final _that = this;
switch (_that) {
case _WirelessReceipt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WirelessReceipt value)?  $default,){
final _that = this;
switch (_that) {
case _WirelessReceipt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  String address,  int port,  DeviceConnectionReceipt? connection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WirelessReceipt() when $default != null:
return $default(_that.deviceId,_that.address,_that.port,_that.connection);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  String address,  int port,  DeviceConnectionReceipt? connection)  $default,) {final _that = this;
switch (_that) {
case _WirelessReceipt():
return $default(_that.deviceId,_that.address,_that.port,_that.connection);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  String address,  int port,  DeviceConnectionReceipt? connection)?  $default,) {final _that = this;
switch (_that) {
case _WirelessReceipt() when $default != null:
return $default(_that.deviceId,_that.address,_that.port,_that.connection);case _:
  return null;

}
}

}

/// @nodoc


class _WirelessReceipt extends WirelessReceipt {
  const _WirelessReceipt({required this.deviceId, required this.address, required this.port, this.connection}): super._();
  

@override final  String deviceId;
@override final  String address;
@override final  int port;
@override final  DeviceConnectionReceipt? connection;

/// Create a copy of WirelessReceipt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WirelessReceiptCopyWith<_WirelessReceipt> get copyWith => __$WirelessReceiptCopyWithImpl<_WirelessReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WirelessReceipt&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.address, address) || other.address == address)&&(identical(other.port, port) || other.port == port)&&(identical(other.connection, connection) || other.connection == connection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,address,port,connection);
}

@override
String toString() {
    return 'WirelessReceipt(deviceId: $deviceId, address: $address, port: $port, connection: $connection)';
}


}

/// @nodoc
abstract mixin class _$WirelessReceiptCopyWith<$Res> implements $WirelessReceiptCopyWith<$Res> {
  factory _$WirelessReceiptCopyWith(_WirelessReceipt value, $Res Function(_WirelessReceipt) _then) = __$WirelessReceiptCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, String address, int port, DeviceConnectionReceipt? connection
});


@override $DeviceConnectionReceiptCopyWith<$Res>? get connection;

}
/// @nodoc
class __$WirelessReceiptCopyWithImpl<$Res>
    implements _$WirelessReceiptCopyWith<$Res> {
  __$WirelessReceiptCopyWithImpl(this._self, this._then);

  final _WirelessReceipt _self;
  final $Res Function(_WirelessReceipt) _then;

/// Create a copy of WirelessReceipt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? address = null,Object? port = null,Object? connection = freezed,}) {
  return _then(_WirelessReceipt(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,connection: freezed == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as DeviceConnectionReceipt?,
  ));
}

/// Create a copy of WirelessReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceConnectionReceiptCopyWith<$Res>? get connection {
    if (_self.connection == null) {
    return null;
  }

  return $DeviceConnectionReceiptCopyWith<$Res>(_self.connection!, (value) {
    return _then(_self.copyWith(connection: value));
  });
}
}

/// @nodoc
mixin _$SetupIssue {

 String get code; String get message;
/// Create a copy of SetupIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetupIssueCopyWith<SetupIssue> get copyWith => _$SetupIssueCopyWithImpl<SetupIssue>(this as SetupIssue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SetupIssue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetupIssue&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as SetupIssue;
  return Object.hash(runtimeType,_this.code,_this.message);
}

@override
String toString() {
  final _this = this as SetupIssue;
  return 'SetupIssue(code: ${_this.code}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $SetupIssueCopyWith<$Res>  {
  factory $SetupIssueCopyWith(SetupIssue value, $Res Function(SetupIssue) _then) = _$SetupIssueCopyWithImpl;
@useResult
$Res call({
 String code, String message
});




}
/// @nodoc
class _$SetupIssueCopyWithImpl<$Res>
    implements $SetupIssueCopyWith<$Res> {
  _$SetupIssueCopyWithImpl(this._self, this._then);

  final SetupIssue _self;
  final $Res Function(SetupIssue) _then;

/// Create a copy of SetupIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? message = null,}) {
  return _then(SetupIssue(
null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SetupIssue].
extension SetupIssuePatterns on SetupIssue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SetupIssue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SetupIssue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SetupIssue value)  $default,){
final _that = this;
switch (_that) {
case _SetupIssue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SetupIssue value)?  $default,){
final _that = this;
switch (_that) {
case _SetupIssue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String code,  String message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SetupIssue() when $default != null:
return $default(_that.code,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String code,  String message)  $default,) {final _that = this;
switch (_that) {
case _SetupIssue():
return $default(_that.code,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String code,  String message)?  $default,) {final _that = this;
switch (_that) {
case _SetupIssue() when $default != null:
return $default(_that.code,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _SetupIssue implements SetupIssue {
  const _SetupIssue(this.code, this.message);
  

@override final  String code;
@override final  String message;

/// Create a copy of SetupIssue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SetupIssueCopyWith<_SetupIssue> get copyWith => __$SetupIssueCopyWithImpl<_SetupIssue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SetupIssue&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,message);
}

@override
String toString() {
    return 'SetupIssue(code: $code, message: $message)';
}


}

/// @nodoc
abstract mixin class _$SetupIssueCopyWith<$Res> implements $SetupIssueCopyWith<$Res> {
  factory _$SetupIssueCopyWith(_SetupIssue value, $Res Function(_SetupIssue) _then) = __$SetupIssueCopyWithImpl;
@override @useResult
$Res call({
 String code, String message
});




}
/// @nodoc
class __$SetupIssueCopyWithImpl<$Res>
    implements _$SetupIssueCopyWith<$Res> {
  __$SetupIssueCopyWithImpl(this._self, this._then);

  final _SetupIssue _self;
  final $Res Function(_SetupIssue) _then;

/// Create a copy of SetupIssue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,}) {
  return _then(_SetupIssue(
null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$UsbSetupResult {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbSetupResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'UsbSetupResult()';
}


}

/// @nodoc
class $UsbSetupResultCopyWith<$Res>  {
$UsbSetupResultCopyWith(UsbSetupResult _, $Res Function(UsbSetupResult) __);
}


/// Adds pattern-matching-related methods to [UsbSetupResult].
extension UsbSetupResultPatterns on UsbSetupResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UsbSelectionRequired value)?  selectionRequired,TResult Function( UsbConnected value)?  connected,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UsbSelectionRequired() when selectionRequired != null:
return selectionRequired(_that);case UsbConnected() when connected != null:
return connected(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UsbSelectionRequired value)  selectionRequired,required TResult Function( UsbConnected value)  connected,}){
final _that = this;
switch (_that) {
case UsbSelectionRequired():
return selectionRequired(_that);case UsbConnected():
return connected(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UsbSelectionRequired value)?  selectionRequired,TResult? Function( UsbConnected value)?  connected,}){
final _that = this;
switch (_that) {
case UsbSelectionRequired() when selectionRequired != null:
return selectionRequired(_that);case UsbConnected() when connected != null:
return connected(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<UsbDeviceChoice> devices,  String? message)?  selectionRequired,TResult Function( DeviceConnectionReceipt receipt)?  connected,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UsbSelectionRequired() when selectionRequired != null:
return selectionRequired(_that.devices,_that.message);case UsbConnected() when connected != null:
return connected(_that.receipt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<UsbDeviceChoice> devices,  String? message)  selectionRequired,required TResult Function( DeviceConnectionReceipt receipt)  connected,}) {final _that = this;
switch (_that) {
case UsbSelectionRequired():
return selectionRequired(_that.devices,_that.message);case UsbConnected():
return connected(_that.receipt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<UsbDeviceChoice> devices,  String? message)?  selectionRequired,TResult? Function( DeviceConnectionReceipt receipt)?  connected,}) {final _that = this;
switch (_that) {
case UsbSelectionRequired() when selectionRequired != null:
return selectionRequired(_that.devices,_that.message);case UsbConnected() when connected != null:
return connected(_that.receipt);case _:
  return null;

}
}

}

/// @nodoc


class UsbSelectionRequired extends UsbSetupResult {
  const UsbSelectionRequired( List<UsbDeviceChoice> devices, {this.message}): _devices = devices,super._();
  

 final  List<UsbDeviceChoice> _devices;
 List<UsbDeviceChoice> get devices {
  if (_devices is EqualUnmodifiableListView) return _devices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_devices);
}

 final  String? message;

/// Create a copy of UsbSetupResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsbSelectionRequiredCopyWith<UsbSelectionRequired> get copyWith => _$UsbSelectionRequiredCopyWithImpl<UsbSelectionRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbSelectionRequired&&const DeepCollectionEquality().equals(other.devices, _devices)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_devices),message);
}

@override
String toString() {
    return 'UsbSetupResult.selectionRequired(devices: $devices, message: $message)';
}


}

/// @nodoc
abstract mixin class $UsbSelectionRequiredCopyWith<$Res> implements $UsbSetupResultCopyWith<$Res> {
  factory $UsbSelectionRequiredCopyWith(UsbSelectionRequired value, $Res Function(UsbSelectionRequired) _then) = _$UsbSelectionRequiredCopyWithImpl;
@useResult
$Res call({
 List<UsbDeviceChoice> devices, String? message
});




}
/// @nodoc
class _$UsbSelectionRequiredCopyWithImpl<$Res>
    implements $UsbSelectionRequiredCopyWith<$Res> {
  _$UsbSelectionRequiredCopyWithImpl(this._self, this._then);

  final UsbSelectionRequired _self;
  final $Res Function(UsbSelectionRequired) _then;

/// Create a copy of UsbSetupResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? devices = null,Object? message = freezed,}) {
  return _then(UsbSelectionRequired(
null == devices ? _self._devices : devices // ignore: cast_nullable_to_non_nullable
as List<UsbDeviceChoice>,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class UsbConnected extends UsbSetupResult {
  const UsbConnected(this.receipt): super._();
  

 final  DeviceConnectionReceipt receipt;

/// Create a copy of UsbSetupResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsbConnectedCopyWith<UsbConnected> get copyWith => _$UsbConnectedCopyWithImpl<UsbConnected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbConnected&&(identical(other.receipt, receipt) || other.receipt == receipt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receipt);
}

@override
String toString() {
    return 'UsbSetupResult.connected(receipt: $receipt)';
}


}

/// @nodoc
abstract mixin class $UsbConnectedCopyWith<$Res> implements $UsbSetupResultCopyWith<$Res> {
  factory $UsbConnectedCopyWith(UsbConnected value, $Res Function(UsbConnected) _then) = _$UsbConnectedCopyWithImpl;
@useResult
$Res call({
 DeviceConnectionReceipt receipt
});


$DeviceConnectionReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$UsbConnectedCopyWithImpl<$Res>
    implements $UsbConnectedCopyWith<$Res> {
  _$UsbConnectedCopyWithImpl(this._self, this._then);

  final UsbConnected _self;
  final $Res Function(UsbConnected) _then;

/// Create a copy of UsbSetupResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? receipt = null,}) {
  return _then(UsbConnected(
null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as DeviceConnectionReceipt,
  ));
}

/// Create a copy of UsbSetupResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceConnectionReceiptCopyWith<$Res> get receipt {
  
  return $DeviceConnectionReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}

/// @nodoc
mixin _$UsbDeviceChoice {

 String get serial; String get state; String? get usbPath; String? get model; int? get transportId; String? get usbDeviceId; String? get name; DeviceSnapshot? get device;
/// Create a copy of UsbDeviceChoice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsbDeviceChoiceCopyWith<UsbDeviceChoice> get copyWith => _$UsbDeviceChoiceCopyWithImpl<UsbDeviceChoice>(this as UsbDeviceChoice, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UsbDeviceChoice;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbDeviceChoice&&(identical(other.serial, _this.serial) || other.serial == _this.serial)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.usbPath, _this.usbPath) || other.usbPath == _this.usbPath)&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.transportId, _this.transportId) || other.transportId == _this.transportId)&&(identical(other.usbDeviceId, _this.usbDeviceId) || other.usbDeviceId == _this.usbDeviceId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.device, _this.device) || other.device == _this.device));
}


@override
int get hashCode {
  final _this = this as UsbDeviceChoice;
  return Object.hash(runtimeType,_this.serial,_this.state,_this.usbPath,_this.model,_this.transportId,_this.usbDeviceId,_this.name,_this.device);
}

@override
String toString() {
  final _this = this as UsbDeviceChoice;
  return 'UsbDeviceChoice(serial: ${_this.serial}, state: ${_this.state}, usbPath: ${_this.usbPath}, model: ${_this.model}, transportId: ${_this.transportId}, usbDeviceId: ${_this.usbDeviceId}, name: ${_this.name}, device: ${_this.device})';
}


}

/// @nodoc
abstract mixin class $UsbDeviceChoiceCopyWith<$Res>  {
  factory $UsbDeviceChoiceCopyWith(UsbDeviceChoice value, $Res Function(UsbDeviceChoice) _then) = _$UsbDeviceChoiceCopyWithImpl;
@useResult
$Res call({
 String serial, String state, String? usbPath, String? model, int? transportId, String? usbDeviceId, String? name, DeviceSnapshot? device
});


$DeviceSnapshotCopyWith<$Res>? get device;

}
/// @nodoc
class _$UsbDeviceChoiceCopyWithImpl<$Res>
    implements $UsbDeviceChoiceCopyWith<$Res> {
  _$UsbDeviceChoiceCopyWithImpl(this._self, this._then);

  final UsbDeviceChoice _self;
  final $Res Function(UsbDeviceChoice) _then;

/// Create a copy of UsbDeviceChoice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? serial = null,Object? state = null,Object? usbPath = freezed,Object? model = freezed,Object? transportId = freezed,Object? usbDeviceId = freezed,Object? name = freezed,Object? device = freezed,}) {
  return _then(UsbDeviceChoice(
serial: null == serial ? _self.serial : serial // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,usbPath: freezed == usbPath ? _self.usbPath : usbPath // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,transportId: freezed == transportId ? _self.transportId : transportId // ignore: cast_nullable_to_non_nullable
as int?,usbDeviceId: freezed == usbDeviceId ? _self.usbDeviceId : usbDeviceId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,device: freezed == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as DeviceSnapshot?,
  ));
}
/// Create a copy of UsbDeviceChoice
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceSnapshotCopyWith<$Res>? get device {
    if (_self.device == null) {
    return null;
  }

  return $DeviceSnapshotCopyWith<$Res>(_self.device!, (value) {
    return _then(_self.copyWith(device: value));
  });
}
}


/// Adds pattern-matching-related methods to [UsbDeviceChoice].
extension UsbDeviceChoicePatterns on UsbDeviceChoice {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UsbDeviceChoice value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UsbDeviceChoice() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UsbDeviceChoice value)  $default,){
final _that = this;
switch (_that) {
case _UsbDeviceChoice():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UsbDeviceChoice value)?  $default,){
final _that = this;
switch (_that) {
case _UsbDeviceChoice() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String serial,  String state,  String? usbPath,  String? model,  int? transportId,  String? usbDeviceId,  String? name,  DeviceSnapshot? device)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UsbDeviceChoice() when $default != null:
return $default(_that.serial,_that.state,_that.usbPath,_that.model,_that.transportId,_that.usbDeviceId,_that.name,_that.device);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String serial,  String state,  String? usbPath,  String? model,  int? transportId,  String? usbDeviceId,  String? name,  DeviceSnapshot? device)  $default,) {final _that = this;
switch (_that) {
case _UsbDeviceChoice():
return $default(_that.serial,_that.state,_that.usbPath,_that.model,_that.transportId,_that.usbDeviceId,_that.name,_that.device);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String serial,  String state,  String? usbPath,  String? model,  int? transportId,  String? usbDeviceId,  String? name,  DeviceSnapshot? device)?  $default,) {final _that = this;
switch (_that) {
case _UsbDeviceChoice() when $default != null:
return $default(_that.serial,_that.state,_that.usbPath,_that.model,_that.transportId,_that.usbDeviceId,_that.name,_that.device);case _:
  return null;

}
}

}

/// @nodoc


class _UsbDeviceChoice implements UsbDeviceChoice {
  const _UsbDeviceChoice({this.serial = '', this.state = '', this.usbPath, this.model, this.transportId, this.usbDeviceId, this.name, this.device});
  

@override@JsonKey() final  String serial;
@override@JsonKey() final  String state;
@override final  String? usbPath;
@override final  String? model;
@override final  int? transportId;
@override final  String? usbDeviceId;
@override final  String? name;
@override final  DeviceSnapshot? device;

/// Create a copy of UsbDeviceChoice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UsbDeviceChoiceCopyWith<_UsbDeviceChoice> get copyWith => __$UsbDeviceChoiceCopyWithImpl<_UsbDeviceChoice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UsbDeviceChoice&&(identical(other.serial, serial) || other.serial == serial)&&(identical(other.state, state) || other.state == state)&&(identical(other.usbPath, usbPath) || other.usbPath == usbPath)&&(identical(other.model, model) || other.model == model)&&(identical(other.transportId, transportId) || other.transportId == transportId)&&(identical(other.usbDeviceId, usbDeviceId) || other.usbDeviceId == usbDeviceId)&&(identical(other.name, name) || other.name == name)&&(identical(other.device, device) || other.device == device));
}


@override
int get hashCode {
    return Object.hash(runtimeType,serial,state,usbPath,model,transportId,usbDeviceId,name,device);
}

@override
String toString() {
    return 'UsbDeviceChoice(serial: $serial, state: $state, usbPath: $usbPath, model: $model, transportId: $transportId, usbDeviceId: $usbDeviceId, name: $name, device: $device)';
}


}

/// @nodoc
abstract mixin class _$UsbDeviceChoiceCopyWith<$Res> implements $UsbDeviceChoiceCopyWith<$Res> {
  factory _$UsbDeviceChoiceCopyWith(_UsbDeviceChoice value, $Res Function(_UsbDeviceChoice) _then) = __$UsbDeviceChoiceCopyWithImpl;
@override @useResult
$Res call({
 String serial, String state, String? usbPath, String? model, int? transportId, String? usbDeviceId, String? name, DeviceSnapshot? device
});


@override $DeviceSnapshotCopyWith<$Res>? get device;

}
/// @nodoc
class __$UsbDeviceChoiceCopyWithImpl<$Res>
    implements _$UsbDeviceChoiceCopyWith<$Res> {
  __$UsbDeviceChoiceCopyWithImpl(this._self, this._then);

  final _UsbDeviceChoice _self;
  final $Res Function(_UsbDeviceChoice) _then;

/// Create a copy of UsbDeviceChoice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? serial = null,Object? state = null,Object? usbPath = freezed,Object? model = freezed,Object? transportId = freezed,Object? usbDeviceId = freezed,Object? name = freezed,Object? device = freezed,}) {
  return _then(_UsbDeviceChoice(
serial: null == serial ? _self.serial : serial // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,usbPath: freezed == usbPath ? _self.usbPath : usbPath // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,transportId: freezed == transportId ? _self.transportId : transportId // ignore: cast_nullable_to_non_nullable
as int?,usbDeviceId: freezed == usbDeviceId ? _self.usbDeviceId : usbDeviceId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,device: freezed == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as DeviceSnapshot?,
  ));
}

/// Create a copy of UsbDeviceChoice
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceSnapshotCopyWith<$Res>? get device {
    if (_self.device == null) {
    return null;
  }

  return $DeviceSnapshotCopyWith<$Res>(_self.device!, (value) {
    return _then(_self.copyWith(device: value));
  });
}
}

// dart format on
