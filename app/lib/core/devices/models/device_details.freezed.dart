// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_details.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DeviceReading<T> {

 String get deviceId; T get value; String? get connectionId; int? get observedAt; bool get stale;
/// Create a copy of DeviceReading
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceReadingCopyWith<T, DeviceReading<T>> get copyWith => _$DeviceReadingCopyWithImpl<T, DeviceReading<T>>(this as DeviceReading<T>, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceReading<T>;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceReading<T>&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&const DeepCollectionEquality().equals(other.value, _this.value)&&(identical(other.connectionId, _this.connectionId) || other.connectionId == _this.connectionId)&&(identical(other.observedAt, _this.observedAt) || other.observedAt == _this.observedAt)&&(identical(other.stale, _this.stale) || other.stale == _this.stale));
}


@override
int get hashCode {
  final _this = this as DeviceReading<T>;
  return Object.hash(runtimeType,_this.deviceId,const DeepCollectionEquality().hash(_this.value),_this.connectionId,_this.observedAt,_this.stale);
}

@override
String toString() {
  final _this = this as DeviceReading<T>;
  return 'DeviceReading<$T>(deviceId: ${_this.deviceId}, value: ${_this.value}, connectionId: ${_this.connectionId}, observedAt: ${_this.observedAt}, stale: ${_this.stale})';
}


}

/// @nodoc
abstract mixin class $DeviceReadingCopyWith<T,$Res>  {
  factory $DeviceReadingCopyWith(DeviceReading<T> value, $Res Function(DeviceReading<T>) _then) = _$DeviceReadingCopyWithImpl;
@useResult
$Res call({
 String deviceId, T value, String? connectionId, int? observedAt, bool stale
});




}
/// @nodoc
class _$DeviceReadingCopyWithImpl<T,$Res>
    implements $DeviceReadingCopyWith<T, $Res> {
  _$DeviceReadingCopyWithImpl(this._self, this._then);

  final DeviceReading<T> _self;
  final $Res Function(DeviceReading<T>) _then;

/// Create a copy of DeviceReading
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? value = freezed,Object? connectionId = freezed,Object? observedAt = freezed,Object? stale = null,}) {
  return _then(DeviceReading(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,connectionId: freezed == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String?,observedAt: freezed == observedAt ? _self.observedAt : observedAt // ignore: cast_nullable_to_non_nullable
as int?,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceReading].
extension DeviceReadingPatterns<T> on DeviceReading<T> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceReading<T> value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceReading() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceReading<T> value)  $default,){
final _that = this;
switch (_that) {
case _DeviceReading():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceReading<T> value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceReading() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  T value,  String? connectionId,  int? observedAt,  bool stale)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceReading() when $default != null:
return $default(_that.deviceId,_that.value,_that.connectionId,_that.observedAt,_that.stale);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  T value,  String? connectionId,  int? observedAt,  bool stale)  $default,) {final _that = this;
switch (_that) {
case _DeviceReading():
return $default(_that.deviceId,_that.value,_that.connectionId,_that.observedAt,_that.stale);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  T value,  String? connectionId,  int? observedAt,  bool stale)?  $default,) {final _that = this;
switch (_that) {
case _DeviceReading() when $default != null:
return $default(_that.deviceId,_that.value,_that.connectionId,_that.observedAt,_that.stale);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceReading<T> implements DeviceReading<T> {
  const _DeviceReading({required this.deviceId, required this.value, this.connectionId, this.observedAt, this.stale = false});
  

@override final  String deviceId;
@override final  T value;
@override final  String? connectionId;
@override final  int? observedAt;
@override@JsonKey() final  bool stale;

/// Create a copy of DeviceReading
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceReadingCopyWith<T, _DeviceReading<T>> get copyWith => __$DeviceReadingCopyWithImpl<T, _DeviceReading<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceReading<T>&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&const DeepCollectionEquality().equals(other.value, value)&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId)&&(identical(other.observedAt, observedAt) || other.observedAt == observedAt)&&(identical(other.stale, stale) || other.stale == stale));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,const DeepCollectionEquality().hash(value),connectionId,observedAt,stale);
}

@override
String toString() {
    return 'DeviceReading<$T>(deviceId: $deviceId, value: $value, connectionId: $connectionId, observedAt: $observedAt, stale: $stale)';
}


}

/// @nodoc
abstract mixin class _$DeviceReadingCopyWith<T,$Res> implements $DeviceReadingCopyWith<T, $Res> {
  factory _$DeviceReadingCopyWith(_DeviceReading<T> value, $Res Function(_DeviceReading<T>) _then) = __$DeviceReadingCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, T value, String? connectionId, int? observedAt, bool stale
});




}
/// @nodoc
class __$DeviceReadingCopyWithImpl<T,$Res>
    implements _$DeviceReadingCopyWith<T, $Res> {
  __$DeviceReadingCopyWithImpl(this._self, this._then);

  final _DeviceReading<T> _self;
  final $Res Function(_DeviceReading<T>) _then;

/// Create a copy of DeviceReading
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? value = freezed,Object? connectionId = freezed,Object? observedAt = freezed,Object? stale = null,}) {
  return _then(_DeviceReading<T>(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,connectionId: freezed == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String?,observedAt: freezed == observedAt ? _self.observedAt : observedAt // ignore: cast_nullable_to_non_nullable
as int?,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$DeviceReadFailure {

 String get code; String get message;
/// Create a copy of DeviceReadFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceReadFailureCopyWith<DeviceReadFailure> get copyWith => _$DeviceReadFailureCopyWithImpl<DeviceReadFailure>(this as DeviceReadFailure, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceReadFailure;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceReadFailure&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as DeviceReadFailure;
  return Object.hash(runtimeType,_this.code,_this.message);
}

@override
String toString() {
  final _this = this as DeviceReadFailure;
  return 'DeviceReadFailure(code: ${_this.code}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $DeviceReadFailureCopyWith<$Res>  {
  factory $DeviceReadFailureCopyWith(DeviceReadFailure value, $Res Function(DeviceReadFailure) _then) = _$DeviceReadFailureCopyWithImpl;
@useResult
$Res call({
 String code, String message
});




}
/// @nodoc
class _$DeviceReadFailureCopyWithImpl<$Res>
    implements $DeviceReadFailureCopyWith<$Res> {
  _$DeviceReadFailureCopyWithImpl(this._self, this._then);

  final DeviceReadFailure _self;
  final $Res Function(DeviceReadFailure) _then;

/// Create a copy of DeviceReadFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? message = null,}) {
  return _then(DeviceReadFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceReadFailure].
extension DeviceReadFailurePatterns on DeviceReadFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceReadFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceReadFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceReadFailure value)  $default,){
final _that = this;
switch (_that) {
case _DeviceReadFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceReadFailure value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceReadFailure() when $default != null:
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
case _DeviceReadFailure() when $default != null:
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
case _DeviceReadFailure():
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
case _DeviceReadFailure() when $default != null:
return $default(_that.code,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceReadFailure implements DeviceReadFailure {
  const _DeviceReadFailure({required this.code, required this.message});
  

@override final  String code;
@override final  String message;

/// Create a copy of DeviceReadFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceReadFailureCopyWith<_DeviceReadFailure> get copyWith => __$DeviceReadFailureCopyWithImpl<_DeviceReadFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceReadFailure&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,message);
}

@override
String toString() {
    return 'DeviceReadFailure(code: $code, message: $message)';
}


}

/// @nodoc
abstract mixin class _$DeviceReadFailureCopyWith<$Res> implements $DeviceReadFailureCopyWith<$Res> {
  factory _$DeviceReadFailureCopyWith(_DeviceReadFailure value, $Res Function(_DeviceReadFailure) _then) = __$DeviceReadFailureCopyWithImpl;
@override @useResult
$Res call({
 String code, String message
});




}
/// @nodoc
class __$DeviceReadFailureCopyWithImpl<$Res>
    implements _$DeviceReadFailureCopyWith<$Res> {
  __$DeviceReadFailureCopyWithImpl(this._self, this._then);

  final _DeviceReadFailure _self;
  final $Res Function(_DeviceReadFailure) _then;

/// Create a copy of DeviceReadFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,}) {
  return _then(_DeviceReadFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$DeviceDetails {

 DeviceSystemInfo get system; DeviceBattery get battery; DeviceDisplayInfo get display; DeviceNetworkInfo get network; DeviceCapacity get memory; DeviceCapacity get storage; int? get cpuCores; Map<DeviceDetailSection, DeviceReadFailure> get failures;
/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceDetailsCopyWith<DeviceDetails> get copyWith => _$DeviceDetailsCopyWithImpl<DeviceDetails>(this as DeviceDetails, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceDetails;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceDetails&&(identical(other.system, _this.system) || other.system == _this.system)&&(identical(other.battery, _this.battery) || other.battery == _this.battery)&&(identical(other.display, _this.display) || other.display == _this.display)&&(identical(other.network, _this.network) || other.network == _this.network)&&(identical(other.memory, _this.memory) || other.memory == _this.memory)&&(identical(other.storage, _this.storage) || other.storage == _this.storage)&&(identical(other.cpuCores, _this.cpuCores) || other.cpuCores == _this.cpuCores)&&const DeepCollectionEquality().equals(other.failures, _this.failures));
}


@override
int get hashCode {
  final _this = this as DeviceDetails;
  return Object.hash(runtimeType,_this.system,_this.battery,_this.display,_this.network,_this.memory,_this.storage,_this.cpuCores,const DeepCollectionEquality().hash(_this.failures));
}

@override
String toString() {
  final _this = this as DeviceDetails;
  return 'DeviceDetails(system: ${_this.system}, battery: ${_this.battery}, display: ${_this.display}, network: ${_this.network}, memory: ${_this.memory}, storage: ${_this.storage}, cpuCores: ${_this.cpuCores}, failures: ${_this.failures})';
}


}

/// @nodoc
abstract mixin class $DeviceDetailsCopyWith<$Res>  {
  factory $DeviceDetailsCopyWith(DeviceDetails value, $Res Function(DeviceDetails) _then) = _$DeviceDetailsCopyWithImpl;
@useResult
$Res call({
 DeviceSystemInfo system, DeviceBattery battery, DeviceDisplayInfo display, DeviceNetworkInfo network, DeviceCapacity memory, DeviceCapacity storage, int? cpuCores, Map<DeviceDetailSection, DeviceReadFailure> failures
});


$DeviceSystemInfoCopyWith<$Res> get system;$DeviceBatteryCopyWith<$Res> get battery;$DeviceDisplayInfoCopyWith<$Res> get display;$DeviceNetworkInfoCopyWith<$Res> get network;

}
/// @nodoc
class _$DeviceDetailsCopyWithImpl<$Res>
    implements $DeviceDetailsCopyWith<$Res> {
  _$DeviceDetailsCopyWithImpl(this._self, this._then);

  final DeviceDetails _self;
  final $Res Function(DeviceDetails) _then;

/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? system = null,Object? battery = null,Object? display = null,Object? network = null,Object? memory = null,Object? storage = null,Object? cpuCores = freezed,Object? failures = null,}) {
  return _then(DeviceDetails(
system: null == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as DeviceSystemInfo,battery: null == battery ? _self.battery : battery // ignore: cast_nullable_to_non_nullable
as DeviceBattery,display: null == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as DeviceDisplayInfo,network: null == network ? _self.network : network // ignore: cast_nullable_to_non_nullable
as DeviceNetworkInfo,memory: null == memory ? _self.memory : memory // ignore: cast_nullable_to_non_nullable
as DeviceCapacity,storage: null == storage ? _self.storage : storage // ignore: cast_nullable_to_non_nullable
as DeviceCapacity,cpuCores: freezed == cpuCores ? _self.cpuCores : cpuCores // ignore: cast_nullable_to_non_nullable
as int?,failures: null == failures ? _self.failures : failures // ignore: cast_nullable_to_non_nullable
as Map<DeviceDetailSection, DeviceReadFailure>,
  ));
}
/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceSystemInfoCopyWith<$Res> get system {
  
  return $DeviceSystemInfoCopyWith<$Res>(_self.system, (value) {
    return _then(_self.copyWith(system: value));
  });
}/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceBatteryCopyWith<$Res> get battery {
  
  return $DeviceBatteryCopyWith<$Res>(_self.battery, (value) {
    return _then(_self.copyWith(battery: value));
  });
}/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceDisplayInfoCopyWith<$Res> get display {
  
  return $DeviceDisplayInfoCopyWith<$Res>(_self.display, (value) {
    return _then(_self.copyWith(display: value));
  });
}/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceNetworkInfoCopyWith<$Res> get network {
  
  return $DeviceNetworkInfoCopyWith<$Res>(_self.network, (value) {
    return _then(_self.copyWith(network: value));
  });
}
}


/// Adds pattern-matching-related methods to [DeviceDetails].
extension DeviceDetailsPatterns on DeviceDetails {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceDetails value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceDetails() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceDetails value)  $default,){
final _that = this;
switch (_that) {
case _DeviceDetails():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceDetails value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceDetails() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DeviceSystemInfo system,  DeviceBattery battery,  DeviceDisplayInfo display,  DeviceNetworkInfo network,  DeviceCapacity memory,  DeviceCapacity storage,  int? cpuCores,  Map<DeviceDetailSection, DeviceReadFailure> failures)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceDetails() when $default != null:
return $default(_that.system,_that.battery,_that.display,_that.network,_that.memory,_that.storage,_that.cpuCores,_that.failures);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DeviceSystemInfo system,  DeviceBattery battery,  DeviceDisplayInfo display,  DeviceNetworkInfo network,  DeviceCapacity memory,  DeviceCapacity storage,  int? cpuCores,  Map<DeviceDetailSection, DeviceReadFailure> failures)  $default,) {final _that = this;
switch (_that) {
case _DeviceDetails():
return $default(_that.system,_that.battery,_that.display,_that.network,_that.memory,_that.storage,_that.cpuCores,_that.failures);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DeviceSystemInfo system,  DeviceBattery battery,  DeviceDisplayInfo display,  DeviceNetworkInfo network,  DeviceCapacity memory,  DeviceCapacity storage,  int? cpuCores,  Map<DeviceDetailSection, DeviceReadFailure> failures)?  $default,) {final _that = this;
switch (_that) {
case _DeviceDetails() when $default != null:
return $default(_that.system,_that.battery,_that.display,_that.network,_that.memory,_that.storage,_that.cpuCores,_that.failures);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceDetails implements DeviceDetails {
  const _DeviceDetails({this.system = const DeviceSystemInfo(), this.battery = const DeviceBattery(), this.display = const DeviceDisplayInfo(), this.network = const DeviceNetworkInfo(), this.memory = const (totalBytes: null, availableBytes: null), this.storage = const (totalBytes: null, availableBytes: null), this.cpuCores,  Map<DeviceDetailSection, DeviceReadFailure> failures = const {}}): _failures = failures;
  

@override@JsonKey() final  DeviceSystemInfo system;
@override@JsonKey() final  DeviceBattery battery;
@override@JsonKey() final  DeviceDisplayInfo display;
@override@JsonKey() final  DeviceNetworkInfo network;
@override@JsonKey() final  DeviceCapacity memory;
@override@JsonKey() final  DeviceCapacity storage;
@override final  int? cpuCores;
 final  Map<DeviceDetailSection, DeviceReadFailure> _failures;
@override@JsonKey() Map<DeviceDetailSection, DeviceReadFailure> get failures {
  if (_failures is EqualUnmodifiableMapView) return _failures;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_failures);
}


/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceDetailsCopyWith<_DeviceDetails> get copyWith => __$DeviceDetailsCopyWithImpl<_DeviceDetails>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceDetails&&(identical(other.system, system) || other.system == system)&&(identical(other.battery, battery) || other.battery == battery)&&(identical(other.display, display) || other.display == display)&&(identical(other.network, network) || other.network == network)&&(identical(other.memory, memory) || other.memory == memory)&&(identical(other.storage, storage) || other.storage == storage)&&(identical(other.cpuCores, cpuCores) || other.cpuCores == cpuCores)&&const DeepCollectionEquality().equals(other.failures, _failures));
}


@override
int get hashCode {
    return Object.hash(runtimeType,system,battery,display,network,memory,storage,cpuCores,const DeepCollectionEquality().hash(_failures));
}

@override
String toString() {
    return 'DeviceDetails(system: $system, battery: $battery, display: $display, network: $network, memory: $memory, storage: $storage, cpuCores: $cpuCores, failures: $failures)';
}


}

/// @nodoc
abstract mixin class _$DeviceDetailsCopyWith<$Res> implements $DeviceDetailsCopyWith<$Res> {
  factory _$DeviceDetailsCopyWith(_DeviceDetails value, $Res Function(_DeviceDetails) _then) = __$DeviceDetailsCopyWithImpl;
@override @useResult
$Res call({
 DeviceSystemInfo system, DeviceBattery battery, DeviceDisplayInfo display, DeviceNetworkInfo network, DeviceCapacity memory, DeviceCapacity storage, int? cpuCores, Map<DeviceDetailSection, DeviceReadFailure> failures
});


@override $DeviceSystemInfoCopyWith<$Res> get system;@override $DeviceBatteryCopyWith<$Res> get battery;@override $DeviceDisplayInfoCopyWith<$Res> get display;@override $DeviceNetworkInfoCopyWith<$Res> get network;

}
/// @nodoc
class __$DeviceDetailsCopyWithImpl<$Res>
    implements _$DeviceDetailsCopyWith<$Res> {
  __$DeviceDetailsCopyWithImpl(this._self, this._then);

  final _DeviceDetails _self;
  final $Res Function(_DeviceDetails) _then;

/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? system = null,Object? battery = null,Object? display = null,Object? network = null,Object? memory = null,Object? storage = null,Object? cpuCores = freezed,Object? failures = null,}) {
  return _then(_DeviceDetails(
system: null == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as DeviceSystemInfo,battery: null == battery ? _self.battery : battery // ignore: cast_nullable_to_non_nullable
as DeviceBattery,display: null == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as DeviceDisplayInfo,network: null == network ? _self.network : network // ignore: cast_nullable_to_non_nullable
as DeviceNetworkInfo,memory: null == memory ? _self.memory : memory // ignore: cast_nullable_to_non_nullable
as DeviceCapacity,storage: null == storage ? _self.storage : storage // ignore: cast_nullable_to_non_nullable
as DeviceCapacity,cpuCores: freezed == cpuCores ? _self.cpuCores : cpuCores // ignore: cast_nullable_to_non_nullable
as int?,failures: null == failures ? _self._failures : failures // ignore: cast_nullable_to_non_nullable
as Map<DeviceDetailSection, DeviceReadFailure>,
  ));
}

/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceSystemInfoCopyWith<$Res> get system {
  
  return $DeviceSystemInfoCopyWith<$Res>(_self.system, (value) {
    return _then(_self.copyWith(system: value));
  });
}/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceBatteryCopyWith<$Res> get battery {
  
  return $DeviceBatteryCopyWith<$Res>(_self.battery, (value) {
    return _then(_self.copyWith(battery: value));
  });
}/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceDisplayInfoCopyWith<$Res> get display {
  
  return $DeviceDisplayInfoCopyWith<$Res>(_self.display, (value) {
    return _then(_self.copyWith(display: value));
  });
}/// Create a copy of DeviceDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceNetworkInfoCopyWith<$Res> get network {
  
  return $DeviceNetworkInfoCopyWith<$Res>(_self.network, (value) {
    return _then(_self.copyWith(network: value));
  });
}
}

/// @nodoc
mixin _$DeviceSystemInfo {

 String? get model; String? get brand; String? get product; String? get hardware; String? get androidVersion; int? get apiLevel; String? get securityPatch; String? get build; String? get serial; String? get abi;
/// Create a copy of DeviceSystemInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceSystemInfoCopyWith<DeviceSystemInfo> get copyWith => _$DeviceSystemInfoCopyWithImpl<DeviceSystemInfo>(this as DeviceSystemInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceSystemInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceSystemInfo&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.brand, _this.brand) || other.brand == _this.brand)&&(identical(other.product, _this.product) || other.product == _this.product)&&(identical(other.hardware, _this.hardware) || other.hardware == _this.hardware)&&(identical(other.androidVersion, _this.androidVersion) || other.androidVersion == _this.androidVersion)&&(identical(other.apiLevel, _this.apiLevel) || other.apiLevel == _this.apiLevel)&&(identical(other.securityPatch, _this.securityPatch) || other.securityPatch == _this.securityPatch)&&(identical(other.build, _this.build) || other.build == _this.build)&&(identical(other.serial, _this.serial) || other.serial == _this.serial)&&(identical(other.abi, _this.abi) || other.abi == _this.abi));
}


@override
int get hashCode {
  final _this = this as DeviceSystemInfo;
  return Object.hash(runtimeType,_this.model,_this.brand,_this.product,_this.hardware,_this.androidVersion,_this.apiLevel,_this.securityPatch,_this.build,_this.serial,_this.abi);
}

@override
String toString() {
  final _this = this as DeviceSystemInfo;
  return 'DeviceSystemInfo(model: ${_this.model}, brand: ${_this.brand}, product: ${_this.product}, hardware: ${_this.hardware}, androidVersion: ${_this.androidVersion}, apiLevel: ${_this.apiLevel}, securityPatch: ${_this.securityPatch}, build: ${_this.build}, serial: ${_this.serial}, abi: ${_this.abi})';
}


}

/// @nodoc
abstract mixin class $DeviceSystemInfoCopyWith<$Res>  {
  factory $DeviceSystemInfoCopyWith(DeviceSystemInfo value, $Res Function(DeviceSystemInfo) _then) = _$DeviceSystemInfoCopyWithImpl;
@useResult
$Res call({
 String? model, String? brand, String? product, String? hardware, String? androidVersion, int? apiLevel, String? securityPatch, String? build, String? serial, String? abi
});




}
/// @nodoc
class _$DeviceSystemInfoCopyWithImpl<$Res>
    implements $DeviceSystemInfoCopyWith<$Res> {
  _$DeviceSystemInfoCopyWithImpl(this._self, this._then);

  final DeviceSystemInfo _self;
  final $Res Function(DeviceSystemInfo) _then;

/// Create a copy of DeviceSystemInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? model = freezed,Object? brand = freezed,Object? product = freezed,Object? hardware = freezed,Object? androidVersion = freezed,Object? apiLevel = freezed,Object? securityPatch = freezed,Object? build = freezed,Object? serial = freezed,Object? abi = freezed,}) {
  return _then(DeviceSystemInfo(
model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,brand: freezed == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String?,product: freezed == product ? _self.product : product // ignore: cast_nullable_to_non_nullable
as String?,hardware: freezed == hardware ? _self.hardware : hardware // ignore: cast_nullable_to_non_nullable
as String?,androidVersion: freezed == androidVersion ? _self.androidVersion : androidVersion // ignore: cast_nullable_to_non_nullable
as String?,apiLevel: freezed == apiLevel ? _self.apiLevel : apiLevel // ignore: cast_nullable_to_non_nullable
as int?,securityPatch: freezed == securityPatch ? _self.securityPatch : securityPatch // ignore: cast_nullable_to_non_nullable
as String?,build: freezed == build ? _self.build : build // ignore: cast_nullable_to_non_nullable
as String?,serial: freezed == serial ? _self.serial : serial // ignore: cast_nullable_to_non_nullable
as String?,abi: freezed == abi ? _self.abi : abi // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceSystemInfo].
extension DeviceSystemInfoPatterns on DeviceSystemInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceSystemInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceSystemInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceSystemInfo value)  $default,){
final _that = this;
switch (_that) {
case _DeviceSystemInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceSystemInfo value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceSystemInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? model,  String? brand,  String? product,  String? hardware,  String? androidVersion,  int? apiLevel,  String? securityPatch,  String? build,  String? serial,  String? abi)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceSystemInfo() when $default != null:
return $default(_that.model,_that.brand,_that.product,_that.hardware,_that.androidVersion,_that.apiLevel,_that.securityPatch,_that.build,_that.serial,_that.abi);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? model,  String? brand,  String? product,  String? hardware,  String? androidVersion,  int? apiLevel,  String? securityPatch,  String? build,  String? serial,  String? abi)  $default,) {final _that = this;
switch (_that) {
case _DeviceSystemInfo():
return $default(_that.model,_that.brand,_that.product,_that.hardware,_that.androidVersion,_that.apiLevel,_that.securityPatch,_that.build,_that.serial,_that.abi);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? model,  String? brand,  String? product,  String? hardware,  String? androidVersion,  int? apiLevel,  String? securityPatch,  String? build,  String? serial,  String? abi)?  $default,) {final _that = this;
switch (_that) {
case _DeviceSystemInfo() when $default != null:
return $default(_that.model,_that.brand,_that.product,_that.hardware,_that.androidVersion,_that.apiLevel,_that.securityPatch,_that.build,_that.serial,_that.abi);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceSystemInfo implements DeviceSystemInfo {
  const _DeviceSystemInfo({this.model, this.brand, this.product, this.hardware, this.androidVersion, this.apiLevel, this.securityPatch, this.build, this.serial, this.abi});
  

@override final  String? model;
@override final  String? brand;
@override final  String? product;
@override final  String? hardware;
@override final  String? androidVersion;
@override final  int? apiLevel;
@override final  String? securityPatch;
@override final  String? build;
@override final  String? serial;
@override final  String? abi;

/// Create a copy of DeviceSystemInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceSystemInfoCopyWith<_DeviceSystemInfo> get copyWith => __$DeviceSystemInfoCopyWithImpl<_DeviceSystemInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceSystemInfo&&(identical(other.model, model) || other.model == model)&&(identical(other.brand, brand) || other.brand == brand)&&(identical(other.product, product) || other.product == product)&&(identical(other.hardware, hardware) || other.hardware == hardware)&&(identical(other.androidVersion, androidVersion) || other.androidVersion == androidVersion)&&(identical(other.apiLevel, apiLevel) || other.apiLevel == apiLevel)&&(identical(other.securityPatch, securityPatch) || other.securityPatch == securityPatch)&&(identical(other.build, build) || other.build == build)&&(identical(other.serial, serial) || other.serial == serial)&&(identical(other.abi, abi) || other.abi == abi));
}


@override
int get hashCode {
    return Object.hash(runtimeType,model,brand,product,hardware,androidVersion,apiLevel,securityPatch,build,serial,abi);
}

@override
String toString() {
    return 'DeviceSystemInfo(model: $model, brand: $brand, product: $product, hardware: $hardware, androidVersion: $androidVersion, apiLevel: $apiLevel, securityPatch: $securityPatch, build: $build, serial: $serial, abi: $abi)';
}


}

/// @nodoc
abstract mixin class _$DeviceSystemInfoCopyWith<$Res> implements $DeviceSystemInfoCopyWith<$Res> {
  factory _$DeviceSystemInfoCopyWith(_DeviceSystemInfo value, $Res Function(_DeviceSystemInfo) _then) = __$DeviceSystemInfoCopyWithImpl;
@override @useResult
$Res call({
 String? model, String? brand, String? product, String? hardware, String? androidVersion, int? apiLevel, String? securityPatch, String? build, String? serial, String? abi
});




}
/// @nodoc
class __$DeviceSystemInfoCopyWithImpl<$Res>
    implements _$DeviceSystemInfoCopyWith<$Res> {
  __$DeviceSystemInfoCopyWithImpl(this._self, this._then);

  final _DeviceSystemInfo _self;
  final $Res Function(_DeviceSystemInfo) _then;

/// Create a copy of DeviceSystemInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? model = freezed,Object? brand = freezed,Object? product = freezed,Object? hardware = freezed,Object? androidVersion = freezed,Object? apiLevel = freezed,Object? securityPatch = freezed,Object? build = freezed,Object? serial = freezed,Object? abi = freezed,}) {
  return _then(_DeviceSystemInfo(
model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,brand: freezed == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String?,product: freezed == product ? _self.product : product // ignore: cast_nullable_to_non_nullable
as String?,hardware: freezed == hardware ? _self.hardware : hardware // ignore: cast_nullable_to_non_nullable
as String?,androidVersion: freezed == androidVersion ? _self.androidVersion : androidVersion // ignore: cast_nullable_to_non_nullable
as String?,apiLevel: freezed == apiLevel ? _self.apiLevel : apiLevel // ignore: cast_nullable_to_non_nullable
as int?,securityPatch: freezed == securityPatch ? _self.securityPatch : securityPatch // ignore: cast_nullable_to_non_nullable
as String?,build: freezed == build ? _self.build : build // ignore: cast_nullable_to_non_nullable
as String?,serial: freezed == serial ? _self.serial : serial // ignore: cast_nullable_to_non_nullable
as String?,abi: freezed == abi ? _self.abi : abi // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$DeviceDisplayInfo {

 int? get width; int? get height; int? get densityDpi; double? get refreshRate; DeviceScreenState get screen;
/// Create a copy of DeviceDisplayInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceDisplayInfoCopyWith<DeviceDisplayInfo> get copyWith => _$DeviceDisplayInfoCopyWithImpl<DeviceDisplayInfo>(this as DeviceDisplayInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceDisplayInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceDisplayInfo&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.height, _this.height) || other.height == _this.height)&&(identical(other.densityDpi, _this.densityDpi) || other.densityDpi == _this.densityDpi)&&(identical(other.refreshRate, _this.refreshRate) || other.refreshRate == _this.refreshRate)&&(identical(other.screen, _this.screen) || other.screen == _this.screen));
}


@override
int get hashCode {
  final _this = this as DeviceDisplayInfo;
  return Object.hash(runtimeType,_this.width,_this.height,_this.densityDpi,_this.refreshRate,_this.screen);
}

@override
String toString() {
  final _this = this as DeviceDisplayInfo;
  return 'DeviceDisplayInfo(width: ${_this.width}, height: ${_this.height}, densityDpi: ${_this.densityDpi}, refreshRate: ${_this.refreshRate}, screen: ${_this.screen})';
}


}

/// @nodoc
abstract mixin class $DeviceDisplayInfoCopyWith<$Res>  {
  factory $DeviceDisplayInfoCopyWith(DeviceDisplayInfo value, $Res Function(DeviceDisplayInfo) _then) = _$DeviceDisplayInfoCopyWithImpl;
@useResult
$Res call({
 int? width, int? height, int? densityDpi, double? refreshRate, DeviceScreenState screen
});


$DeviceScreenStateCopyWith<$Res> get screen;

}
/// @nodoc
class _$DeviceDisplayInfoCopyWithImpl<$Res>
    implements $DeviceDisplayInfoCopyWith<$Res> {
  _$DeviceDisplayInfoCopyWithImpl(this._self, this._then);

  final DeviceDisplayInfo _self;
  final $Res Function(DeviceDisplayInfo) _then;

/// Create a copy of DeviceDisplayInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? width = freezed,Object? height = freezed,Object? densityDpi = freezed,Object? refreshRate = freezed,Object? screen = null,}) {
  return _then(DeviceDisplayInfo(
width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,densityDpi: freezed == densityDpi ? _self.densityDpi : densityDpi // ignore: cast_nullable_to_non_nullable
as int?,refreshRate: freezed == refreshRate ? _self.refreshRate : refreshRate // ignore: cast_nullable_to_non_nullable
as double?,screen: null == screen ? _self.screen : screen // ignore: cast_nullable_to_non_nullable
as DeviceScreenState,
  ));
}
/// Create a copy of DeviceDisplayInfo
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceScreenStateCopyWith<$Res> get screen {
  
  return $DeviceScreenStateCopyWith<$Res>(_self.screen, (value) {
    return _then(_self.copyWith(screen: value));
  });
}
}


/// Adds pattern-matching-related methods to [DeviceDisplayInfo].
extension DeviceDisplayInfoPatterns on DeviceDisplayInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceDisplayInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceDisplayInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceDisplayInfo value)  $default,){
final _that = this;
switch (_that) {
case _DeviceDisplayInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceDisplayInfo value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceDisplayInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? width,  int? height,  int? densityDpi,  double? refreshRate,  DeviceScreenState screen)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceDisplayInfo() when $default != null:
return $default(_that.width,_that.height,_that.densityDpi,_that.refreshRate,_that.screen);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? width,  int? height,  int? densityDpi,  double? refreshRate,  DeviceScreenState screen)  $default,) {final _that = this;
switch (_that) {
case _DeviceDisplayInfo():
return $default(_that.width,_that.height,_that.densityDpi,_that.refreshRate,_that.screen);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? width,  int? height,  int? densityDpi,  double? refreshRate,  DeviceScreenState screen)?  $default,) {final _that = this;
switch (_that) {
case _DeviceDisplayInfo() when $default != null:
return $default(_that.width,_that.height,_that.densityDpi,_that.refreshRate,_that.screen);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceDisplayInfo implements DeviceDisplayInfo {
  const _DeviceDisplayInfo({this.width, this.height, this.densityDpi, this.refreshRate, this.screen = const DeviceScreenState()});
  

@override final  int? width;
@override final  int? height;
@override final  int? densityDpi;
@override final  double? refreshRate;
@override@JsonKey() final  DeviceScreenState screen;

/// Create a copy of DeviceDisplayInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceDisplayInfoCopyWith<_DeviceDisplayInfo> get copyWith => __$DeviceDisplayInfoCopyWithImpl<_DeviceDisplayInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceDisplayInfo&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.densityDpi, densityDpi) || other.densityDpi == densityDpi)&&(identical(other.refreshRate, refreshRate) || other.refreshRate == refreshRate)&&(identical(other.screen, screen) || other.screen == screen));
}


@override
int get hashCode {
    return Object.hash(runtimeType,width,height,densityDpi,refreshRate,screen);
}

@override
String toString() {
    return 'DeviceDisplayInfo(width: $width, height: $height, densityDpi: $densityDpi, refreshRate: $refreshRate, screen: $screen)';
}


}

/// @nodoc
abstract mixin class _$DeviceDisplayInfoCopyWith<$Res> implements $DeviceDisplayInfoCopyWith<$Res> {
  factory _$DeviceDisplayInfoCopyWith(_DeviceDisplayInfo value, $Res Function(_DeviceDisplayInfo) _then) = __$DeviceDisplayInfoCopyWithImpl;
@override @useResult
$Res call({
 int? width, int? height, int? densityDpi, double? refreshRate, DeviceScreenState screen
});


@override $DeviceScreenStateCopyWith<$Res> get screen;

}
/// @nodoc
class __$DeviceDisplayInfoCopyWithImpl<$Res>
    implements _$DeviceDisplayInfoCopyWith<$Res> {
  __$DeviceDisplayInfoCopyWithImpl(this._self, this._then);

  final _DeviceDisplayInfo _self;
  final $Res Function(_DeviceDisplayInfo) _then;

/// Create a copy of DeviceDisplayInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? width = freezed,Object? height = freezed,Object? densityDpi = freezed,Object? refreshRate = freezed,Object? screen = null,}) {
  return _then(_DeviceDisplayInfo(
width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,densityDpi: freezed == densityDpi ? _self.densityDpi : densityDpi // ignore: cast_nullable_to_non_nullable
as int?,refreshRate: freezed == refreshRate ? _self.refreshRate : refreshRate // ignore: cast_nullable_to_non_nullable
as double?,screen: null == screen ? _self.screen : screen // ignore: cast_nullable_to_non_nullable
as DeviceScreenState,
  ));
}

/// Create a copy of DeviceDisplayInfo
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceScreenStateCopyWith<$Res> get screen {
  
  return $DeviceScreenStateCopyWith<$Res>(_self.screen, (value) {
    return _then(_self.copyWith(screen: value));
  });
}
}

/// @nodoc
mixin _$DeviceScreenState {

 bool? get screenOn; bool? get locked;
/// Create a copy of DeviceScreenState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceScreenStateCopyWith<DeviceScreenState> get copyWith => _$DeviceScreenStateCopyWithImpl<DeviceScreenState>(this as DeviceScreenState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceScreenState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceScreenState&&(identical(other.screenOn, _this.screenOn) || other.screenOn == _this.screenOn)&&(identical(other.locked, _this.locked) || other.locked == _this.locked));
}


@override
int get hashCode {
  final _this = this as DeviceScreenState;
  return Object.hash(runtimeType,_this.screenOn,_this.locked);
}

@override
String toString() {
  final _this = this as DeviceScreenState;
  return 'DeviceScreenState(screenOn: ${_this.screenOn}, locked: ${_this.locked})';
}


}

/// @nodoc
abstract mixin class $DeviceScreenStateCopyWith<$Res>  {
  factory $DeviceScreenStateCopyWith(DeviceScreenState value, $Res Function(DeviceScreenState) _then) = _$DeviceScreenStateCopyWithImpl;
@useResult
$Res call({
 bool? screenOn, bool? locked
});




}
/// @nodoc
class _$DeviceScreenStateCopyWithImpl<$Res>
    implements $DeviceScreenStateCopyWith<$Res> {
  _$DeviceScreenStateCopyWithImpl(this._self, this._then);

  final DeviceScreenState _self;
  final $Res Function(DeviceScreenState) _then;

/// Create a copy of DeviceScreenState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? screenOn = freezed,Object? locked = freezed,}) {
  return _then(DeviceScreenState(
screenOn: freezed == screenOn ? _self.screenOn : screenOn // ignore: cast_nullable_to_non_nullable
as bool?,locked: freezed == locked ? _self.locked : locked // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceScreenState].
extension DeviceScreenStatePatterns on DeviceScreenState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceScreenState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceScreenState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceScreenState value)  $default,){
final _that = this;
switch (_that) {
case _DeviceScreenState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceScreenState value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceScreenState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool? screenOn,  bool? locked)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceScreenState() when $default != null:
return $default(_that.screenOn,_that.locked);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool? screenOn,  bool? locked)  $default,) {final _that = this;
switch (_that) {
case _DeviceScreenState():
return $default(_that.screenOn,_that.locked);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool? screenOn,  bool? locked)?  $default,) {final _that = this;
switch (_that) {
case _DeviceScreenState() when $default != null:
return $default(_that.screenOn,_that.locked);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceScreenState implements DeviceScreenState {
  const _DeviceScreenState({this.screenOn, this.locked});
  

@override final  bool? screenOn;
@override final  bool? locked;

/// Create a copy of DeviceScreenState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceScreenStateCopyWith<_DeviceScreenState> get copyWith => __$DeviceScreenStateCopyWithImpl<_DeviceScreenState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceScreenState&&(identical(other.screenOn, screenOn) || other.screenOn == screenOn)&&(identical(other.locked, locked) || other.locked == locked));
}


@override
int get hashCode {
    return Object.hash(runtimeType,screenOn,locked);
}

@override
String toString() {
    return 'DeviceScreenState(screenOn: $screenOn, locked: $locked)';
}


}

/// @nodoc
abstract mixin class _$DeviceScreenStateCopyWith<$Res> implements $DeviceScreenStateCopyWith<$Res> {
  factory _$DeviceScreenStateCopyWith(_DeviceScreenState value, $Res Function(_DeviceScreenState) _then) = __$DeviceScreenStateCopyWithImpl;
@override @useResult
$Res call({
 bool? screenOn, bool? locked
});




}
/// @nodoc
class __$DeviceScreenStateCopyWithImpl<$Res>
    implements _$DeviceScreenStateCopyWith<$Res> {
  __$DeviceScreenStateCopyWithImpl(this._self, this._then);

  final _DeviceScreenState _self;
  final $Res Function(_DeviceScreenState) _then;

/// Create a copy of DeviceScreenState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? screenOn = freezed,Object? locked = freezed,}) {
  return _then(_DeviceScreenState(
screenOn: freezed == screenOn ? _self.screenOn : screenOn // ignore: cast_nullable_to_non_nullable
as bool?,locked: freezed == locked ? _self.locked : locked // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

/// @nodoc
mixin _$DeviceNetworkAddress {

 String get interface; String get address;
/// Create a copy of DeviceNetworkAddress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceNetworkAddressCopyWith<DeviceNetworkAddress> get copyWith => _$DeviceNetworkAddressCopyWithImpl<DeviceNetworkAddress>(this as DeviceNetworkAddress, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceNetworkAddress;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceNetworkAddress&&(identical(other.interface, _this.interface) || other.interface == _this.interface)&&(identical(other.address, _this.address) || other.address == _this.address));
}


@override
int get hashCode {
  final _this = this as DeviceNetworkAddress;
  return Object.hash(runtimeType,_this.interface,_this.address);
}

@override
String toString() {
  final _this = this as DeviceNetworkAddress;
  return 'DeviceNetworkAddress(interface: ${_this.interface}, address: ${_this.address})';
}


}

/// @nodoc
abstract mixin class $DeviceNetworkAddressCopyWith<$Res>  {
  factory $DeviceNetworkAddressCopyWith(DeviceNetworkAddress value, $Res Function(DeviceNetworkAddress) _then) = _$DeviceNetworkAddressCopyWithImpl;
@useResult
$Res call({
 String interface, String address
});




}
/// @nodoc
class _$DeviceNetworkAddressCopyWithImpl<$Res>
    implements $DeviceNetworkAddressCopyWith<$Res> {
  _$DeviceNetworkAddressCopyWithImpl(this._self, this._then);

  final DeviceNetworkAddress _self;
  final $Res Function(DeviceNetworkAddress) _then;

/// Create a copy of DeviceNetworkAddress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? interface = null,Object? address = null,}) {
  return _then(DeviceNetworkAddress(
interface: null == interface ? _self.interface : interface // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceNetworkAddress].
extension DeviceNetworkAddressPatterns on DeviceNetworkAddress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceNetworkAddress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceNetworkAddress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceNetworkAddress value)  $default,){
final _that = this;
switch (_that) {
case _DeviceNetworkAddress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceNetworkAddress value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceNetworkAddress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String interface,  String address)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceNetworkAddress() when $default != null:
return $default(_that.interface,_that.address);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String interface,  String address)  $default,) {final _that = this;
switch (_that) {
case _DeviceNetworkAddress():
return $default(_that.interface,_that.address);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String interface,  String address)?  $default,) {final _that = this;
switch (_that) {
case _DeviceNetworkAddress() when $default != null:
return $default(_that.interface,_that.address);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceNetworkAddress implements DeviceNetworkAddress {
  const _DeviceNetworkAddress({required this.interface, required this.address});
  

@override final  String interface;
@override final  String address;

/// Create a copy of DeviceNetworkAddress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceNetworkAddressCopyWith<_DeviceNetworkAddress> get copyWith => __$DeviceNetworkAddressCopyWithImpl<_DeviceNetworkAddress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceNetworkAddress&&(identical(other.interface, interface) || other.interface == interface)&&(identical(other.address, address) || other.address == address));
}


@override
int get hashCode {
    return Object.hash(runtimeType,interface,address);
}

@override
String toString() {
    return 'DeviceNetworkAddress(interface: $interface, address: $address)';
}


}

/// @nodoc
abstract mixin class _$DeviceNetworkAddressCopyWith<$Res> implements $DeviceNetworkAddressCopyWith<$Res> {
  factory _$DeviceNetworkAddressCopyWith(_DeviceNetworkAddress value, $Res Function(_DeviceNetworkAddress) _then) = __$DeviceNetworkAddressCopyWithImpl;
@override @useResult
$Res call({
 String interface, String address
});




}
/// @nodoc
class __$DeviceNetworkAddressCopyWithImpl<$Res>
    implements _$DeviceNetworkAddressCopyWith<$Res> {
  __$DeviceNetworkAddressCopyWithImpl(this._self, this._then);

  final _DeviceNetworkAddress _self;
  final $Res Function(_DeviceNetworkAddress) _then;

/// Create a copy of DeviceNetworkAddress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? interface = null,Object? address = null,}) {
  return _then(_DeviceNetworkAddress(
interface: null == interface ? _self.interface : interface // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$DeviceNetworkInfo {

 List<DeviceNetworkAddress> get addresses; DeviceTransport? get transport; String? get address; int? get port;
/// Create a copy of DeviceNetworkInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceNetworkInfoCopyWith<DeviceNetworkInfo> get copyWith => _$DeviceNetworkInfoCopyWithImpl<DeviceNetworkInfo>(this as DeviceNetworkInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceNetworkInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceNetworkInfo&&const DeepCollectionEquality().equals(other.addresses, _this.addresses)&&(identical(other.transport, _this.transport) || other.transport == _this.transport)&&(identical(other.address, _this.address) || other.address == _this.address)&&(identical(other.port, _this.port) || other.port == _this.port));
}


@override
int get hashCode {
  final _this = this as DeviceNetworkInfo;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.addresses),_this.transport,_this.address,_this.port);
}

@override
String toString() {
  final _this = this as DeviceNetworkInfo;
  return 'DeviceNetworkInfo(addresses: ${_this.addresses}, transport: ${_this.transport}, address: ${_this.address}, port: ${_this.port})';
}


}

/// @nodoc
abstract mixin class $DeviceNetworkInfoCopyWith<$Res>  {
  factory $DeviceNetworkInfoCopyWith(DeviceNetworkInfo value, $Res Function(DeviceNetworkInfo) _then) = _$DeviceNetworkInfoCopyWithImpl;
@useResult
$Res call({
 List<DeviceNetworkAddress> addresses, DeviceTransport? transport, String? address, int? port
});




}
/// @nodoc
class _$DeviceNetworkInfoCopyWithImpl<$Res>
    implements $DeviceNetworkInfoCopyWith<$Res> {
  _$DeviceNetworkInfoCopyWithImpl(this._self, this._then);

  final DeviceNetworkInfo _self;
  final $Res Function(DeviceNetworkInfo) _then;

/// Create a copy of DeviceNetworkInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? addresses = null,Object? transport = freezed,Object? address = freezed,Object? port = freezed,}) {
  return _then(DeviceNetworkInfo(
addresses: null == addresses ? _self.addresses : addresses // ignore: cast_nullable_to_non_nullable
as List<DeviceNetworkAddress>,transport: freezed == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as DeviceTransport?,address: freezed == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String?,port: freezed == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceNetworkInfo].
extension DeviceNetworkInfoPatterns on DeviceNetworkInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceNetworkInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceNetworkInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceNetworkInfo value)  $default,){
final _that = this;
switch (_that) {
case _DeviceNetworkInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceNetworkInfo value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceNetworkInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<DeviceNetworkAddress> addresses,  DeviceTransport? transport,  String? address,  int? port)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceNetworkInfo() when $default != null:
return $default(_that.addresses,_that.transport,_that.address,_that.port);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<DeviceNetworkAddress> addresses,  DeviceTransport? transport,  String? address,  int? port)  $default,) {final _that = this;
switch (_that) {
case _DeviceNetworkInfo():
return $default(_that.addresses,_that.transport,_that.address,_that.port);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<DeviceNetworkAddress> addresses,  DeviceTransport? transport,  String? address,  int? port)?  $default,) {final _that = this;
switch (_that) {
case _DeviceNetworkInfo() when $default != null:
return $default(_that.addresses,_that.transport,_that.address,_that.port);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceNetworkInfo implements DeviceNetworkInfo {
  const _DeviceNetworkInfo({ List<DeviceNetworkAddress> addresses = const [], this.transport, this.address, this.port}): _addresses = addresses;
  

 final  List<DeviceNetworkAddress> _addresses;
@override@JsonKey() List<DeviceNetworkAddress> get addresses {
  if (_addresses is EqualUnmodifiableListView) return _addresses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_addresses);
}

@override final  DeviceTransport? transport;
@override final  String? address;
@override final  int? port;

/// Create a copy of DeviceNetworkInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceNetworkInfoCopyWith<_DeviceNetworkInfo> get copyWith => __$DeviceNetworkInfoCopyWithImpl<_DeviceNetworkInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceNetworkInfo&&const DeepCollectionEquality().equals(other.addresses, _addresses)&&(identical(other.transport, transport) || other.transport == transport)&&(identical(other.address, address) || other.address == address)&&(identical(other.port, port) || other.port == port));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_addresses),transport,address,port);
}

@override
String toString() {
    return 'DeviceNetworkInfo(addresses: $addresses, transport: $transport, address: $address, port: $port)';
}


}

/// @nodoc
abstract mixin class _$DeviceNetworkInfoCopyWith<$Res> implements $DeviceNetworkInfoCopyWith<$Res> {
  factory _$DeviceNetworkInfoCopyWith(_DeviceNetworkInfo value, $Res Function(_DeviceNetworkInfo) _then) = __$DeviceNetworkInfoCopyWithImpl;
@override @useResult
$Res call({
 List<DeviceNetworkAddress> addresses, DeviceTransport? transport, String? address, int? port
});




}
/// @nodoc
class __$DeviceNetworkInfoCopyWithImpl<$Res>
    implements _$DeviceNetworkInfoCopyWith<$Res> {
  __$DeviceNetworkInfoCopyWithImpl(this._self, this._then);

  final _DeviceNetworkInfo _self;
  final $Res Function(_DeviceNetworkInfo) _then;

/// Create a copy of DeviceNetworkInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? addresses = null,Object? transport = freezed,Object? address = freezed,Object? port = freezed,}) {
  return _then(_DeviceNetworkInfo(
addresses: null == addresses ? _self._addresses : addresses // ignore: cast_nullable_to_non_nullable
as List<DeviceNetworkAddress>,transport: freezed == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as DeviceTransport?,address: freezed == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String?,port: freezed == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
