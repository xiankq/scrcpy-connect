// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_battery.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DeviceBattery {

 int? get level; DeviceBatteryStatus get status; int? get health; double? get temperatureC; double? get voltageMv;
/// Create a copy of DeviceBattery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceBatteryCopyWith<DeviceBattery> get copyWith => _$DeviceBatteryCopyWithImpl<DeviceBattery>(this as DeviceBattery, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceBattery;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceBattery&&(identical(other.level, _this.level) || other.level == _this.level)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.health, _this.health) || other.health == _this.health)&&(identical(other.temperatureC, _this.temperatureC) || other.temperatureC == _this.temperatureC)&&(identical(other.voltageMv, _this.voltageMv) || other.voltageMv == _this.voltageMv));
}


@override
int get hashCode {
  final _this = this as DeviceBattery;
  return Object.hash(runtimeType,_this.level,_this.status,_this.health,_this.temperatureC,_this.voltageMv);
}

@override
String toString() {
  final _this = this as DeviceBattery;
  return 'DeviceBattery(level: ${_this.level}, status: ${_this.status}, health: ${_this.health}, temperatureC: ${_this.temperatureC}, voltageMv: ${_this.voltageMv})';
}


}

/// @nodoc
abstract mixin class $DeviceBatteryCopyWith<$Res>  {
  factory $DeviceBatteryCopyWith(DeviceBattery value, $Res Function(DeviceBattery) _then) = _$DeviceBatteryCopyWithImpl;
@useResult
$Res call({
 int? level, DeviceBatteryStatus status, int? health, double? temperatureC, double? voltageMv
});




}
/// @nodoc
class _$DeviceBatteryCopyWithImpl<$Res>
    implements $DeviceBatteryCopyWith<$Res> {
  _$DeviceBatteryCopyWithImpl(this._self, this._then);

  final DeviceBattery _self;
  final $Res Function(DeviceBattery) _then;

/// Create a copy of DeviceBattery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? level = freezed,Object? status = null,Object? health = freezed,Object? temperatureC = freezed,Object? voltageMv = freezed,}) {
  return _then(DeviceBattery(
level: freezed == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as int?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceBatteryStatus,health: freezed == health ? _self.health : health // ignore: cast_nullable_to_non_nullable
as int?,temperatureC: freezed == temperatureC ? _self.temperatureC : temperatureC // ignore: cast_nullable_to_non_nullable
as double?,voltageMv: freezed == voltageMv ? _self.voltageMv : voltageMv // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceBattery].
extension DeviceBatteryPatterns on DeviceBattery {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceBattery value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceBattery() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceBattery value)  $default,){
final _that = this;
switch (_that) {
case _DeviceBattery():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceBattery value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceBattery() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? level,  DeviceBatteryStatus status,  int? health,  double? temperatureC,  double? voltageMv)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceBattery() when $default != null:
return $default(_that.level,_that.status,_that.health,_that.temperatureC,_that.voltageMv);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? level,  DeviceBatteryStatus status,  int? health,  double? temperatureC,  double? voltageMv)  $default,) {final _that = this;
switch (_that) {
case _DeviceBattery():
return $default(_that.level,_that.status,_that.health,_that.temperatureC,_that.voltageMv);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? level,  DeviceBatteryStatus status,  int? health,  double? temperatureC,  double? voltageMv)?  $default,) {final _that = this;
switch (_that) {
case _DeviceBattery() when $default != null:
return $default(_that.level,_that.status,_that.health,_that.temperatureC,_that.voltageMv);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceBattery implements DeviceBattery {
  const _DeviceBattery({this.level, this.status = DeviceBatteryStatus.unknown, this.health, this.temperatureC, this.voltageMv});
  

@override final  int? level;
@override@JsonKey() final  DeviceBatteryStatus status;
@override final  int? health;
@override final  double? temperatureC;
@override final  double? voltageMv;

/// Create a copy of DeviceBattery
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceBatteryCopyWith<_DeviceBattery> get copyWith => __$DeviceBatteryCopyWithImpl<_DeviceBattery>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceBattery&&(identical(other.level, level) || other.level == level)&&(identical(other.status, status) || other.status == status)&&(identical(other.health, health) || other.health == health)&&(identical(other.temperatureC, temperatureC) || other.temperatureC == temperatureC)&&(identical(other.voltageMv, voltageMv) || other.voltageMv == voltageMv));
}


@override
int get hashCode {
    return Object.hash(runtimeType,level,status,health,temperatureC,voltageMv);
}

@override
String toString() {
    return 'DeviceBattery(level: $level, status: $status, health: $health, temperatureC: $temperatureC, voltageMv: $voltageMv)';
}


}

/// @nodoc
abstract mixin class _$DeviceBatteryCopyWith<$Res> implements $DeviceBatteryCopyWith<$Res> {
  factory _$DeviceBatteryCopyWith(_DeviceBattery value, $Res Function(_DeviceBattery) _then) = __$DeviceBatteryCopyWithImpl;
@override @useResult
$Res call({
 int? level, DeviceBatteryStatus status, int? health, double? temperatureC, double? voltageMv
});




}
/// @nodoc
class __$DeviceBatteryCopyWithImpl<$Res>
    implements _$DeviceBatteryCopyWith<$Res> {
  __$DeviceBatteryCopyWithImpl(this._self, this._then);

  final _DeviceBattery _self;
  final $Res Function(_DeviceBattery) _then;

/// Create a copy of DeviceBattery
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? level = freezed,Object? status = null,Object? health = freezed,Object? temperatureC = freezed,Object? voltageMv = freezed,}) {
  return _then(_DeviceBattery(
level: freezed == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as int?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceBatteryStatus,health: freezed == health ? _self.health : health // ignore: cast_nullable_to_non_nullable
as int?,temperatureC: freezed == temperatureC ? _self.temperatureC : temperatureC // ignore: cast_nullable_to_non_nullable
as double?,voltageMv: freezed == voltageMv ? _self.voltageMv : voltageMv // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

// dart format on
