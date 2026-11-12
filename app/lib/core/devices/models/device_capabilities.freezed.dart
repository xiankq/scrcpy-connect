// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_capabilities.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DeviceCapability {

 DeviceFeature get feature; DeviceFeatureStatus get status; String get reason;
/// Create a copy of DeviceCapability
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceCapabilityCopyWith<DeviceCapability> get copyWith => _$DeviceCapabilityCopyWithImpl<DeviceCapability>(this as DeviceCapability, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceCapability;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceCapability&&(identical(other.feature, _this.feature) || other.feature == _this.feature)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}


@override
int get hashCode {
  final _this = this as DeviceCapability;
  return Object.hash(runtimeType,_this.feature,_this.status,_this.reason);
}

@override
String toString() {
  final _this = this as DeviceCapability;
  return 'DeviceCapability(feature: ${_this.feature}, status: ${_this.status}, reason: ${_this.reason})';
}


}

/// @nodoc
abstract mixin class $DeviceCapabilityCopyWith<$Res>  {
  factory $DeviceCapabilityCopyWith(DeviceCapability value, $Res Function(DeviceCapability) _then) = _$DeviceCapabilityCopyWithImpl;
@useResult
$Res call({
 DeviceFeature feature, DeviceFeatureStatus status, String reason
});




}
/// @nodoc
class _$DeviceCapabilityCopyWithImpl<$Res>
    implements $DeviceCapabilityCopyWith<$Res> {
  _$DeviceCapabilityCopyWithImpl(this._self, this._then);

  final DeviceCapability _self;
  final $Res Function(DeviceCapability) _then;

/// Create a copy of DeviceCapability
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? feature = null,Object? status = null,Object? reason = null,}) {
  return _then(DeviceCapability(
feature: null == feature ? _self.feature : feature // ignore: cast_nullable_to_non_nullable
as DeviceFeature,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceFeatureStatus,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceCapability].
extension DeviceCapabilityPatterns on DeviceCapability {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceCapability value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceCapability() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceCapability value)  $default,){
final _that = this;
switch (_that) {
case _DeviceCapability():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceCapability value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceCapability() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DeviceFeature feature,  DeviceFeatureStatus status,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceCapability() when $default != null:
return $default(_that.feature,_that.status,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DeviceFeature feature,  DeviceFeatureStatus status,  String reason)  $default,) {final _that = this;
switch (_that) {
case _DeviceCapability():
return $default(_that.feature,_that.status,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DeviceFeature feature,  DeviceFeatureStatus status,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _DeviceCapability() when $default != null:
return $default(_that.feature,_that.status,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceCapability implements DeviceCapability {
  const _DeviceCapability({required this.feature, required this.status, required this.reason});
  

@override final  DeviceFeature feature;
@override final  DeviceFeatureStatus status;
@override final  String reason;

/// Create a copy of DeviceCapability
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceCapabilityCopyWith<_DeviceCapability> get copyWith => __$DeviceCapabilityCopyWithImpl<_DeviceCapability>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceCapability&&(identical(other.feature, feature) || other.feature == feature)&&(identical(other.status, status) || other.status == status)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,feature,status,reason);
}

@override
String toString() {
    return 'DeviceCapability(feature: $feature, status: $status, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$DeviceCapabilityCopyWith<$Res> implements $DeviceCapabilityCopyWith<$Res> {
  factory _$DeviceCapabilityCopyWith(_DeviceCapability value, $Res Function(_DeviceCapability) _then) = __$DeviceCapabilityCopyWithImpl;
@override @useResult
$Res call({
 DeviceFeature feature, DeviceFeatureStatus status, String reason
});




}
/// @nodoc
class __$DeviceCapabilityCopyWithImpl<$Res>
    implements _$DeviceCapabilityCopyWith<$Res> {
  __$DeviceCapabilityCopyWithImpl(this._self, this._then);

  final _DeviceCapability _self;
  final $Res Function(_DeviceCapability) _then;

/// Create a copy of DeviceCapability
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? feature = null,Object? status = null,Object? reason = null,}) {
  return _then(_DeviceCapability(
feature: null == feature ? _self.feature : feature // ignore: cast_nullable_to_non_nullable
as DeviceFeature,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceFeatureStatus,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$DeviceCapabilities {

 String get deviceId; String? get connectionId; List<DeviceCapability> get capabilities; List<String> get features;
/// Create a copy of DeviceCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceCapabilitiesCopyWith<DeviceCapabilities> get copyWith => _$DeviceCapabilitiesCopyWithImpl<DeviceCapabilities>(this as DeviceCapabilities, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceCapabilities;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceCapabilities&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.connectionId, _this.connectionId) || other.connectionId == _this.connectionId)&&const DeepCollectionEquality().equals(other.capabilities, _this.capabilities)&&const DeepCollectionEquality().equals(other.features, _this.features));
}


@override
int get hashCode {
  final _this = this as DeviceCapabilities;
  return Object.hash(runtimeType,_this.deviceId,_this.connectionId,const DeepCollectionEquality().hash(_this.capabilities),const DeepCollectionEquality().hash(_this.features));
}

@override
String toString() {
  final _this = this as DeviceCapabilities;
  return 'DeviceCapabilities(deviceId: ${_this.deviceId}, connectionId: ${_this.connectionId}, capabilities: ${_this.capabilities}, features: ${_this.features})';
}


}

/// @nodoc
abstract mixin class $DeviceCapabilitiesCopyWith<$Res>  {
  factory $DeviceCapabilitiesCopyWith(DeviceCapabilities value, $Res Function(DeviceCapabilities) _then) = _$DeviceCapabilitiesCopyWithImpl;
@useResult
$Res call({
 String deviceId, String? connectionId, List<DeviceCapability> capabilities, List<String> features
});




}
/// @nodoc
class _$DeviceCapabilitiesCopyWithImpl<$Res>
    implements $DeviceCapabilitiesCopyWith<$Res> {
  _$DeviceCapabilitiesCopyWithImpl(this._self, this._then);

  final DeviceCapabilities _self;
  final $Res Function(DeviceCapabilities) _then;

/// Create a copy of DeviceCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? connectionId = freezed,Object? capabilities = null,Object? features = null,}) {
  return _then(DeviceCapabilities(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,connectionId: freezed == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String?,capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as List<DeviceCapability>,features: null == features ? _self.features : features // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceCapabilities].
extension DeviceCapabilitiesPatterns on DeviceCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _DeviceCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  String? connectionId,  List<DeviceCapability> capabilities,  List<String> features)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceCapabilities() when $default != null:
return $default(_that.deviceId,_that.connectionId,_that.capabilities,_that.features);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  String? connectionId,  List<DeviceCapability> capabilities,  List<String> features)  $default,) {final _that = this;
switch (_that) {
case _DeviceCapabilities():
return $default(_that.deviceId,_that.connectionId,_that.capabilities,_that.features);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  String? connectionId,  List<DeviceCapability> capabilities,  List<String> features)?  $default,) {final _that = this;
switch (_that) {
case _DeviceCapabilities() when $default != null:
return $default(_that.deviceId,_that.connectionId,_that.capabilities,_that.features);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceCapabilities implements DeviceCapabilities {
  const _DeviceCapabilities({required this.deviceId, this.connectionId,  List<DeviceCapability> capabilities = const [],  List<String> features = const []}): _capabilities = capabilities,_features = features;
  

@override final  String deviceId;
@override final  String? connectionId;
 final  List<DeviceCapability> _capabilities;
@override@JsonKey() List<DeviceCapability> get capabilities {
  if (_capabilities is EqualUnmodifiableListView) return _capabilities;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_capabilities);
}

 final  List<String> _features;
@override@JsonKey() List<String> get features {
  if (_features is EqualUnmodifiableListView) return _features;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_features);
}


/// Create a copy of DeviceCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceCapabilitiesCopyWith<_DeviceCapabilities> get copyWith => __$DeviceCapabilitiesCopyWithImpl<_DeviceCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceCapabilities&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId)&&const DeepCollectionEquality().equals(other.capabilities, _capabilities)&&const DeepCollectionEquality().equals(other.features, _features));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,connectionId,const DeepCollectionEquality().hash(_capabilities),const DeepCollectionEquality().hash(_features));
}

@override
String toString() {
    return 'DeviceCapabilities(deviceId: $deviceId, connectionId: $connectionId, capabilities: $capabilities, features: $features)';
}


}

/// @nodoc
abstract mixin class _$DeviceCapabilitiesCopyWith<$Res> implements $DeviceCapabilitiesCopyWith<$Res> {
  factory _$DeviceCapabilitiesCopyWith(_DeviceCapabilities value, $Res Function(_DeviceCapabilities) _then) = __$DeviceCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, String? connectionId, List<DeviceCapability> capabilities, List<String> features
});




}
/// @nodoc
class __$DeviceCapabilitiesCopyWithImpl<$Res>
    implements _$DeviceCapabilitiesCopyWith<$Res> {
  __$DeviceCapabilitiesCopyWithImpl(this._self, this._then);

  final _DeviceCapabilities _self;
  final $Res Function(_DeviceCapabilities) _then;

/// Create a copy of DeviceCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? connectionId = freezed,Object? capabilities = null,Object? features = null,}) {
  return _then(_DeviceCapabilities(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,connectionId: freezed == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String?,capabilities: null == capabilities ? _self._capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as List<DeviceCapability>,features: null == features ? _self._features : features // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc
mixin _$DeviceDiagnosis {

 DeviceSnapshot get device; bool get connected; String? get connectionId; bool? get usbBackendAvailable; List<String> get features; DeviceCapabilityObservation get identity; Map<String, DeviceCapabilityObservation> get observations; bool? get tcpReachable; String? get networkError; bool? get identityPresent; String? get identityError; bool get adbBurstRequested; String? get wirelessProperties; List<String> get notes;
/// Create a copy of DeviceDiagnosis
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceDiagnosisCopyWith<DeviceDiagnosis> get copyWith => _$DeviceDiagnosisCopyWithImpl<DeviceDiagnosis>(this as DeviceDiagnosis, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceDiagnosis;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceDiagnosis&&(identical(other.device, _this.device) || other.device == _this.device)&&(identical(other.connected, _this.connected) || other.connected == _this.connected)&&(identical(other.connectionId, _this.connectionId) || other.connectionId == _this.connectionId)&&(identical(other.usbBackendAvailable, _this.usbBackendAvailable) || other.usbBackendAvailable == _this.usbBackendAvailable)&&const DeepCollectionEquality().equals(other.features, _this.features)&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&const DeepCollectionEquality().equals(other.observations, _this.observations)&&(identical(other.tcpReachable, _this.tcpReachable) || other.tcpReachable == _this.tcpReachable)&&(identical(other.networkError, _this.networkError) || other.networkError == _this.networkError)&&(identical(other.identityPresent, _this.identityPresent) || other.identityPresent == _this.identityPresent)&&(identical(other.identityError, _this.identityError) || other.identityError == _this.identityError)&&(identical(other.adbBurstRequested, _this.adbBurstRequested) || other.adbBurstRequested == _this.adbBurstRequested)&&(identical(other.wirelessProperties, _this.wirelessProperties) || other.wirelessProperties == _this.wirelessProperties)&&const DeepCollectionEquality().equals(other.notes, _this.notes));
}


@override
int get hashCode {
  final _this = this as DeviceDiagnosis;
  return Object.hash(runtimeType,_this.device,_this.connected,_this.connectionId,_this.usbBackendAvailable,const DeepCollectionEquality().hash(_this.features),_this.identity,const DeepCollectionEquality().hash(_this.observations),_this.tcpReachable,_this.networkError,_this.identityPresent,_this.identityError,_this.adbBurstRequested,_this.wirelessProperties,const DeepCollectionEquality().hash(_this.notes));
}

@override
String toString() {
  final _this = this as DeviceDiagnosis;
  return 'DeviceDiagnosis(device: ${_this.device}, connected: ${_this.connected}, connectionId: ${_this.connectionId}, usbBackendAvailable: ${_this.usbBackendAvailable}, features: ${_this.features}, identity: ${_this.identity}, observations: ${_this.observations}, tcpReachable: ${_this.tcpReachable}, networkError: ${_this.networkError}, identityPresent: ${_this.identityPresent}, identityError: ${_this.identityError}, adbBurstRequested: ${_this.adbBurstRequested}, wirelessProperties: ${_this.wirelessProperties}, notes: ${_this.notes})';
}


}

/// @nodoc
abstract mixin class $DeviceDiagnosisCopyWith<$Res>  {
  factory $DeviceDiagnosisCopyWith(DeviceDiagnosis value, $Res Function(DeviceDiagnosis) _then) = _$DeviceDiagnosisCopyWithImpl;
@useResult
$Res call({
 DeviceSnapshot device, bool connected, String? connectionId, bool? usbBackendAvailable, List<String> features, DeviceCapabilityObservation identity, Map<String, DeviceCapabilityObservation> observations, bool? tcpReachable, String? networkError, bool? identityPresent, String? identityError, bool adbBurstRequested, String? wirelessProperties, List<String> notes
});


$DeviceSnapshotCopyWith<$Res> get device;

}
/// @nodoc
class _$DeviceDiagnosisCopyWithImpl<$Res>
    implements $DeviceDiagnosisCopyWith<$Res> {
  _$DeviceDiagnosisCopyWithImpl(this._self, this._then);

  final DeviceDiagnosis _self;
  final $Res Function(DeviceDiagnosis) _then;

/// Create a copy of DeviceDiagnosis
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? device = null,Object? connected = null,Object? connectionId = freezed,Object? usbBackendAvailable = freezed,Object? features = null,Object? identity = null,Object? observations = null,Object? tcpReachable = freezed,Object? networkError = freezed,Object? identityPresent = freezed,Object? identityError = freezed,Object? adbBurstRequested = null,Object? wirelessProperties = freezed,Object? notes = null,}) {
  return _then(DeviceDiagnosis(
device: null == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as DeviceSnapshot,connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,connectionId: freezed == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String?,usbBackendAvailable: freezed == usbBackendAvailable ? _self.usbBackendAvailable : usbBackendAvailable // ignore: cast_nullable_to_non_nullable
as bool?,features: null == features ? _self.features : features // ignore: cast_nullable_to_non_nullable
as List<String>,identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as DeviceCapabilityObservation,observations: null == observations ? _self.observations : observations // ignore: cast_nullable_to_non_nullable
as Map<String, DeviceCapabilityObservation>,tcpReachable: freezed == tcpReachable ? _self.tcpReachable : tcpReachable // ignore: cast_nullable_to_non_nullable
as bool?,networkError: freezed == networkError ? _self.networkError : networkError // ignore: cast_nullable_to_non_nullable
as String?,identityPresent: freezed == identityPresent ? _self.identityPresent : identityPresent // ignore: cast_nullable_to_non_nullable
as bool?,identityError: freezed == identityError ? _self.identityError : identityError // ignore: cast_nullable_to_non_nullable
as String?,adbBurstRequested: null == adbBurstRequested ? _self.adbBurstRequested : adbBurstRequested // ignore: cast_nullable_to_non_nullable
as bool,wirelessProperties: freezed == wirelessProperties ? _self.wirelessProperties : wirelessProperties // ignore: cast_nullable_to_non_nullable
as String?,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}
/// Create a copy of DeviceDiagnosis
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceSnapshotCopyWith<$Res> get device {
  
  return $DeviceSnapshotCopyWith<$Res>(_self.device, (value) {
    return _then(_self.copyWith(device: value));
  });
}
}


/// Adds pattern-matching-related methods to [DeviceDiagnosis].
extension DeviceDiagnosisPatterns on DeviceDiagnosis {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceDiagnosis value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceDiagnosis() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceDiagnosis value)  $default,){
final _that = this;
switch (_that) {
case _DeviceDiagnosis():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceDiagnosis value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceDiagnosis() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DeviceSnapshot device,  bool connected,  String? connectionId,  bool? usbBackendAvailable,  List<String> features,  DeviceCapabilityObservation identity,  Map<String, DeviceCapabilityObservation> observations,  bool? tcpReachable,  String? networkError,  bool? identityPresent,  String? identityError,  bool adbBurstRequested,  String? wirelessProperties,  List<String> notes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceDiagnosis() when $default != null:
return $default(_that.device,_that.connected,_that.connectionId,_that.usbBackendAvailable,_that.features,_that.identity,_that.observations,_that.tcpReachable,_that.networkError,_that.identityPresent,_that.identityError,_that.adbBurstRequested,_that.wirelessProperties,_that.notes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DeviceSnapshot device,  bool connected,  String? connectionId,  bool? usbBackendAvailable,  List<String> features,  DeviceCapabilityObservation identity,  Map<String, DeviceCapabilityObservation> observations,  bool? tcpReachable,  String? networkError,  bool? identityPresent,  String? identityError,  bool adbBurstRequested,  String? wirelessProperties,  List<String> notes)  $default,) {final _that = this;
switch (_that) {
case _DeviceDiagnosis():
return $default(_that.device,_that.connected,_that.connectionId,_that.usbBackendAvailable,_that.features,_that.identity,_that.observations,_that.tcpReachable,_that.networkError,_that.identityPresent,_that.identityError,_that.adbBurstRequested,_that.wirelessProperties,_that.notes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DeviceSnapshot device,  bool connected,  String? connectionId,  bool? usbBackendAvailable,  List<String> features,  DeviceCapabilityObservation identity,  Map<String, DeviceCapabilityObservation> observations,  bool? tcpReachable,  String? networkError,  bool? identityPresent,  String? identityError,  bool adbBurstRequested,  String? wirelessProperties,  List<String> notes)?  $default,) {final _that = this;
switch (_that) {
case _DeviceDiagnosis() when $default != null:
return $default(_that.device,_that.connected,_that.connectionId,_that.usbBackendAvailable,_that.features,_that.identity,_that.observations,_that.tcpReachable,_that.networkError,_that.identityPresent,_that.identityError,_that.adbBurstRequested,_that.wirelessProperties,_that.notes);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceDiagnosis implements DeviceDiagnosis {
  const _DeviceDiagnosis({required this.device, required this.connected, this.connectionId, this.usbBackendAvailable,  List<String> features = const [], this.identity = const DeviceCapabilityObservation.unknown(),  Map<String, DeviceCapabilityObservation> observations = const {}, this.tcpReachable, this.networkError, this.identityPresent, this.identityError, required this.adbBurstRequested, this.wirelessProperties,  List<String> notes = const []}): _features = features,_observations = observations,_notes = notes;
  

@override final  DeviceSnapshot device;
@override final  bool connected;
@override final  String? connectionId;
@override final  bool? usbBackendAvailable;
 final  List<String> _features;
@override@JsonKey() List<String> get features {
  if (_features is EqualUnmodifiableListView) return _features;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_features);
}

@override@JsonKey() final  DeviceCapabilityObservation identity;
 final  Map<String, DeviceCapabilityObservation> _observations;
@override@JsonKey() Map<String, DeviceCapabilityObservation> get observations {
  if (_observations is EqualUnmodifiableMapView) return _observations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_observations);
}

@override final  bool? tcpReachable;
@override final  String? networkError;
@override final  bool? identityPresent;
@override final  String? identityError;
@override final  bool adbBurstRequested;
@override final  String? wirelessProperties;
 final  List<String> _notes;
@override@JsonKey() List<String> get notes {
  if (_notes is EqualUnmodifiableListView) return _notes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_notes);
}


/// Create a copy of DeviceDiagnosis
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceDiagnosisCopyWith<_DeviceDiagnosis> get copyWith => __$DeviceDiagnosisCopyWithImpl<_DeviceDiagnosis>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceDiagnosis&&(identical(other.device, device) || other.device == device)&&(identical(other.connected, connected) || other.connected == connected)&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId)&&(identical(other.usbBackendAvailable, usbBackendAvailable) || other.usbBackendAvailable == usbBackendAvailable)&&const DeepCollectionEquality().equals(other.features, _features)&&(identical(other.identity, identity) || other.identity == identity)&&const DeepCollectionEquality().equals(other.observations, _observations)&&(identical(other.tcpReachable, tcpReachable) || other.tcpReachable == tcpReachable)&&(identical(other.networkError, networkError) || other.networkError == networkError)&&(identical(other.identityPresent, identityPresent) || other.identityPresent == identityPresent)&&(identical(other.identityError, identityError) || other.identityError == identityError)&&(identical(other.adbBurstRequested, adbBurstRequested) || other.adbBurstRequested == adbBurstRequested)&&(identical(other.wirelessProperties, wirelessProperties) || other.wirelessProperties == wirelessProperties)&&const DeepCollectionEquality().equals(other.notes, _notes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,device,connected,connectionId,usbBackendAvailable,const DeepCollectionEquality().hash(_features),identity,const DeepCollectionEquality().hash(_observations),tcpReachable,networkError,identityPresent,identityError,adbBurstRequested,wirelessProperties,const DeepCollectionEquality().hash(_notes));
}

@override
String toString() {
    return 'DeviceDiagnosis(device: $device, connected: $connected, connectionId: $connectionId, usbBackendAvailable: $usbBackendAvailable, features: $features, identity: $identity, observations: $observations, tcpReachable: $tcpReachable, networkError: $networkError, identityPresent: $identityPresent, identityError: $identityError, adbBurstRequested: $adbBurstRequested, wirelessProperties: $wirelessProperties, notes: $notes)';
}


}

/// @nodoc
abstract mixin class _$DeviceDiagnosisCopyWith<$Res> implements $DeviceDiagnosisCopyWith<$Res> {
  factory _$DeviceDiagnosisCopyWith(_DeviceDiagnosis value, $Res Function(_DeviceDiagnosis) _then) = __$DeviceDiagnosisCopyWithImpl;
@override @useResult
$Res call({
 DeviceSnapshot device, bool connected, String? connectionId, bool? usbBackendAvailable, List<String> features, DeviceCapabilityObservation identity, Map<String, DeviceCapabilityObservation> observations, bool? tcpReachable, String? networkError, bool? identityPresent, String? identityError, bool adbBurstRequested, String? wirelessProperties, List<String> notes
});


@override $DeviceSnapshotCopyWith<$Res> get device;

}
/// @nodoc
class __$DeviceDiagnosisCopyWithImpl<$Res>
    implements _$DeviceDiagnosisCopyWith<$Res> {
  __$DeviceDiagnosisCopyWithImpl(this._self, this._then);

  final _DeviceDiagnosis _self;
  final $Res Function(_DeviceDiagnosis) _then;

/// Create a copy of DeviceDiagnosis
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? device = null,Object? connected = null,Object? connectionId = freezed,Object? usbBackendAvailable = freezed,Object? features = null,Object? identity = null,Object? observations = null,Object? tcpReachable = freezed,Object? networkError = freezed,Object? identityPresent = freezed,Object? identityError = freezed,Object? adbBurstRequested = null,Object? wirelessProperties = freezed,Object? notes = null,}) {
  return _then(_DeviceDiagnosis(
device: null == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as DeviceSnapshot,connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,connectionId: freezed == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String?,usbBackendAvailable: freezed == usbBackendAvailable ? _self.usbBackendAvailable : usbBackendAvailable // ignore: cast_nullable_to_non_nullable
as bool?,features: null == features ? _self._features : features // ignore: cast_nullable_to_non_nullable
as List<String>,identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as DeviceCapabilityObservation,observations: null == observations ? _self._observations : observations // ignore: cast_nullable_to_non_nullable
as Map<String, DeviceCapabilityObservation>,tcpReachable: freezed == tcpReachable ? _self.tcpReachable : tcpReachable // ignore: cast_nullable_to_non_nullable
as bool?,networkError: freezed == networkError ? _self.networkError : networkError // ignore: cast_nullable_to_non_nullable
as String?,identityPresent: freezed == identityPresent ? _self.identityPresent : identityPresent // ignore: cast_nullable_to_non_nullable
as bool?,identityError: freezed == identityError ? _self.identityError : identityError // ignore: cast_nullable_to_non_nullable
as String?,adbBurstRequested: null == adbBurstRequested ? _self.adbBurstRequested : adbBurstRequested // ignore: cast_nullable_to_non_nullable
as bool,wirelessProperties: freezed == wirelessProperties ? _self.wirelessProperties : wirelessProperties // ignore: cast_nullable_to_non_nullable
as String?,notes: null == notes ? _self._notes : notes // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

/// Create a copy of DeviceDiagnosis
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
