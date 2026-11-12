// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_call.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DeviceCall {

 String? get id;@JsonKey(unknownEnumValue: DeviceCallState.unknown) DeviceCallState get state; String? get name; String? get number; String? get deviceName; bool get aggregate;
/// Create a copy of DeviceCall
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceCallCopyWith<DeviceCall> get copyWith => _$DeviceCallCopyWithImpl<DeviceCall>(this as DeviceCall, _$identity);

  /// Serializes this DeviceCall to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DeviceCall;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceCall&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.number, _this.number) || other.number == _this.number)&&(identical(other.deviceName, _this.deviceName) || other.deviceName == _this.deviceName)&&(identical(other.aggregate, _this.aggregate) || other.aggregate == _this.aggregate));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DeviceCall;
  return Object.hash(runtimeType,_this.id,_this.state,_this.name,_this.number,_this.deviceName,_this.aggregate);
}

@override
String toString() {
  final _this = this as DeviceCall;
  return 'DeviceCall(id: ${_this.id}, state: ${_this.state}, name: ${_this.name}, number: ${_this.number}, deviceName: ${_this.deviceName}, aggregate: ${_this.aggregate})';
}


}

/// @nodoc
abstract mixin class $DeviceCallCopyWith<$Res>  {
  factory $DeviceCallCopyWith(DeviceCall value, $Res Function(DeviceCall) _then) = _$DeviceCallCopyWithImpl;
@useResult
$Res call({
 String? id,@JsonKey(unknownEnumValue: DeviceCallState.unknown) DeviceCallState state, String? name, String? number, String? deviceName, bool aggregate
});




}
/// @nodoc
class _$DeviceCallCopyWithImpl<$Res>
    implements $DeviceCallCopyWith<$Res> {
  _$DeviceCallCopyWithImpl(this._self, this._then);

  final DeviceCall _self;
  final $Res Function(DeviceCall) _then;

/// Create a copy of DeviceCall
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? state = null,Object? name = freezed,Object? number = freezed,Object? deviceName = freezed,Object? aggregate = null,}) {
  return _then(DeviceCall(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as DeviceCallState,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,number: freezed == number ? _self.number : number // ignore: cast_nullable_to_non_nullable
as String?,deviceName: freezed == deviceName ? _self.deviceName : deviceName // ignore: cast_nullable_to_non_nullable
as String?,aggregate: null == aggregate ? _self.aggregate : aggregate // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceCall].
extension DeviceCallPatterns on DeviceCall {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceCall value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceCall() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceCall value)  $default,){
final _that = this;
switch (_that) {
case _DeviceCall():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceCall value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceCall() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? id, @JsonKey(unknownEnumValue: DeviceCallState.unknown)  DeviceCallState state,  String? name,  String? number,  String? deviceName,  bool aggregate)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceCall() when $default != null:
return $default(_that.id,_that.state,_that.name,_that.number,_that.deviceName,_that.aggregate);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? id, @JsonKey(unknownEnumValue: DeviceCallState.unknown)  DeviceCallState state,  String? name,  String? number,  String? deviceName,  bool aggregate)  $default,) {final _that = this;
switch (_that) {
case _DeviceCall():
return $default(_that.id,_that.state,_that.name,_that.number,_that.deviceName,_that.aggregate);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? id, @JsonKey(unknownEnumValue: DeviceCallState.unknown)  DeviceCallState state,  String? name,  String? number,  String? deviceName,  bool aggregate)?  $default,) {final _that = this;
switch (_that) {
case _DeviceCall() when $default != null:
return $default(_that.id,_that.state,_that.name,_that.number,_that.deviceName,_that.aggregate);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DeviceCall implements DeviceCall {
  const _DeviceCall({this.id, @JsonKey(unknownEnumValue: DeviceCallState.unknown) this.state = DeviceCallState.unknown, this.name, this.number, this.deviceName, this.aggregate = false});
  factory _DeviceCall.fromJson(Map<String, dynamic> json) => _$DeviceCallFromJson(json);

@override final  String? id;
@override@JsonKey(unknownEnumValue: DeviceCallState.unknown) final  DeviceCallState state;
@override final  String? name;
@override final  String? number;
@override final  String? deviceName;
@override@JsonKey() final  bool aggregate;

/// Create a copy of DeviceCall
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceCallCopyWith<_DeviceCall> get copyWith => __$DeviceCallCopyWithImpl<_DeviceCall>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DeviceCallToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceCall&&(identical(other.id, id) || other.id == id)&&(identical(other.state, state) || other.state == state)&&(identical(other.name, name) || other.name == name)&&(identical(other.number, number) || other.number == number)&&(identical(other.deviceName, deviceName) || other.deviceName == deviceName)&&(identical(other.aggregate, aggregate) || other.aggregate == aggregate));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,state,name,number,deviceName,aggregate);
}

@override
String toString() {
    return 'DeviceCall(id: $id, state: $state, name: $name, number: $number, deviceName: $deviceName, aggregate: $aggregate)';
}


}

/// @nodoc
abstract mixin class _$DeviceCallCopyWith<$Res> implements $DeviceCallCopyWith<$Res> {
  factory _$DeviceCallCopyWith(_DeviceCall value, $Res Function(_DeviceCall) _then) = __$DeviceCallCopyWithImpl;
@override @useResult
$Res call({
 String? id,@JsonKey(unknownEnumValue: DeviceCallState.unknown) DeviceCallState state, String? name, String? number, String? deviceName, bool aggregate
});




}
/// @nodoc
class __$DeviceCallCopyWithImpl<$Res>
    implements _$DeviceCallCopyWith<$Res> {
  __$DeviceCallCopyWithImpl(this._self, this._then);

  final _DeviceCall _self;
  final $Res Function(_DeviceCall) _then;

/// Create a copy of DeviceCall
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? state = null,Object? name = freezed,Object? number = freezed,Object? deviceName = freezed,Object? aggregate = null,}) {
  return _then(_DeviceCall(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as DeviceCallState,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,number: freezed == number ? _self.number : number // ignore: cast_nullable_to_non_nullable
as String?,deviceName: freezed == deviceName ? _self.deviceName : deviceName // ignore: cast_nullable_to_non_nullable
as String?,aggregate: null == aggregate ? _self.aggregate : aggregate // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$DeviceCallsSnapshot {

 String get deviceId;@JsonKey(unknownEnumValue: DeviceCallAvailability.unknown) DeviceCallAvailability get status; bool get live; List<DeviceCall> get calls; String? get reason; bool get canOpenSystemCallUi; bool get canRetrySystemCallUi;
/// Create a copy of DeviceCallsSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceCallsSnapshotCopyWith<DeviceCallsSnapshot> get copyWith => _$DeviceCallsSnapshotCopyWithImpl<DeviceCallsSnapshot>(this as DeviceCallsSnapshot, _$identity);

  /// Serializes this DeviceCallsSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DeviceCallsSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceCallsSnapshot&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.live, _this.live) || other.live == _this.live)&&const DeepCollectionEquality().equals(other.calls, _this.calls)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.canOpenSystemCallUi, _this.canOpenSystemCallUi) || other.canOpenSystemCallUi == _this.canOpenSystemCallUi)&&(identical(other.canRetrySystemCallUi, _this.canRetrySystemCallUi) || other.canRetrySystemCallUi == _this.canRetrySystemCallUi));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DeviceCallsSnapshot;
  return Object.hash(runtimeType,_this.deviceId,_this.status,_this.live,const DeepCollectionEquality().hash(_this.calls),_this.reason,_this.canOpenSystemCallUi,_this.canRetrySystemCallUi);
}

@override
String toString() {
  final _this = this as DeviceCallsSnapshot;
  return 'DeviceCallsSnapshot(deviceId: ${_this.deviceId}, status: ${_this.status}, live: ${_this.live}, calls: ${_this.calls}, reason: ${_this.reason}, canOpenSystemCallUi: ${_this.canOpenSystemCallUi}, canRetrySystemCallUi: ${_this.canRetrySystemCallUi})';
}


}

/// @nodoc
abstract mixin class $DeviceCallsSnapshotCopyWith<$Res>  {
  factory $DeviceCallsSnapshotCopyWith(DeviceCallsSnapshot value, $Res Function(DeviceCallsSnapshot) _then) = _$DeviceCallsSnapshotCopyWithImpl;
@useResult
$Res call({
 String deviceId,@JsonKey(unknownEnumValue: DeviceCallAvailability.unknown) DeviceCallAvailability status, bool live, List<DeviceCall> calls, String? reason, bool canOpenSystemCallUi, bool canRetrySystemCallUi
});




}
/// @nodoc
class _$DeviceCallsSnapshotCopyWithImpl<$Res>
    implements $DeviceCallsSnapshotCopyWith<$Res> {
  _$DeviceCallsSnapshotCopyWithImpl(this._self, this._then);

  final DeviceCallsSnapshot _self;
  final $Res Function(DeviceCallsSnapshot) _then;

/// Create a copy of DeviceCallsSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? status = null,Object? live = null,Object? calls = null,Object? reason = freezed,Object? canOpenSystemCallUi = null,Object? canRetrySystemCallUi = null,}) {
  return _then(DeviceCallsSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceCallAvailability,live: null == live ? _self.live : live // ignore: cast_nullable_to_non_nullable
as bool,calls: null == calls ? _self.calls : calls // ignore: cast_nullable_to_non_nullable
as List<DeviceCall>,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,canOpenSystemCallUi: null == canOpenSystemCallUi ? _self.canOpenSystemCallUi : canOpenSystemCallUi // ignore: cast_nullable_to_non_nullable
as bool,canRetrySystemCallUi: null == canRetrySystemCallUi ? _self.canRetrySystemCallUi : canRetrySystemCallUi // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceCallsSnapshot].
extension DeviceCallsSnapshotPatterns on DeviceCallsSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceCallsSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceCallsSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceCallsSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _DeviceCallsSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceCallsSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceCallsSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId, @JsonKey(unknownEnumValue: DeviceCallAvailability.unknown)  DeviceCallAvailability status,  bool live,  List<DeviceCall> calls,  String? reason,  bool canOpenSystemCallUi,  bool canRetrySystemCallUi)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceCallsSnapshot() when $default != null:
return $default(_that.deviceId,_that.status,_that.live,_that.calls,_that.reason,_that.canOpenSystemCallUi,_that.canRetrySystemCallUi);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId, @JsonKey(unknownEnumValue: DeviceCallAvailability.unknown)  DeviceCallAvailability status,  bool live,  List<DeviceCall> calls,  String? reason,  bool canOpenSystemCallUi,  bool canRetrySystemCallUi)  $default,) {final _that = this;
switch (_that) {
case _DeviceCallsSnapshot():
return $default(_that.deviceId,_that.status,_that.live,_that.calls,_that.reason,_that.canOpenSystemCallUi,_that.canRetrySystemCallUi);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId, @JsonKey(unknownEnumValue: DeviceCallAvailability.unknown)  DeviceCallAvailability status,  bool live,  List<DeviceCall> calls,  String? reason,  bool canOpenSystemCallUi,  bool canRetrySystemCallUi)?  $default,) {final _that = this;
switch (_that) {
case _DeviceCallsSnapshot() when $default != null:
return $default(_that.deviceId,_that.status,_that.live,_that.calls,_that.reason,_that.canOpenSystemCallUi,_that.canRetrySystemCallUi);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DeviceCallsSnapshot extends DeviceCallsSnapshot {
  const _DeviceCallsSnapshot({required this.deviceId, @JsonKey(unknownEnumValue: DeviceCallAvailability.unknown) this.status = DeviceCallAvailability.unknown, this.live = false,  List<DeviceCall> calls = const [], this.reason, this.canOpenSystemCallUi = false, this.canRetrySystemCallUi = false}): _calls = calls,super._();
  factory _DeviceCallsSnapshot.fromJson(Map<String, dynamic> json) => _$DeviceCallsSnapshotFromJson(json);

@override final  String deviceId;
@override@JsonKey(unknownEnumValue: DeviceCallAvailability.unknown) final  DeviceCallAvailability status;
@override@JsonKey() final  bool live;
 final  List<DeviceCall> _calls;
@override@JsonKey() List<DeviceCall> get calls {
  if (_calls is EqualUnmodifiableListView) return _calls;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_calls);
}

@override final  String? reason;
@override@JsonKey() final  bool canOpenSystemCallUi;
@override@JsonKey() final  bool canRetrySystemCallUi;

/// Create a copy of DeviceCallsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceCallsSnapshotCopyWith<_DeviceCallsSnapshot> get copyWith => __$DeviceCallsSnapshotCopyWithImpl<_DeviceCallsSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DeviceCallsSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceCallsSnapshot&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.status, status) || other.status == status)&&(identical(other.live, live) || other.live == live)&&const DeepCollectionEquality().equals(other.calls, _calls)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.canOpenSystemCallUi, canOpenSystemCallUi) || other.canOpenSystemCallUi == canOpenSystemCallUi)&&(identical(other.canRetrySystemCallUi, canRetrySystemCallUi) || other.canRetrySystemCallUi == canRetrySystemCallUi));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,status,live,const DeepCollectionEquality().hash(_calls),reason,canOpenSystemCallUi,canRetrySystemCallUi);
}

@override
String toString() {
    return 'DeviceCallsSnapshot(deviceId: $deviceId, status: $status, live: $live, calls: $calls, reason: $reason, canOpenSystemCallUi: $canOpenSystemCallUi, canRetrySystemCallUi: $canRetrySystemCallUi)';
}


}

/// @nodoc
abstract mixin class _$DeviceCallsSnapshotCopyWith<$Res> implements $DeviceCallsSnapshotCopyWith<$Res> {
  factory _$DeviceCallsSnapshotCopyWith(_DeviceCallsSnapshot value, $Res Function(_DeviceCallsSnapshot) _then) = __$DeviceCallsSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String deviceId,@JsonKey(unknownEnumValue: DeviceCallAvailability.unknown) DeviceCallAvailability status, bool live, List<DeviceCall> calls, String? reason, bool canOpenSystemCallUi, bool canRetrySystemCallUi
});




}
/// @nodoc
class __$DeviceCallsSnapshotCopyWithImpl<$Res>
    implements _$DeviceCallsSnapshotCopyWith<$Res> {
  __$DeviceCallsSnapshotCopyWithImpl(this._self, this._then);

  final _DeviceCallsSnapshot _self;
  final $Res Function(_DeviceCallsSnapshot) _then;

/// Create a copy of DeviceCallsSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? status = null,Object? live = null,Object? calls = null,Object? reason = freezed,Object? canOpenSystemCallUi = null,Object? canRetrySystemCallUi = null,}) {
  return _then(_DeviceCallsSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DeviceCallAvailability,live: null == live ? _self.live : live // ignore: cast_nullable_to_non_nullable
as bool,calls: null == calls ? _self._calls : calls // ignore: cast_nullable_to_non_nullable
as List<DeviceCall>,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,canOpenSystemCallUi: null == canOpenSystemCallUi ? _self.canOpenSystemCallUi : canOpenSystemCallUi // ignore: cast_nullable_to_non_nullable
as bool,canRetrySystemCallUi: null == canRetrySystemCallUi ? _self.canRetrySystemCallUi : canRetrySystemCallUi // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
