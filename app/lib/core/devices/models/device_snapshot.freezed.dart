// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DeviceSnapshot {

 String get id; String? get name; String? get address; int? get port;@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) DeviceTransport? get transport;@JsonKey(unknownEnumValue: DeviceConnectionStatus.unknown) DeviceConnectionStatus get status;@JsonKey(includeIfNull: false) String? get connectionId; String? get guid; String? get serial; String? get model; String? get androidVersion; int? get apiLevel; int? get battery; bool? get charging; int? get batteryUpdatedAt; int? get lastSeen; String? get reason; bool get autoReconnect; bool get observationWanted;
/// Create a copy of DeviceSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceSnapshotCopyWith<DeviceSnapshot> get copyWith => _$DeviceSnapshotCopyWithImpl<DeviceSnapshot>(this as DeviceSnapshot, _$identity);

  /// Serializes this DeviceSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DeviceSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceSnapshot&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.address, _this.address) || other.address == _this.address)&&(identical(other.port, _this.port) || other.port == _this.port)&&(identical(other.transport, _this.transport) || other.transport == _this.transport)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.connectionId, _this.connectionId) || other.connectionId == _this.connectionId)&&(identical(other.guid, _this.guid) || other.guid == _this.guid)&&(identical(other.serial, _this.serial) || other.serial == _this.serial)&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.androidVersion, _this.androidVersion) || other.androidVersion == _this.androidVersion)&&(identical(other.apiLevel, _this.apiLevel) || other.apiLevel == _this.apiLevel)&&(identical(other.battery, _this.battery) || other.battery == _this.battery)&&(identical(other.charging, _this.charging) || other.charging == _this.charging)&&(identical(other.batteryUpdatedAt, _this.batteryUpdatedAt) || other.batteryUpdatedAt == _this.batteryUpdatedAt)&&(identical(other.lastSeen, _this.lastSeen) || other.lastSeen == _this.lastSeen)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.autoReconnect, _this.autoReconnect) || other.autoReconnect == _this.autoReconnect)&&(identical(other.observationWanted, _this.observationWanted) || other.observationWanted == _this.observationWanted));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DeviceSnapshot;
  return Object.hashAll([runtimeType,_this.id,_this.name,_this.address,_this.port,_this.transport,_this.status,_this.connectionId,_this.guid,_this.serial,_this.model,_this.androidVersion,_this.apiLevel,_this.battery,_this.charging,_this.batteryUpdatedAt,_this.lastSeen,_this.reason,_this.autoReconnect,_this.observationWanted]);
}

@override
String toString() {
  final _this = this as DeviceSnapshot;
  return 'DeviceSnapshot(id: ${_this.id}, name: ${_this.name}, address: ${_this.address}, port: ${_this.port}, transport: ${_this.transport}, status: ${_this.status}, connectionId: ${_this.connectionId}, guid: ${_this.guid}, serial: ${_this.serial}, model: ${_this.model}, androidVersion: ${_this.androidVersion}, apiLevel: ${_this.apiLevel}, battery: ${_this.battery}, charging: ${_this.charging}, batteryUpdatedAt: ${_this.batteryUpdatedAt}, lastSeen: ${_this.lastSeen}, reason: ${_this.reason}, autoReconnect: ${_this.autoReconnect}, observationWanted: ${_this.observationWanted})';
}


}

/// @nodoc
abstract mixin class $DeviceSnapshotCopyWith<$Res>  {
  factory $DeviceSnapshotCopyWith(DeviceSnapshot value, $Res Function(DeviceSnapshot) _then) = _$DeviceSnapshotCopyWithImpl;
@useResult
$Res call({
 String id, String? name, String? address, int? port,@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) DeviceTransport? transport,@JsonKey(unknownEnumValue: DeviceConnectionStatus.unknown) DeviceConnectionStatus status,@JsonKey(includeIfNull: false) String? connectionId, String? guid, String? serial, String? model, String? androidVersion, int? apiLevel, int? battery, bool? charging, int? batteryUpdatedAt, int? lastSeen, String? reason, bool autoReconnect, bool observationWanted
});




}
/// @nodoc
class _$DeviceSnapshotCopyWithImpl<$Res>
    implements $DeviceSnapshotCopyWith<$Res> {
  _$DeviceSnapshotCopyWithImpl(this._self, this._then);

  final DeviceSnapshot _self;
  final $Res Function(DeviceSnapshot) _then;

/// Create a copy of DeviceSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = freezed,Object? address = freezed,Object? port = freezed,Object? transport = freezed,Object? status = null,Object? connectionId = freezed,Object? guid = freezed,Object? serial = freezed,Object? model = freezed,Object? androidVersion = freezed,Object? apiLevel = freezed,Object? battery = freezed,Object? charging = freezed,Object? batteryUpdatedAt = freezed,Object? lastSeen = freezed,Object? reason = freezed,Object? autoReconnect = null,Object? observationWanted = null,}) {
  return _then(DeviceSnapshot(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,address: freezed == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String?,port: freezed == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int?,transport: freezed == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as DeviceTransport?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceConnectionStatus,connectionId: freezed == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String?,guid: freezed == guid ? _self.guid : guid // ignore: cast_nullable_to_non_nullable
as String?,serial: freezed == serial ? _self.serial : serial // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,androidVersion: freezed == androidVersion ? _self.androidVersion : androidVersion // ignore: cast_nullable_to_non_nullable
as String?,apiLevel: freezed == apiLevel ? _self.apiLevel : apiLevel // ignore: cast_nullable_to_non_nullable
as int?,battery: freezed == battery ? _self.battery : battery // ignore: cast_nullable_to_non_nullable
as int?,charging: freezed == charging ? _self.charging : charging // ignore: cast_nullable_to_non_nullable
as bool?,batteryUpdatedAt: freezed == batteryUpdatedAt ? _self.batteryUpdatedAt : batteryUpdatedAt // ignore: cast_nullable_to_non_nullable
as int?,lastSeen: freezed == lastSeen ? _self.lastSeen : lastSeen // ignore: cast_nullable_to_non_nullable
as int?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,autoReconnect: null == autoReconnect ? _self.autoReconnect : autoReconnect // ignore: cast_nullable_to_non_nullable
as bool,observationWanted: null == observationWanted ? _self.observationWanted : observationWanted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceSnapshot].
extension DeviceSnapshotPatterns on DeviceSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _DeviceSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? name,  String? address,  int? port, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  DeviceTransport? transport, @JsonKey(unknownEnumValue: DeviceConnectionStatus.unknown)  DeviceConnectionStatus status, @JsonKey(includeIfNull: false)  String? connectionId,  String? guid,  String? serial,  String? model,  String? androidVersion,  int? apiLevel,  int? battery,  bool? charging,  int? batteryUpdatedAt,  int? lastSeen,  String? reason,  bool autoReconnect,  bool observationWanted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceSnapshot() when $default != null:
return $default(_that.id,_that.name,_that.address,_that.port,_that.transport,_that.status,_that.connectionId,_that.guid,_that.serial,_that.model,_that.androidVersion,_that.apiLevel,_that.battery,_that.charging,_that.batteryUpdatedAt,_that.lastSeen,_that.reason,_that.autoReconnect,_that.observationWanted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? name,  String? address,  int? port, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  DeviceTransport? transport, @JsonKey(unknownEnumValue: DeviceConnectionStatus.unknown)  DeviceConnectionStatus status, @JsonKey(includeIfNull: false)  String? connectionId,  String? guid,  String? serial,  String? model,  String? androidVersion,  int? apiLevel,  int? battery,  bool? charging,  int? batteryUpdatedAt,  int? lastSeen,  String? reason,  bool autoReconnect,  bool observationWanted)  $default,) {final _that = this;
switch (_that) {
case _DeviceSnapshot():
return $default(_that.id,_that.name,_that.address,_that.port,_that.transport,_that.status,_that.connectionId,_that.guid,_that.serial,_that.model,_that.androidVersion,_that.apiLevel,_that.battery,_that.charging,_that.batteryUpdatedAt,_that.lastSeen,_that.reason,_that.autoReconnect,_that.observationWanted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? name,  String? address,  int? port, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  DeviceTransport? transport, @JsonKey(unknownEnumValue: DeviceConnectionStatus.unknown)  DeviceConnectionStatus status, @JsonKey(includeIfNull: false)  String? connectionId,  String? guid,  String? serial,  String? model,  String? androidVersion,  int? apiLevel,  int? battery,  bool? charging,  int? batteryUpdatedAt,  int? lastSeen,  String? reason,  bool autoReconnect,  bool observationWanted)?  $default,) {final _that = this;
switch (_that) {
case _DeviceSnapshot() when $default != null:
return $default(_that.id,_that.name,_that.address,_that.port,_that.transport,_that.status,_that.connectionId,_that.guid,_that.serial,_that.model,_that.androidVersion,_that.apiLevel,_that.battery,_that.charging,_that.batteryUpdatedAt,_that.lastSeen,_that.reason,_that.autoReconnect,_that.observationWanted);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(checked: true)
class _DeviceSnapshot implements DeviceSnapshot {
  const _DeviceSnapshot({required this.id, this.name, this.address, this.port, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) this.transport, @JsonKey(unknownEnumValue: DeviceConnectionStatus.unknown) this.status = DeviceConnectionStatus.unknown, @JsonKey(includeIfNull: false) this.connectionId, this.guid, this.serial, this.model, this.androidVersion, this.apiLevel, this.battery, this.charging, this.batteryUpdatedAt, this.lastSeen, this.reason, this.autoReconnect = false, this.observationWanted = true});
  factory _DeviceSnapshot.fromJson(Map<String, dynamic> json) => _$DeviceSnapshotFromJson(json);

@override final  String id;
@override final  String? name;
@override final  String? address;
@override final  int? port;
@override@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) final  DeviceTransport? transport;
@override@JsonKey(unknownEnumValue: DeviceConnectionStatus.unknown) final  DeviceConnectionStatus status;
@override@JsonKey(includeIfNull: false) final  String? connectionId;
@override final  String? guid;
@override final  String? serial;
@override final  String? model;
@override final  String? androidVersion;
@override final  int? apiLevel;
@override final  int? battery;
@override final  bool? charging;
@override final  int? batteryUpdatedAt;
@override final  int? lastSeen;
@override final  String? reason;
@override@JsonKey() final  bool autoReconnect;
@override@JsonKey() final  bool observationWanted;

/// Create a copy of DeviceSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceSnapshotCopyWith<_DeviceSnapshot> get copyWith => __$DeviceSnapshotCopyWithImpl<_DeviceSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DeviceSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceSnapshot&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.address, address) || other.address == address)&&(identical(other.port, port) || other.port == port)&&(identical(other.transport, transport) || other.transport == transport)&&(identical(other.status, status) || other.status == status)&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId)&&(identical(other.guid, guid) || other.guid == guid)&&(identical(other.serial, serial) || other.serial == serial)&&(identical(other.model, model) || other.model == model)&&(identical(other.androidVersion, androidVersion) || other.androidVersion == androidVersion)&&(identical(other.apiLevel, apiLevel) || other.apiLevel == apiLevel)&&(identical(other.battery, battery) || other.battery == battery)&&(identical(other.charging, charging) || other.charging == charging)&&(identical(other.batteryUpdatedAt, batteryUpdatedAt) || other.batteryUpdatedAt == batteryUpdatedAt)&&(identical(other.lastSeen, lastSeen) || other.lastSeen == lastSeen)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.autoReconnect, autoReconnect) || other.autoReconnect == autoReconnect)&&(identical(other.observationWanted, observationWanted) || other.observationWanted == observationWanted));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,name,address,port,transport,status,connectionId,guid,serial,model,androidVersion,apiLevel,battery,charging,batteryUpdatedAt,lastSeen,reason,autoReconnect,observationWanted]);
}

@override
String toString() {
    return 'DeviceSnapshot(id: $id, name: $name, address: $address, port: $port, transport: $transport, status: $status, connectionId: $connectionId, guid: $guid, serial: $serial, model: $model, androidVersion: $androidVersion, apiLevel: $apiLevel, battery: $battery, charging: $charging, batteryUpdatedAt: $batteryUpdatedAt, lastSeen: $lastSeen, reason: $reason, autoReconnect: $autoReconnect, observationWanted: $observationWanted)';
}


}

/// @nodoc
abstract mixin class _$DeviceSnapshotCopyWith<$Res> implements $DeviceSnapshotCopyWith<$Res> {
  factory _$DeviceSnapshotCopyWith(_DeviceSnapshot value, $Res Function(_DeviceSnapshot) _then) = __$DeviceSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String id, String? name, String? address, int? port,@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) DeviceTransport? transport,@JsonKey(unknownEnumValue: DeviceConnectionStatus.unknown) DeviceConnectionStatus status,@JsonKey(includeIfNull: false) String? connectionId, String? guid, String? serial, String? model, String? androidVersion, int? apiLevel, int? battery, bool? charging, int? batteryUpdatedAt, int? lastSeen, String? reason, bool autoReconnect, bool observationWanted
});




}
/// @nodoc
class __$DeviceSnapshotCopyWithImpl<$Res>
    implements _$DeviceSnapshotCopyWith<$Res> {
  __$DeviceSnapshotCopyWithImpl(this._self, this._then);

  final _DeviceSnapshot _self;
  final $Res Function(_DeviceSnapshot) _then;

/// Create a copy of DeviceSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = freezed,Object? address = freezed,Object? port = freezed,Object? transport = freezed,Object? status = null,Object? connectionId = freezed,Object? guid = freezed,Object? serial = freezed,Object? model = freezed,Object? androidVersion = freezed,Object? apiLevel = freezed,Object? battery = freezed,Object? charging = freezed,Object? batteryUpdatedAt = freezed,Object? lastSeen = freezed,Object? reason = freezed,Object? autoReconnect = null,Object? observationWanted = null,}) {
  return _then(_DeviceSnapshot(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,address: freezed == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String?,port: freezed == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int?,transport: freezed == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as DeviceTransport?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceConnectionStatus,connectionId: freezed == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String?,guid: freezed == guid ? _self.guid : guid // ignore: cast_nullable_to_non_nullable
as String?,serial: freezed == serial ? _self.serial : serial // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,androidVersion: freezed == androidVersion ? _self.androidVersion : androidVersion // ignore: cast_nullable_to_non_nullable
as String?,apiLevel: freezed == apiLevel ? _self.apiLevel : apiLevel // ignore: cast_nullable_to_non_nullable
as int?,battery: freezed == battery ? _self.battery : battery // ignore: cast_nullable_to_non_nullable
as int?,charging: freezed == charging ? _self.charging : charging // ignore: cast_nullable_to_non_nullable
as bool?,batteryUpdatedAt: freezed == batteryUpdatedAt ? _self.batteryUpdatedAt : batteryUpdatedAt // ignore: cast_nullable_to_non_nullable
as int?,lastSeen: freezed == lastSeen ? _self.lastSeen : lastSeen // ignore: cast_nullable_to_non_nullable
as int?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,autoReconnect: null == autoReconnect ? _self.autoReconnect : autoReconnect // ignore: cast_nullable_to_non_nullable
as bool,observationWanted: null == observationWanted ? _self.observationWanted : observationWanted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
