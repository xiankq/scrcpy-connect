// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_connection_control.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DeviceEndpoint {

 String get address; int get port; DeviceTransport get transport;
/// Create a copy of DeviceEndpoint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceEndpointCopyWith<DeviceEndpoint> get copyWith => _$DeviceEndpointCopyWithImpl<DeviceEndpoint>(this as DeviceEndpoint, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceEndpoint;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceEndpoint&&(identical(other.address, _this.address) || other.address == _this.address)&&(identical(other.port, _this.port) || other.port == _this.port)&&(identical(other.transport, _this.transport) || other.transport == _this.transport));
}


@override
int get hashCode {
  final _this = this as DeviceEndpoint;
  return Object.hash(runtimeType,_this.address,_this.port,_this.transport);
}

@override
String toString() {
  final _this = this as DeviceEndpoint;
  return 'DeviceEndpoint(address: ${_this.address}, port: ${_this.port}, transport: ${_this.transport})';
}


}

/// @nodoc
abstract mixin class $DeviceEndpointCopyWith<$Res>  {
  factory $DeviceEndpointCopyWith(DeviceEndpoint value, $Res Function(DeviceEndpoint) _then) = _$DeviceEndpointCopyWithImpl;
@useResult
$Res call({
 String address, int port, DeviceTransport transport
});




}
/// @nodoc
class _$DeviceEndpointCopyWithImpl<$Res>
    implements $DeviceEndpointCopyWith<$Res> {
  _$DeviceEndpointCopyWithImpl(this._self, this._then);

  final DeviceEndpoint _self;
  final $Res Function(DeviceEndpoint) _then;

/// Create a copy of DeviceEndpoint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? address = null,Object? port = null,Object? transport = null,}) {
  return _then(DeviceEndpoint(
address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as DeviceTransport,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceEndpoint].
extension DeviceEndpointPatterns on DeviceEndpoint {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceEndpoint value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceEndpoint() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceEndpoint value)  $default,){
final _that = this;
switch (_that) {
case _DeviceEndpoint():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceEndpoint value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceEndpoint() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String address,  int port,  DeviceTransport transport)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceEndpoint() when $default != null:
return $default(_that.address,_that.port,_that.transport);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String address,  int port,  DeviceTransport transport)  $default,) {final _that = this;
switch (_that) {
case _DeviceEndpoint():
return $default(_that.address,_that.port,_that.transport);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String address,  int port,  DeviceTransport transport)?  $default,) {final _that = this;
switch (_that) {
case _DeviceEndpoint() when $default != null:
return $default(_that.address,_that.port,_that.transport);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceEndpoint implements DeviceEndpoint {
  const _DeviceEndpoint({required this.address, required this.port, this.transport = DeviceTransport.tcp});
  

@override final  String address;
@override final  int port;
@override@JsonKey() final  DeviceTransport transport;

/// Create a copy of DeviceEndpoint
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceEndpointCopyWith<_DeviceEndpoint> get copyWith => __$DeviceEndpointCopyWithImpl<_DeviceEndpoint>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceEndpoint&&(identical(other.address, address) || other.address == address)&&(identical(other.port, port) || other.port == port)&&(identical(other.transport, transport) || other.transport == transport));
}


@override
int get hashCode {
    return Object.hash(runtimeType,address,port,transport);
}

@override
String toString() {
    return 'DeviceEndpoint(address: $address, port: $port, transport: $transport)';
}


}

/// @nodoc
abstract mixin class _$DeviceEndpointCopyWith<$Res> implements $DeviceEndpointCopyWith<$Res> {
  factory _$DeviceEndpointCopyWith(_DeviceEndpoint value, $Res Function(_DeviceEndpoint) _then) = __$DeviceEndpointCopyWithImpl;
@override @useResult
$Res call({
 String address, int port, DeviceTransport transport
});




}
/// @nodoc
class __$DeviceEndpointCopyWithImpl<$Res>
    implements _$DeviceEndpointCopyWith<$Res> {
  __$DeviceEndpointCopyWithImpl(this._self, this._then);

  final _DeviceEndpoint _self;
  final $Res Function(_DeviceEndpoint) _then;

/// Create a copy of DeviceEndpoint
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? address = null,Object? port = null,Object? transport = null,}) {
  return _then(_DeviceEndpoint(
address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as DeviceTransport,
  ));
}


}

/// @nodoc
mixin _$DeviceConnectionReceipt {

 DeviceSnapshot get device; bool? get adbBurstActive;
/// Create a copy of DeviceConnectionReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceConnectionReceiptCopyWith<DeviceConnectionReceipt> get copyWith => _$DeviceConnectionReceiptCopyWithImpl<DeviceConnectionReceipt>(this as DeviceConnectionReceipt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceConnectionReceipt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceConnectionReceipt&&(identical(other.device, _this.device) || other.device == _this.device)&&(identical(other.adbBurstActive, _this.adbBurstActive) || other.adbBurstActive == _this.adbBurstActive));
}


@override
int get hashCode {
  final _this = this as DeviceConnectionReceipt;
  return Object.hash(runtimeType,_this.device,_this.adbBurstActive);
}

@override
String toString() {
  final _this = this as DeviceConnectionReceipt;
  return 'DeviceConnectionReceipt(device: ${_this.device}, adbBurstActive: ${_this.adbBurstActive})';
}


}

/// @nodoc
abstract mixin class $DeviceConnectionReceiptCopyWith<$Res>  {
  factory $DeviceConnectionReceiptCopyWith(DeviceConnectionReceipt value, $Res Function(DeviceConnectionReceipt) _then) = _$DeviceConnectionReceiptCopyWithImpl;
@useResult
$Res call({
 DeviceSnapshot device, bool? adbBurstActive
});


$DeviceSnapshotCopyWith<$Res> get device;

}
/// @nodoc
class _$DeviceConnectionReceiptCopyWithImpl<$Res>
    implements $DeviceConnectionReceiptCopyWith<$Res> {
  _$DeviceConnectionReceiptCopyWithImpl(this._self, this._then);

  final DeviceConnectionReceipt _self;
  final $Res Function(DeviceConnectionReceipt) _then;

/// Create a copy of DeviceConnectionReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? device = null,Object? adbBurstActive = freezed,}) {
  return _then(DeviceConnectionReceipt(
device: null == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as DeviceSnapshot,adbBurstActive: freezed == adbBurstActive ? _self.adbBurstActive : adbBurstActive // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}
/// Create a copy of DeviceConnectionReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceSnapshotCopyWith<$Res> get device {
  
  return $DeviceSnapshotCopyWith<$Res>(_self.device, (value) {
    return _then(_self.copyWith(device: value));
  });
}
}


/// Adds pattern-matching-related methods to [DeviceConnectionReceipt].
extension DeviceConnectionReceiptPatterns on DeviceConnectionReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceConnectionReceipt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceConnectionReceipt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceConnectionReceipt value)  $default,){
final _that = this;
switch (_that) {
case _DeviceConnectionReceipt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceConnectionReceipt value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceConnectionReceipt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DeviceSnapshot device,  bool? adbBurstActive)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceConnectionReceipt() when $default != null:
return $default(_that.device,_that.adbBurstActive);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DeviceSnapshot device,  bool? adbBurstActive)  $default,) {final _that = this;
switch (_that) {
case _DeviceConnectionReceipt():
return $default(_that.device,_that.adbBurstActive);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DeviceSnapshot device,  bool? adbBurstActive)?  $default,) {final _that = this;
switch (_that) {
case _DeviceConnectionReceipt() when $default != null:
return $default(_that.device,_that.adbBurstActive);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceConnectionReceipt extends DeviceConnectionReceipt {
  const _DeviceConnectionReceipt({required this.device, this.adbBurstActive}): super._();
  

@override final  DeviceSnapshot device;
@override final  bool? adbBurstActive;

/// Create a copy of DeviceConnectionReceipt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceConnectionReceiptCopyWith<_DeviceConnectionReceipt> get copyWith => __$DeviceConnectionReceiptCopyWithImpl<_DeviceConnectionReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceConnectionReceipt&&(identical(other.device, device) || other.device == device)&&(identical(other.adbBurstActive, adbBurstActive) || other.adbBurstActive == adbBurstActive));
}


@override
int get hashCode {
    return Object.hash(runtimeType,device,adbBurstActive);
}

@override
String toString() {
    return 'DeviceConnectionReceipt(device: $device, adbBurstActive: $adbBurstActive)';
}


}

/// @nodoc
abstract mixin class _$DeviceConnectionReceiptCopyWith<$Res> implements $DeviceConnectionReceiptCopyWith<$Res> {
  factory _$DeviceConnectionReceiptCopyWith(_DeviceConnectionReceipt value, $Res Function(_DeviceConnectionReceipt) _then) = __$DeviceConnectionReceiptCopyWithImpl;
@override @useResult
$Res call({
 DeviceSnapshot device, bool? adbBurstActive
});


@override $DeviceSnapshotCopyWith<$Res> get device;

}
/// @nodoc
class __$DeviceConnectionReceiptCopyWithImpl<$Res>
    implements _$DeviceConnectionReceiptCopyWith<$Res> {
  __$DeviceConnectionReceiptCopyWithImpl(this._self, this._then);

  final _DeviceConnectionReceipt _self;
  final $Res Function(_DeviceConnectionReceipt) _then;

/// Create a copy of DeviceConnectionReceipt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? device = null,Object? adbBurstActive = freezed,}) {
  return _then(_DeviceConnectionReceipt(
device: null == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as DeviceSnapshot,adbBurstActive: freezed == adbBurstActive ? _self.adbBurstActive : adbBurstActive // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

/// Create a copy of DeviceConnectionReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceSnapshotCopyWith<$Res> get device {
  
  return $DeviceSnapshotCopyWith<$Res>(_self.device, (value) {
    return _then(_self.copyWith(device: value));
  });
}
}

// dart format on
