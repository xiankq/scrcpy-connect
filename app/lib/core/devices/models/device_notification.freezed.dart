// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_notification.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DeviceNotification {

 String get id; String? get key; String? get revision; String get packageName; String get appName; String get title; String get body; int? get userId; int? get postedAt; bool get groupSummary; bool? get canOpen; bool? get canDismiss;
/// Create a copy of DeviceNotification
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceNotificationCopyWith<DeviceNotification> get copyWith => _$DeviceNotificationCopyWithImpl<DeviceNotification>(this as DeviceNotification, _$identity);

  /// Serializes this DeviceNotification to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DeviceNotification;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceNotification&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.packageName, _this.packageName) || other.packageName == _this.packageName)&&(identical(other.appName, _this.appName) || other.appName == _this.appName)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.body, _this.body) || other.body == _this.body)&&(identical(other.userId, _this.userId) || other.userId == _this.userId)&&(identical(other.postedAt, _this.postedAt) || other.postedAt == _this.postedAt)&&(identical(other.groupSummary, _this.groupSummary) || other.groupSummary == _this.groupSummary)&&(identical(other.canOpen, _this.canOpen) || other.canOpen == _this.canOpen)&&(identical(other.canDismiss, _this.canDismiss) || other.canDismiss == _this.canDismiss));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DeviceNotification;
  return Object.hash(runtimeType,_this.id,_this.key,_this.revision,_this.packageName,_this.appName,_this.title,_this.body,_this.userId,_this.postedAt,_this.groupSummary,_this.canOpen,_this.canDismiss);
}

@override
String toString() {
  final _this = this as DeviceNotification;
  return 'DeviceNotification(id: ${_this.id}, key: ${_this.key}, revision: ${_this.revision}, packageName: ${_this.packageName}, appName: ${_this.appName}, title: ${_this.title}, body: ${_this.body}, userId: ${_this.userId}, postedAt: ${_this.postedAt}, groupSummary: ${_this.groupSummary}, canOpen: ${_this.canOpen}, canDismiss: ${_this.canDismiss})';
}


}

/// @nodoc
abstract mixin class $DeviceNotificationCopyWith<$Res>  {
  factory $DeviceNotificationCopyWith(DeviceNotification value, $Res Function(DeviceNotification) _then) = _$DeviceNotificationCopyWithImpl;
@useResult
$Res call({
 String id, String? key, String? revision, String packageName, String appName, String title, String body, int? userId, int? postedAt, bool groupSummary, bool? canOpen, bool? canDismiss
});




}
/// @nodoc
class _$DeviceNotificationCopyWithImpl<$Res>
    implements $DeviceNotificationCopyWith<$Res> {
  _$DeviceNotificationCopyWithImpl(this._self, this._then);

  final DeviceNotification _self;
  final $Res Function(DeviceNotification) _then;

/// Create a copy of DeviceNotification
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? key = freezed,Object? revision = freezed,Object? packageName = null,Object? appName = null,Object? title = null,Object? body = null,Object? userId = freezed,Object? postedAt = freezed,Object? groupSummary = null,Object? canOpen = freezed,Object? canDismiss = freezed,}) {
  return _then(DeviceNotification(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,revision: freezed == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as String?,packageName: null == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String,appName: null == appName ? _self.appName : appName // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,userId: freezed == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int?,postedAt: freezed == postedAt ? _self.postedAt : postedAt // ignore: cast_nullable_to_non_nullable
as int?,groupSummary: null == groupSummary ? _self.groupSummary : groupSummary // ignore: cast_nullable_to_non_nullable
as bool,canOpen: freezed == canOpen ? _self.canOpen : canOpen // ignore: cast_nullable_to_non_nullable
as bool?,canDismiss: freezed == canDismiss ? _self.canDismiss : canDismiss // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceNotification].
extension DeviceNotificationPatterns on DeviceNotification {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceNotification value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceNotification() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceNotification value)  $default,){
final _that = this;
switch (_that) {
case _DeviceNotification():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceNotification value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceNotification() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? key,  String? revision,  String packageName,  String appName,  String title,  String body,  int? userId,  int? postedAt,  bool groupSummary,  bool? canOpen,  bool? canDismiss)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceNotification() when $default != null:
return $default(_that.id,_that.key,_that.revision,_that.packageName,_that.appName,_that.title,_that.body,_that.userId,_that.postedAt,_that.groupSummary,_that.canOpen,_that.canDismiss);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? key,  String? revision,  String packageName,  String appName,  String title,  String body,  int? userId,  int? postedAt,  bool groupSummary,  bool? canOpen,  bool? canDismiss)  $default,) {final _that = this;
switch (_that) {
case _DeviceNotification():
return $default(_that.id,_that.key,_that.revision,_that.packageName,_that.appName,_that.title,_that.body,_that.userId,_that.postedAt,_that.groupSummary,_that.canOpen,_that.canDismiss);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? key,  String? revision,  String packageName,  String appName,  String title,  String body,  int? userId,  int? postedAt,  bool groupSummary,  bool? canOpen,  bool? canDismiss)?  $default,) {final _that = this;
switch (_that) {
case _DeviceNotification() when $default != null:
return $default(_that.id,_that.key,_that.revision,_that.packageName,_that.appName,_that.title,_that.body,_that.userId,_that.postedAt,_that.groupSummary,_that.canOpen,_that.canDismiss);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DeviceNotification implements DeviceNotification {
  const _DeviceNotification({required this.id, this.key, this.revision, this.packageName = '', this.appName = '', this.title = '', this.body = '', this.userId, this.postedAt, this.groupSummary = false, this.canOpen, this.canDismiss});
  factory _DeviceNotification.fromJson(Map<String, dynamic> json) => _$DeviceNotificationFromJson(json);

@override final  String id;
@override final  String? key;
@override final  String? revision;
@override@JsonKey() final  String packageName;
@override@JsonKey() final  String appName;
@override@JsonKey() final  String title;
@override@JsonKey() final  String body;
@override final  int? userId;
@override final  int? postedAt;
@override@JsonKey() final  bool groupSummary;
@override final  bool? canOpen;
@override final  bool? canDismiss;

/// Create a copy of DeviceNotification
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceNotificationCopyWith<_DeviceNotification> get copyWith => __$DeviceNotificationCopyWithImpl<_DeviceNotification>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DeviceNotificationToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceNotification&&(identical(other.id, id) || other.id == id)&&(identical(other.key, key) || other.key == key)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.packageName, packageName) || other.packageName == packageName)&&(identical(other.appName, appName) || other.appName == appName)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.postedAt, postedAt) || other.postedAt == postedAt)&&(identical(other.groupSummary, groupSummary) || other.groupSummary == groupSummary)&&(identical(other.canOpen, canOpen) || other.canOpen == canOpen)&&(identical(other.canDismiss, canDismiss) || other.canDismiss == canDismiss));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,key,revision,packageName,appName,title,body,userId,postedAt,groupSummary,canOpen,canDismiss);
}

@override
String toString() {
    return 'DeviceNotification(id: $id, key: $key, revision: $revision, packageName: $packageName, appName: $appName, title: $title, body: $body, userId: $userId, postedAt: $postedAt, groupSummary: $groupSummary, canOpen: $canOpen, canDismiss: $canDismiss)';
}


}

/// @nodoc
abstract mixin class _$DeviceNotificationCopyWith<$Res> implements $DeviceNotificationCopyWith<$Res> {
  factory _$DeviceNotificationCopyWith(_DeviceNotification value, $Res Function(_DeviceNotification) _then) = __$DeviceNotificationCopyWithImpl;
@override @useResult
$Res call({
 String id, String? key, String? revision, String packageName, String appName, String title, String body, int? userId, int? postedAt, bool groupSummary, bool? canOpen, bool? canDismiss
});




}
/// @nodoc
class __$DeviceNotificationCopyWithImpl<$Res>
    implements _$DeviceNotificationCopyWith<$Res> {
  __$DeviceNotificationCopyWithImpl(this._self, this._then);

  final _DeviceNotification _self;
  final $Res Function(_DeviceNotification) _then;

/// Create a copy of DeviceNotification
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? key = freezed,Object? revision = freezed,Object? packageName = null,Object? appName = null,Object? title = null,Object? body = null,Object? userId = freezed,Object? postedAt = freezed,Object? groupSummary = null,Object? canOpen = freezed,Object? canDismiss = freezed,}) {
  return _then(_DeviceNotification(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,revision: freezed == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as String?,packageName: null == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String,appName: null == appName ? _self.appName : appName // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,userId: freezed == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int?,postedAt: freezed == postedAt ? _self.postedAt : postedAt // ignore: cast_nullable_to_non_nullable
as int?,groupSummary: null == groupSummary ? _self.groupSummary : groupSummary // ignore: cast_nullable_to_non_nullable
as bool,canOpen: freezed == canOpen ? _self.canOpen : canOpen // ignore: cast_nullable_to_non_nullable
as bool?,canDismiss: freezed == canDismiss ? _self.canDismiss : canDismiss // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}


/// @nodoc
mixin _$DeviceNotificationsSnapshot {

 String get deviceId;@JsonKey(unknownEnumValue: DeviceNotificationAvailability.unknown) DeviceNotificationAvailability get status; bool get live; int? get observationEpoch; bool get observationEnabled; bool get truncated; List<DeviceNotification> get notifications; String? get reason;
/// Create a copy of DeviceNotificationsSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceNotificationsSnapshotCopyWith<DeviceNotificationsSnapshot> get copyWith => _$DeviceNotificationsSnapshotCopyWithImpl<DeviceNotificationsSnapshot>(this as DeviceNotificationsSnapshot, _$identity);

  /// Serializes this DeviceNotificationsSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DeviceNotificationsSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceNotificationsSnapshot&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.live, _this.live) || other.live == _this.live)&&(identical(other.observationEpoch, _this.observationEpoch) || other.observationEpoch == _this.observationEpoch)&&(identical(other.observationEnabled, _this.observationEnabled) || other.observationEnabled == _this.observationEnabled)&&(identical(other.truncated, _this.truncated) || other.truncated == _this.truncated)&&const DeepCollectionEquality().equals(other.notifications, _this.notifications)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DeviceNotificationsSnapshot;
  return Object.hash(runtimeType,_this.deviceId,_this.status,_this.live,_this.observationEpoch,_this.observationEnabled,_this.truncated,const DeepCollectionEquality().hash(_this.notifications),_this.reason);
}

@override
String toString() {
  final _this = this as DeviceNotificationsSnapshot;
  return 'DeviceNotificationsSnapshot(deviceId: ${_this.deviceId}, status: ${_this.status}, live: ${_this.live}, observationEpoch: ${_this.observationEpoch}, observationEnabled: ${_this.observationEnabled}, truncated: ${_this.truncated}, notifications: ${_this.notifications}, reason: ${_this.reason})';
}


}

/// @nodoc
abstract mixin class $DeviceNotificationsSnapshotCopyWith<$Res>  {
  factory $DeviceNotificationsSnapshotCopyWith(DeviceNotificationsSnapshot value, $Res Function(DeviceNotificationsSnapshot) _then) = _$DeviceNotificationsSnapshotCopyWithImpl;
@useResult
$Res call({
 String deviceId,@JsonKey(unknownEnumValue: DeviceNotificationAvailability.unknown) DeviceNotificationAvailability status, bool live, int? observationEpoch, bool observationEnabled, bool truncated, List<DeviceNotification> notifications, String? reason
});




}
/// @nodoc
class _$DeviceNotificationsSnapshotCopyWithImpl<$Res>
    implements $DeviceNotificationsSnapshotCopyWith<$Res> {
  _$DeviceNotificationsSnapshotCopyWithImpl(this._self, this._then);

  final DeviceNotificationsSnapshot _self;
  final $Res Function(DeviceNotificationsSnapshot) _then;

/// Create a copy of DeviceNotificationsSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? status = null,Object? live = null,Object? observationEpoch = freezed,Object? observationEnabled = null,Object? truncated = null,Object? notifications = null,Object? reason = freezed,}) {
  return _then(DeviceNotificationsSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceNotificationAvailability,live: null == live ? _self.live : live // ignore: cast_nullable_to_non_nullable
as bool,observationEpoch: freezed == observationEpoch ? _self.observationEpoch : observationEpoch // ignore: cast_nullable_to_non_nullable
as int?,observationEnabled: null == observationEnabled ? _self.observationEnabled : observationEnabled // ignore: cast_nullable_to_non_nullable
as bool,truncated: null == truncated ? _self.truncated : truncated // ignore: cast_nullable_to_non_nullable
as bool,notifications: null == notifications ? _self.notifications : notifications // ignore: cast_nullable_to_non_nullable
as List<DeviceNotification>,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceNotificationsSnapshot].
extension DeviceNotificationsSnapshotPatterns on DeviceNotificationsSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceNotificationsSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceNotificationsSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceNotificationsSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _DeviceNotificationsSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceNotificationsSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceNotificationsSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId, @JsonKey(unknownEnumValue: DeviceNotificationAvailability.unknown)  DeviceNotificationAvailability status,  bool live,  int? observationEpoch,  bool observationEnabled,  bool truncated,  List<DeviceNotification> notifications,  String? reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceNotificationsSnapshot() when $default != null:
return $default(_that.deviceId,_that.status,_that.live,_that.observationEpoch,_that.observationEnabled,_that.truncated,_that.notifications,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId, @JsonKey(unknownEnumValue: DeviceNotificationAvailability.unknown)  DeviceNotificationAvailability status,  bool live,  int? observationEpoch,  bool observationEnabled,  bool truncated,  List<DeviceNotification> notifications,  String? reason)  $default,) {final _that = this;
switch (_that) {
case _DeviceNotificationsSnapshot():
return $default(_that.deviceId,_that.status,_that.live,_that.observationEpoch,_that.observationEnabled,_that.truncated,_that.notifications,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId, @JsonKey(unknownEnumValue: DeviceNotificationAvailability.unknown)  DeviceNotificationAvailability status,  bool live,  int? observationEpoch,  bool observationEnabled,  bool truncated,  List<DeviceNotification> notifications,  String? reason)?  $default,) {final _that = this;
switch (_that) {
case _DeviceNotificationsSnapshot() when $default != null:
return $default(_that.deviceId,_that.status,_that.live,_that.observationEpoch,_that.observationEnabled,_that.truncated,_that.notifications,_that.reason);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DeviceNotificationsSnapshot implements DeviceNotificationsSnapshot {
  const _DeviceNotificationsSnapshot({required this.deviceId, @JsonKey(unknownEnumValue: DeviceNotificationAvailability.unknown) this.status = DeviceNotificationAvailability.unknown, this.live = false, this.observationEpoch, this.observationEnabled = false, this.truncated = false,  List<DeviceNotification> notifications = const [], this.reason}): _notifications = notifications;
  factory _DeviceNotificationsSnapshot.fromJson(Map<String, dynamic> json) => _$DeviceNotificationsSnapshotFromJson(json);

@override final  String deviceId;
@override@JsonKey(unknownEnumValue: DeviceNotificationAvailability.unknown) final  DeviceNotificationAvailability status;
@override@JsonKey() final  bool live;
@override final  int? observationEpoch;
@override@JsonKey() final  bool observationEnabled;
@override@JsonKey() final  bool truncated;
 final  List<DeviceNotification> _notifications;
@override@JsonKey() List<DeviceNotification> get notifications {
  if (_notifications is EqualUnmodifiableListView) return _notifications;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_notifications);
}

@override final  String? reason;

/// Create a copy of DeviceNotificationsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceNotificationsSnapshotCopyWith<_DeviceNotificationsSnapshot> get copyWith => __$DeviceNotificationsSnapshotCopyWithImpl<_DeviceNotificationsSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DeviceNotificationsSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceNotificationsSnapshot&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.status, status) || other.status == status)&&(identical(other.live, live) || other.live == live)&&(identical(other.observationEpoch, observationEpoch) || other.observationEpoch == observationEpoch)&&(identical(other.observationEnabled, observationEnabled) || other.observationEnabled == observationEnabled)&&(identical(other.truncated, truncated) || other.truncated == truncated)&&const DeepCollectionEquality().equals(other.notifications, _notifications)&&(identical(other.reason, reason) || other.reason == reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,status,live,observationEpoch,observationEnabled,truncated,const DeepCollectionEquality().hash(_notifications),reason);
}

@override
String toString() {
    return 'DeviceNotificationsSnapshot(deviceId: $deviceId, status: $status, live: $live, observationEpoch: $observationEpoch, observationEnabled: $observationEnabled, truncated: $truncated, notifications: $notifications, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$DeviceNotificationsSnapshotCopyWith<$Res> implements $DeviceNotificationsSnapshotCopyWith<$Res> {
  factory _$DeviceNotificationsSnapshotCopyWith(_DeviceNotificationsSnapshot value, $Res Function(_DeviceNotificationsSnapshot) _then) = __$DeviceNotificationsSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String deviceId,@JsonKey(unknownEnumValue: DeviceNotificationAvailability.unknown) DeviceNotificationAvailability status, bool live, int? observationEpoch, bool observationEnabled, bool truncated, List<DeviceNotification> notifications, String? reason
});




}
/// @nodoc
class __$DeviceNotificationsSnapshotCopyWithImpl<$Res>
    implements _$DeviceNotificationsSnapshotCopyWith<$Res> {
  __$DeviceNotificationsSnapshotCopyWithImpl(this._self, this._then);

  final _DeviceNotificationsSnapshot _self;
  final $Res Function(_DeviceNotificationsSnapshot) _then;

/// Create a copy of DeviceNotificationsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? status = null,Object? live = null,Object? observationEpoch = freezed,Object? observationEnabled = null,Object? truncated = null,Object? notifications = null,Object? reason = freezed,}) {
  return _then(_DeviceNotificationsSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceNotificationAvailability,live: null == live ? _self.live : live // ignore: cast_nullable_to_non_nullable
as bool,observationEpoch: freezed == observationEpoch ? _self.observationEpoch : observationEpoch // ignore: cast_nullable_to_non_nullable
as int?,observationEnabled: null == observationEnabled ? _self.observationEnabled : observationEnabled // ignore: cast_nullable_to_non_nullable
as bool,truncated: null == truncated ? _self.truncated : truncated // ignore: cast_nullable_to_non_nullable
as bool,notifications: null == notifications ? _self._notifications : notifications // ignore: cast_nullable_to_non_nullable
as List<DeviceNotification>,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
