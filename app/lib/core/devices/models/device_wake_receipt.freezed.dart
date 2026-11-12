// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_wake_receipt.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DeviceWakeReceipt {

 String get deviceId; String get connectionId; DeviceWakeEvidence get evidence;
/// Create a copy of DeviceWakeReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceWakeReceiptCopyWith<DeviceWakeReceipt> get copyWith => _$DeviceWakeReceiptCopyWithImpl<DeviceWakeReceipt>(this as DeviceWakeReceipt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceWakeReceipt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceWakeReceipt&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.connectionId, _this.connectionId) || other.connectionId == _this.connectionId)&&(identical(other.evidence, _this.evidence) || other.evidence == _this.evidence));
}


@override
int get hashCode {
  final _this = this as DeviceWakeReceipt;
  return Object.hash(runtimeType,_this.deviceId,_this.connectionId,_this.evidence);
}

@override
String toString() {
  final _this = this as DeviceWakeReceipt;
  return 'DeviceWakeReceipt(deviceId: ${_this.deviceId}, connectionId: ${_this.connectionId}, evidence: ${_this.evidence})';
}


}

/// @nodoc
abstract mixin class $DeviceWakeReceiptCopyWith<$Res>  {
  factory $DeviceWakeReceiptCopyWith(DeviceWakeReceipt value, $Res Function(DeviceWakeReceipt) _then) = _$DeviceWakeReceiptCopyWithImpl;
@useResult
$Res call({
 String deviceId, String connectionId, DeviceWakeEvidence evidence
});




}
/// @nodoc
class _$DeviceWakeReceiptCopyWithImpl<$Res>
    implements $DeviceWakeReceiptCopyWith<$Res> {
  _$DeviceWakeReceiptCopyWithImpl(this._self, this._then);

  final DeviceWakeReceipt _self;
  final $Res Function(DeviceWakeReceipt) _then;

/// Create a copy of DeviceWakeReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? connectionId = null,Object? evidence = null,}) {
  return _then(DeviceWakeReceipt(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,connectionId: null == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String,evidence: null == evidence ? _self.evidence : evidence // ignore: cast_nullable_to_non_nullable
as DeviceWakeEvidence,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceWakeReceipt].
extension DeviceWakeReceiptPatterns on DeviceWakeReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceWakeReceipt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceWakeReceipt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceWakeReceipt value)  $default,){
final _that = this;
switch (_that) {
case _DeviceWakeReceipt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceWakeReceipt value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceWakeReceipt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  String connectionId,  DeviceWakeEvidence evidence)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceWakeReceipt() when $default != null:
return $default(_that.deviceId,_that.connectionId,_that.evidence);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  String connectionId,  DeviceWakeEvidence evidence)  $default,) {final _that = this;
switch (_that) {
case _DeviceWakeReceipt():
return $default(_that.deviceId,_that.connectionId,_that.evidence);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  String connectionId,  DeviceWakeEvidence evidence)?  $default,) {final _that = this;
switch (_that) {
case _DeviceWakeReceipt() when $default != null:
return $default(_that.deviceId,_that.connectionId,_that.evidence);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceWakeReceipt implements DeviceWakeReceipt {
  const _DeviceWakeReceipt({required this.deviceId, required this.connectionId, required this.evidence});
  

@override final  String deviceId;
@override final  String connectionId;
@override final  DeviceWakeEvidence evidence;

/// Create a copy of DeviceWakeReceipt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceWakeReceiptCopyWith<_DeviceWakeReceipt> get copyWith => __$DeviceWakeReceiptCopyWithImpl<_DeviceWakeReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceWakeReceipt&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId)&&(identical(other.evidence, evidence) || other.evidence == evidence));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,connectionId,evidence);
}

@override
String toString() {
    return 'DeviceWakeReceipt(deviceId: $deviceId, connectionId: $connectionId, evidence: $evidence)';
}


}

/// @nodoc
abstract mixin class _$DeviceWakeReceiptCopyWith<$Res> implements $DeviceWakeReceiptCopyWith<$Res> {
  factory _$DeviceWakeReceiptCopyWith(_DeviceWakeReceipt value, $Res Function(_DeviceWakeReceipt) _then) = __$DeviceWakeReceiptCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, String connectionId, DeviceWakeEvidence evidence
});




}
/// @nodoc
class __$DeviceWakeReceiptCopyWithImpl<$Res>
    implements _$DeviceWakeReceiptCopyWith<$Res> {
  __$DeviceWakeReceiptCopyWithImpl(this._self, this._then);

  final _DeviceWakeReceipt _self;
  final $Res Function(_DeviceWakeReceipt) _then;

/// Create a copy of DeviceWakeReceipt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? connectionId = null,Object? evidence = null,}) {
  return _then(_DeviceWakeReceipt(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,connectionId: null == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String,evidence: null == evidence ? _self.evidence : evidence // ignore: cast_nullable_to_non_nullable
as DeviceWakeEvidence,
  ));
}


}

// dart format on
