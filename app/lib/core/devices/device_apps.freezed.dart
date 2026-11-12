// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_apps.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DeviceApp {

 String get packageName; String get name; bool get system; int? get taskId; int? get userId;
/// Create a copy of DeviceApp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceAppCopyWith<DeviceApp> get copyWith => _$DeviceAppCopyWithImpl<DeviceApp>(this as DeviceApp, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceApp;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceApp&&(identical(other.packageName, _this.packageName) || other.packageName == _this.packageName)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.system, _this.system) || other.system == _this.system)&&(identical(other.taskId, _this.taskId) || other.taskId == _this.taskId)&&(identical(other.userId, _this.userId) || other.userId == _this.userId));
}


@override
int get hashCode {
  final _this = this as DeviceApp;
  return Object.hash(runtimeType,_this.packageName,_this.name,_this.system,_this.taskId,_this.userId);
}

@override
String toString() {
  final _this = this as DeviceApp;
  return 'DeviceApp(packageName: ${_this.packageName}, name: ${_this.name}, system: ${_this.system}, taskId: ${_this.taskId}, userId: ${_this.userId})';
}


}

/// @nodoc
abstract mixin class $DeviceAppCopyWith<$Res>  {
  factory $DeviceAppCopyWith(DeviceApp value, $Res Function(DeviceApp) _then) = _$DeviceAppCopyWithImpl;
@useResult
$Res call({
 String packageName, String name, bool system, int? taskId, int? userId
});




}
/// @nodoc
class _$DeviceAppCopyWithImpl<$Res>
    implements $DeviceAppCopyWith<$Res> {
  _$DeviceAppCopyWithImpl(this._self, this._then);

  final DeviceApp _self;
  final $Res Function(DeviceApp) _then;

/// Create a copy of DeviceApp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? packageName = null,Object? name = null,Object? system = null,Object? taskId = freezed,Object? userId = freezed,}) {
  return _then(DeviceApp(
packageName: null == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,system: null == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as bool,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as int?,userId: freezed == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceApp].
extension DeviceAppPatterns on DeviceApp {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceApp value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceApp() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceApp value)  $default,){
final _that = this;
switch (_that) {
case _DeviceApp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceApp value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceApp() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String packageName,  String name,  bool system,  int? taskId,  int? userId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceApp() when $default != null:
return $default(_that.packageName,_that.name,_that.system,_that.taskId,_that.userId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String packageName,  String name,  bool system,  int? taskId,  int? userId)  $default,) {final _that = this;
switch (_that) {
case _DeviceApp():
return $default(_that.packageName,_that.name,_that.system,_that.taskId,_that.userId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String packageName,  String name,  bool system,  int? taskId,  int? userId)?  $default,) {final _that = this;
switch (_that) {
case _DeviceApp() when $default != null:
return $default(_that.packageName,_that.name,_that.system,_that.taskId,_that.userId);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceApp implements DeviceApp {
  const _DeviceApp({required this.packageName, required this.name, this.system = false, this.taskId, this.userId});
  

@override final  String packageName;
@override final  String name;
@override@JsonKey() final  bool system;
@override final  int? taskId;
@override final  int? userId;

/// Create a copy of DeviceApp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceAppCopyWith<_DeviceApp> get copyWith => __$DeviceAppCopyWithImpl<_DeviceApp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceApp&&(identical(other.packageName, packageName) || other.packageName == packageName)&&(identical(other.name, name) || other.name == name)&&(identical(other.system, system) || other.system == system)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.userId, userId) || other.userId == userId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,packageName,name,system,taskId,userId);
}

@override
String toString() {
    return 'DeviceApp(packageName: $packageName, name: $name, system: $system, taskId: $taskId, userId: $userId)';
}


}

/// @nodoc
abstract mixin class _$DeviceAppCopyWith<$Res> implements $DeviceAppCopyWith<$Res> {
  factory _$DeviceAppCopyWith(_DeviceApp value, $Res Function(_DeviceApp) _then) = __$DeviceAppCopyWithImpl;
@override @useResult
$Res call({
 String packageName, String name, bool system, int? taskId, int? userId
});




}
/// @nodoc
class __$DeviceAppCopyWithImpl<$Res>
    implements _$DeviceAppCopyWith<$Res> {
  __$DeviceAppCopyWithImpl(this._self, this._then);

  final _DeviceApp _self;
  final $Res Function(_DeviceApp) _then;

/// Create a copy of DeviceApp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? packageName = null,Object? name = null,Object? system = null,Object? taskId = freezed,Object? userId = freezed,}) {
  return _then(_DeviceApp(
packageName: null == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,system: null == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as bool,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as int?,userId: freezed == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$RunningDeviceApps {

 String get deviceId; List<DeviceApp> get apps; String? get connectionId; int get userId;
/// Create a copy of RunningDeviceApps
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RunningDeviceAppsCopyWith<RunningDeviceApps> get copyWith => _$RunningDeviceAppsCopyWithImpl<RunningDeviceApps>(this as RunningDeviceApps, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RunningDeviceApps;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RunningDeviceApps&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&const DeepCollectionEquality().equals(other.apps, _this.apps)&&(identical(other.connectionId, _this.connectionId) || other.connectionId == _this.connectionId)&&(identical(other.userId, _this.userId) || other.userId == _this.userId));
}


@override
int get hashCode {
  final _this = this as RunningDeviceApps;
  return Object.hash(runtimeType,_this.deviceId,const DeepCollectionEquality().hash(_this.apps),_this.connectionId,_this.userId);
}

@override
String toString() {
  final _this = this as RunningDeviceApps;
  return 'RunningDeviceApps(deviceId: ${_this.deviceId}, apps: ${_this.apps}, connectionId: ${_this.connectionId}, userId: ${_this.userId})';
}


}

/// @nodoc
abstract mixin class $RunningDeviceAppsCopyWith<$Res>  {
  factory $RunningDeviceAppsCopyWith(RunningDeviceApps value, $Res Function(RunningDeviceApps) _then) = _$RunningDeviceAppsCopyWithImpl;
@useResult
$Res call({
 String deviceId, List<DeviceApp> apps, String? connectionId, int userId
});




}
/// @nodoc
class _$RunningDeviceAppsCopyWithImpl<$Res>
    implements $RunningDeviceAppsCopyWith<$Res> {
  _$RunningDeviceAppsCopyWithImpl(this._self, this._then);

  final RunningDeviceApps _self;
  final $Res Function(RunningDeviceApps) _then;

/// Create a copy of RunningDeviceApps
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? apps = null,Object? connectionId = freezed,Object? userId = null,}) {
  return _then(RunningDeviceApps(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,apps: null == apps ? _self.apps : apps // ignore: cast_nullable_to_non_nullable
as List<DeviceApp>,connectionId: freezed == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String?,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [RunningDeviceApps].
extension RunningDeviceAppsPatterns on RunningDeviceApps {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RunningDeviceApps value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RunningDeviceApps() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RunningDeviceApps value)  $default,){
final _that = this;
switch (_that) {
case _RunningDeviceApps():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RunningDeviceApps value)?  $default,){
final _that = this;
switch (_that) {
case _RunningDeviceApps() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  List<DeviceApp> apps,  String? connectionId,  int userId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RunningDeviceApps() when $default != null:
return $default(_that.deviceId,_that.apps,_that.connectionId,_that.userId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  List<DeviceApp> apps,  String? connectionId,  int userId)  $default,) {final _that = this;
switch (_that) {
case _RunningDeviceApps():
return $default(_that.deviceId,_that.apps,_that.connectionId,_that.userId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  List<DeviceApp> apps,  String? connectionId,  int userId)?  $default,) {final _that = this;
switch (_that) {
case _RunningDeviceApps() when $default != null:
return $default(_that.deviceId,_that.apps,_that.connectionId,_that.userId);case _:
  return null;

}
}

}

/// @nodoc


class _RunningDeviceApps implements RunningDeviceApps {
  const _RunningDeviceApps({required this.deviceId, required  List<DeviceApp> apps, this.connectionId, required this.userId}): _apps = apps;
  

@override final  String deviceId;
 final  List<DeviceApp> _apps;
@override List<DeviceApp> get apps {
  if (_apps is EqualUnmodifiableListView) return _apps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_apps);
}

@override final  String? connectionId;
@override final  int userId;

/// Create a copy of RunningDeviceApps
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RunningDeviceAppsCopyWith<_RunningDeviceApps> get copyWith => __$RunningDeviceAppsCopyWithImpl<_RunningDeviceApps>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RunningDeviceApps&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&const DeepCollectionEquality().equals(other.apps, _apps)&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId)&&(identical(other.userId, userId) || other.userId == userId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,const DeepCollectionEquality().hash(_apps),connectionId,userId);
}

@override
String toString() {
    return 'RunningDeviceApps(deviceId: $deviceId, apps: $apps, connectionId: $connectionId, userId: $userId)';
}


}

/// @nodoc
abstract mixin class _$RunningDeviceAppsCopyWith<$Res> implements $RunningDeviceAppsCopyWith<$Res> {
  factory _$RunningDeviceAppsCopyWith(_RunningDeviceApps value, $Res Function(_RunningDeviceApps) _then) = __$RunningDeviceAppsCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, List<DeviceApp> apps, String? connectionId, int userId
});




}
/// @nodoc
class __$RunningDeviceAppsCopyWithImpl<$Res>
    implements _$RunningDeviceAppsCopyWith<$Res> {
  __$RunningDeviceAppsCopyWithImpl(this._self, this._then);

  final _RunningDeviceApps _self;
  final $Res Function(_RunningDeviceApps) _then;

/// Create a copy of RunningDeviceApps
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? apps = null,Object? connectionId = freezed,Object? userId = null,}) {
  return _then(_RunningDeviceApps(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,apps: null == apps ? _self._apps : apps // ignore: cast_nullable_to_non_nullable
as List<DeviceApp>,connectionId: freezed == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String?,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
