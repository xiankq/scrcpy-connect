// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'keep_awake_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$KeepAwakeFailure {

 String get code; String get reason;
/// Create a copy of KeepAwakeFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KeepAwakeFailureCopyWith<KeepAwakeFailure> get copyWith => _$KeepAwakeFailureCopyWithImpl<KeepAwakeFailure>(this as KeepAwakeFailure, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as KeepAwakeFailure;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KeepAwakeFailure&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}


@override
int get hashCode {
  final _this = this as KeepAwakeFailure;
  return Object.hash(runtimeType,_this.code,_this.reason);
}

@override
String toString() {
  final _this = this as KeepAwakeFailure;
  return 'KeepAwakeFailure(code: ${_this.code}, reason: ${_this.reason})';
}


}

/// @nodoc
abstract mixin class $KeepAwakeFailureCopyWith<$Res>  {
  factory $KeepAwakeFailureCopyWith(KeepAwakeFailure value, $Res Function(KeepAwakeFailure) _then) = _$KeepAwakeFailureCopyWithImpl;
@useResult
$Res call({
 String code, String reason
});




}
/// @nodoc
class _$KeepAwakeFailureCopyWithImpl<$Res>
    implements $KeepAwakeFailureCopyWith<$Res> {
  _$KeepAwakeFailureCopyWithImpl(this._self, this._then);

  final KeepAwakeFailure _self;
  final $Res Function(KeepAwakeFailure) _then;

/// Create a copy of KeepAwakeFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? reason = null,}) {
  return _then(KeepAwakeFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [KeepAwakeFailure].
extension KeepAwakeFailurePatterns on KeepAwakeFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _KeepAwakeFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _KeepAwakeFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _KeepAwakeFailure value)  $default,){
final _that = this;
switch (_that) {
case _KeepAwakeFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _KeepAwakeFailure value)?  $default,){
final _that = this;
switch (_that) {
case _KeepAwakeFailure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String code,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _KeepAwakeFailure() when $default != null:
return $default(_that.code,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String code,  String reason)  $default,) {final _that = this;
switch (_that) {
case _KeepAwakeFailure():
return $default(_that.code,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String code,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _KeepAwakeFailure() when $default != null:
return $default(_that.code,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _KeepAwakeFailure extends KeepAwakeFailure {
  const _KeepAwakeFailure({required this.code, required this.reason}): super._();
  

@override final  String code;
@override final  String reason;

/// Create a copy of KeepAwakeFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$KeepAwakeFailureCopyWith<_KeepAwakeFailure> get copyWith => __$KeepAwakeFailureCopyWithImpl<_KeepAwakeFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _KeepAwakeFailure&&(identical(other.code, code) || other.code == code)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,reason);
}

@override
String toString() {
    return 'KeepAwakeFailure(code: $code, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$KeepAwakeFailureCopyWith<$Res> implements $KeepAwakeFailureCopyWith<$Res> {
  factory _$KeepAwakeFailureCopyWith(_KeepAwakeFailure value, $Res Function(_KeepAwakeFailure) _then) = __$KeepAwakeFailureCopyWithImpl;
@override @useResult
$Res call({
 String code, String reason
});




}
/// @nodoc
class __$KeepAwakeFailureCopyWithImpl<$Res>
    implements _$KeepAwakeFailureCopyWith<$Res> {
  __$KeepAwakeFailureCopyWithImpl(this._self, this._then);

  final _KeepAwakeFailure _self;
  final $Res Function(_KeepAwakeFailure) _then;

/// Create a copy of KeepAwakeFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? reason = null,}) {
  return _then(_KeepAwakeFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$KeepAwakeSnapshot {

 String get deviceId; KeepAwakeStatus get status; bool get keepActive; bool get keepActiveApplied; bool get keepActiveLeaseActive; String? get keepActiveLeaseId; int? get keepActivePid; int? get keepActiveProcessStarted; String? get keepActiveConnectionId; KeepAwakeFailure? get keepActiveError; bool get releasePending; bool get localCleanupConfirmed; bool get cleanupConfirmed; bool get remoteExitVerified; bool get remoteRestoreVerified; List<KeepAwakeSnapshot> get pendingCleanup;
/// Create a copy of KeepAwakeSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KeepAwakeSnapshotCopyWith<KeepAwakeSnapshot> get copyWith => _$KeepAwakeSnapshotCopyWithImpl<KeepAwakeSnapshot>(this as KeepAwakeSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as KeepAwakeSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KeepAwakeSnapshot&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.keepActive, _this.keepActive) || other.keepActive == _this.keepActive)&&(identical(other.keepActiveApplied, _this.keepActiveApplied) || other.keepActiveApplied == _this.keepActiveApplied)&&(identical(other.keepActiveLeaseActive, _this.keepActiveLeaseActive) || other.keepActiveLeaseActive == _this.keepActiveLeaseActive)&&(identical(other.keepActiveLeaseId, _this.keepActiveLeaseId) || other.keepActiveLeaseId == _this.keepActiveLeaseId)&&(identical(other.keepActivePid, _this.keepActivePid) || other.keepActivePid == _this.keepActivePid)&&(identical(other.keepActiveProcessStarted, _this.keepActiveProcessStarted) || other.keepActiveProcessStarted == _this.keepActiveProcessStarted)&&(identical(other.keepActiveConnectionId, _this.keepActiveConnectionId) || other.keepActiveConnectionId == _this.keepActiveConnectionId)&&(identical(other.keepActiveError, _this.keepActiveError) || other.keepActiveError == _this.keepActiveError)&&(identical(other.releasePending, _this.releasePending) || other.releasePending == _this.releasePending)&&(identical(other.localCleanupConfirmed, _this.localCleanupConfirmed) || other.localCleanupConfirmed == _this.localCleanupConfirmed)&&(identical(other.cleanupConfirmed, _this.cleanupConfirmed) || other.cleanupConfirmed == _this.cleanupConfirmed)&&(identical(other.remoteExitVerified, _this.remoteExitVerified) || other.remoteExitVerified == _this.remoteExitVerified)&&(identical(other.remoteRestoreVerified, _this.remoteRestoreVerified) || other.remoteRestoreVerified == _this.remoteRestoreVerified)&&const DeepCollectionEquality().equals(other.pendingCleanup, _this.pendingCleanup));
}


@override
int get hashCode {
  final _this = this as KeepAwakeSnapshot;
  return Object.hash(runtimeType,_this.deviceId,_this.status,_this.keepActive,_this.keepActiveApplied,_this.keepActiveLeaseActive,_this.keepActiveLeaseId,_this.keepActivePid,_this.keepActiveProcessStarted,_this.keepActiveConnectionId,_this.keepActiveError,_this.releasePending,_this.localCleanupConfirmed,_this.cleanupConfirmed,_this.remoteExitVerified,_this.remoteRestoreVerified,const DeepCollectionEquality().hash(_this.pendingCleanup));
}

@override
String toString() {
  final _this = this as KeepAwakeSnapshot;
  return 'KeepAwakeSnapshot(deviceId: ${_this.deviceId}, status: ${_this.status}, keepActive: ${_this.keepActive}, keepActiveApplied: ${_this.keepActiveApplied}, keepActiveLeaseActive: ${_this.keepActiveLeaseActive}, keepActiveLeaseId: ${_this.keepActiveLeaseId}, keepActivePid: ${_this.keepActivePid}, keepActiveProcessStarted: ${_this.keepActiveProcessStarted}, keepActiveConnectionId: ${_this.keepActiveConnectionId}, keepActiveError: ${_this.keepActiveError}, releasePending: ${_this.releasePending}, localCleanupConfirmed: ${_this.localCleanupConfirmed}, cleanupConfirmed: ${_this.cleanupConfirmed}, remoteExitVerified: ${_this.remoteExitVerified}, remoteRestoreVerified: ${_this.remoteRestoreVerified}, pendingCleanup: ${_this.pendingCleanup})';
}


}

/// @nodoc
abstract mixin class $KeepAwakeSnapshotCopyWith<$Res>  {
  factory $KeepAwakeSnapshotCopyWith(KeepAwakeSnapshot value, $Res Function(KeepAwakeSnapshot) _then) = _$KeepAwakeSnapshotCopyWithImpl;
@useResult
$Res call({
 String deviceId, KeepAwakeStatus status, bool keepActive, bool keepActiveApplied, bool keepActiveLeaseActive, String? keepActiveLeaseId, int? keepActivePid, int? keepActiveProcessStarted, String? keepActiveConnectionId, KeepAwakeFailure? keepActiveError, bool releasePending, bool localCleanupConfirmed, bool cleanupConfirmed, bool remoteExitVerified, bool remoteRestoreVerified, List<KeepAwakeSnapshot> pendingCleanup
});


$KeepAwakeFailureCopyWith<$Res>? get keepActiveError;

}
/// @nodoc
class _$KeepAwakeSnapshotCopyWithImpl<$Res>
    implements $KeepAwakeSnapshotCopyWith<$Res> {
  _$KeepAwakeSnapshotCopyWithImpl(this._self, this._then);

  final KeepAwakeSnapshot _self;
  final $Res Function(KeepAwakeSnapshot) _then;

/// Create a copy of KeepAwakeSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? status = null,Object? keepActive = null,Object? keepActiveApplied = null,Object? keepActiveLeaseActive = null,Object? keepActiveLeaseId = freezed,Object? keepActivePid = freezed,Object? keepActiveProcessStarted = freezed,Object? keepActiveConnectionId = freezed,Object? keepActiveError = freezed,Object? releasePending = null,Object? localCleanupConfirmed = null,Object? cleanupConfirmed = null,Object? remoteExitVerified = null,Object? remoteRestoreVerified = null,Object? pendingCleanup = null,}) {
  return _then(KeepAwakeSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as KeepAwakeStatus,keepActive: null == keepActive ? _self.keepActive : keepActive // ignore: cast_nullable_to_non_nullable
as bool,keepActiveApplied: null == keepActiveApplied ? _self.keepActiveApplied : keepActiveApplied // ignore: cast_nullable_to_non_nullable
as bool,keepActiveLeaseActive: null == keepActiveLeaseActive ? _self.keepActiveLeaseActive : keepActiveLeaseActive // ignore: cast_nullable_to_non_nullable
as bool,keepActiveLeaseId: freezed == keepActiveLeaseId ? _self.keepActiveLeaseId : keepActiveLeaseId // ignore: cast_nullable_to_non_nullable
as String?,keepActivePid: freezed == keepActivePid ? _self.keepActivePid : keepActivePid // ignore: cast_nullable_to_non_nullable
as int?,keepActiveProcessStarted: freezed == keepActiveProcessStarted ? _self.keepActiveProcessStarted : keepActiveProcessStarted // ignore: cast_nullable_to_non_nullable
as int?,keepActiveConnectionId: freezed == keepActiveConnectionId ? _self.keepActiveConnectionId : keepActiveConnectionId // ignore: cast_nullable_to_non_nullable
as String?,keepActiveError: freezed == keepActiveError ? _self.keepActiveError : keepActiveError // ignore: cast_nullable_to_non_nullable
as KeepAwakeFailure?,releasePending: null == releasePending ? _self.releasePending : releasePending // ignore: cast_nullable_to_non_nullable
as bool,localCleanupConfirmed: null == localCleanupConfirmed ? _self.localCleanupConfirmed : localCleanupConfirmed // ignore: cast_nullable_to_non_nullable
as bool,cleanupConfirmed: null == cleanupConfirmed ? _self.cleanupConfirmed : cleanupConfirmed // ignore: cast_nullable_to_non_nullable
as bool,remoteExitVerified: null == remoteExitVerified ? _self.remoteExitVerified : remoteExitVerified // ignore: cast_nullable_to_non_nullable
as bool,remoteRestoreVerified: null == remoteRestoreVerified ? _self.remoteRestoreVerified : remoteRestoreVerified // ignore: cast_nullable_to_non_nullable
as bool,pendingCleanup: null == pendingCleanup ? _self.pendingCleanup : pendingCleanup // ignore: cast_nullable_to_non_nullable
as List<KeepAwakeSnapshot>,
  ));
}
/// Create a copy of KeepAwakeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$KeepAwakeFailureCopyWith<$Res>? get keepActiveError {
    if (_self.keepActiveError == null) {
    return null;
  }

  return $KeepAwakeFailureCopyWith<$Res>(_self.keepActiveError!, (value) {
    return _then(_self.copyWith(keepActiveError: value));
  });
}
}


/// Adds pattern-matching-related methods to [KeepAwakeSnapshot].
extension KeepAwakeSnapshotPatterns on KeepAwakeSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _KeepAwakeSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _KeepAwakeSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _KeepAwakeSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _KeepAwakeSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _KeepAwakeSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _KeepAwakeSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  KeepAwakeStatus status,  bool keepActive,  bool keepActiveApplied,  bool keepActiveLeaseActive,  String? keepActiveLeaseId,  int? keepActivePid,  int? keepActiveProcessStarted,  String? keepActiveConnectionId,  KeepAwakeFailure? keepActiveError,  bool releasePending,  bool localCleanupConfirmed,  bool cleanupConfirmed,  bool remoteExitVerified,  bool remoteRestoreVerified,  List<KeepAwakeSnapshot> pendingCleanup)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _KeepAwakeSnapshot() when $default != null:
return $default(_that.deviceId,_that.status,_that.keepActive,_that.keepActiveApplied,_that.keepActiveLeaseActive,_that.keepActiveLeaseId,_that.keepActivePid,_that.keepActiveProcessStarted,_that.keepActiveConnectionId,_that.keepActiveError,_that.releasePending,_that.localCleanupConfirmed,_that.cleanupConfirmed,_that.remoteExitVerified,_that.remoteRestoreVerified,_that.pendingCleanup);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  KeepAwakeStatus status,  bool keepActive,  bool keepActiveApplied,  bool keepActiveLeaseActive,  String? keepActiveLeaseId,  int? keepActivePid,  int? keepActiveProcessStarted,  String? keepActiveConnectionId,  KeepAwakeFailure? keepActiveError,  bool releasePending,  bool localCleanupConfirmed,  bool cleanupConfirmed,  bool remoteExitVerified,  bool remoteRestoreVerified,  List<KeepAwakeSnapshot> pendingCleanup)  $default,) {final _that = this;
switch (_that) {
case _KeepAwakeSnapshot():
return $default(_that.deviceId,_that.status,_that.keepActive,_that.keepActiveApplied,_that.keepActiveLeaseActive,_that.keepActiveLeaseId,_that.keepActivePid,_that.keepActiveProcessStarted,_that.keepActiveConnectionId,_that.keepActiveError,_that.releasePending,_that.localCleanupConfirmed,_that.cleanupConfirmed,_that.remoteExitVerified,_that.remoteRestoreVerified,_that.pendingCleanup);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  KeepAwakeStatus status,  bool keepActive,  bool keepActiveApplied,  bool keepActiveLeaseActive,  String? keepActiveLeaseId,  int? keepActivePid,  int? keepActiveProcessStarted,  String? keepActiveConnectionId,  KeepAwakeFailure? keepActiveError,  bool releasePending,  bool localCleanupConfirmed,  bool cleanupConfirmed,  bool remoteExitVerified,  bool remoteRestoreVerified,  List<KeepAwakeSnapshot> pendingCleanup)?  $default,) {final _that = this;
switch (_that) {
case _KeepAwakeSnapshot() when $default != null:
return $default(_that.deviceId,_that.status,_that.keepActive,_that.keepActiveApplied,_that.keepActiveLeaseActive,_that.keepActiveLeaseId,_that.keepActivePid,_that.keepActiveProcessStarted,_that.keepActiveConnectionId,_that.keepActiveError,_that.releasePending,_that.localCleanupConfirmed,_that.cleanupConfirmed,_that.remoteExitVerified,_that.remoteRestoreVerified,_that.pendingCleanup);case _:
  return null;

}
}

}

/// @nodoc


class _KeepAwakeSnapshot extends KeepAwakeSnapshot {
  const _KeepAwakeSnapshot({required this.deviceId, this.status = KeepAwakeStatus.starting, this.keepActive = false, this.keepActiveApplied = false, this.keepActiveLeaseActive = false, this.keepActiveLeaseId, this.keepActivePid, this.keepActiveProcessStarted, this.keepActiveConnectionId, this.keepActiveError, this.releasePending = false, this.localCleanupConfirmed = false, this.cleanupConfirmed = false, this.remoteExitVerified = false, this.remoteRestoreVerified = false,  List<KeepAwakeSnapshot> pendingCleanup = const []}): _pendingCleanup = pendingCleanup,super._();
  

@override final  String deviceId;
@override@JsonKey() final  KeepAwakeStatus status;
@override@JsonKey() final  bool keepActive;
@override@JsonKey() final  bool keepActiveApplied;
@override@JsonKey() final  bool keepActiveLeaseActive;
@override final  String? keepActiveLeaseId;
@override final  int? keepActivePid;
@override final  int? keepActiveProcessStarted;
@override final  String? keepActiveConnectionId;
@override final  KeepAwakeFailure? keepActiveError;
@override@JsonKey() final  bool releasePending;
@override@JsonKey() final  bool localCleanupConfirmed;
@override@JsonKey() final  bool cleanupConfirmed;
@override@JsonKey() final  bool remoteExitVerified;
@override@JsonKey() final  bool remoteRestoreVerified;
 final  List<KeepAwakeSnapshot> _pendingCleanup;
@override@JsonKey() List<KeepAwakeSnapshot> get pendingCleanup {
  if (_pendingCleanup is EqualUnmodifiableListView) return _pendingCleanup;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_pendingCleanup);
}


/// Create a copy of KeepAwakeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$KeepAwakeSnapshotCopyWith<_KeepAwakeSnapshot> get copyWith => __$KeepAwakeSnapshotCopyWithImpl<_KeepAwakeSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _KeepAwakeSnapshot&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.status, status) || other.status == status)&&(identical(other.keepActive, keepActive) || other.keepActive == keepActive)&&(identical(other.keepActiveApplied, keepActiveApplied) || other.keepActiveApplied == keepActiveApplied)&&(identical(other.keepActiveLeaseActive, keepActiveLeaseActive) || other.keepActiveLeaseActive == keepActiveLeaseActive)&&(identical(other.keepActiveLeaseId, keepActiveLeaseId) || other.keepActiveLeaseId == keepActiveLeaseId)&&(identical(other.keepActivePid, keepActivePid) || other.keepActivePid == keepActivePid)&&(identical(other.keepActiveProcessStarted, keepActiveProcessStarted) || other.keepActiveProcessStarted == keepActiveProcessStarted)&&(identical(other.keepActiveConnectionId, keepActiveConnectionId) || other.keepActiveConnectionId == keepActiveConnectionId)&&(identical(other.keepActiveError, keepActiveError) || other.keepActiveError == keepActiveError)&&(identical(other.releasePending, releasePending) || other.releasePending == releasePending)&&(identical(other.localCleanupConfirmed, localCleanupConfirmed) || other.localCleanupConfirmed == localCleanupConfirmed)&&(identical(other.cleanupConfirmed, cleanupConfirmed) || other.cleanupConfirmed == cleanupConfirmed)&&(identical(other.remoteExitVerified, remoteExitVerified) || other.remoteExitVerified == remoteExitVerified)&&(identical(other.remoteRestoreVerified, remoteRestoreVerified) || other.remoteRestoreVerified == remoteRestoreVerified)&&const DeepCollectionEquality().equals(other.pendingCleanup, _pendingCleanup));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,status,keepActive,keepActiveApplied,keepActiveLeaseActive,keepActiveLeaseId,keepActivePid,keepActiveProcessStarted,keepActiveConnectionId,keepActiveError,releasePending,localCleanupConfirmed,cleanupConfirmed,remoteExitVerified,remoteRestoreVerified,const DeepCollectionEquality().hash(_pendingCleanup));
}

@override
String toString() {
    return 'KeepAwakeSnapshot(deviceId: $deviceId, status: $status, keepActive: $keepActive, keepActiveApplied: $keepActiveApplied, keepActiveLeaseActive: $keepActiveLeaseActive, keepActiveLeaseId: $keepActiveLeaseId, keepActivePid: $keepActivePid, keepActiveProcessStarted: $keepActiveProcessStarted, keepActiveConnectionId: $keepActiveConnectionId, keepActiveError: $keepActiveError, releasePending: $releasePending, localCleanupConfirmed: $localCleanupConfirmed, cleanupConfirmed: $cleanupConfirmed, remoteExitVerified: $remoteExitVerified, remoteRestoreVerified: $remoteRestoreVerified, pendingCleanup: $pendingCleanup)';
}


}

/// @nodoc
abstract mixin class _$KeepAwakeSnapshotCopyWith<$Res> implements $KeepAwakeSnapshotCopyWith<$Res> {
  factory _$KeepAwakeSnapshotCopyWith(_KeepAwakeSnapshot value, $Res Function(_KeepAwakeSnapshot) _then) = __$KeepAwakeSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, KeepAwakeStatus status, bool keepActive, bool keepActiveApplied, bool keepActiveLeaseActive, String? keepActiveLeaseId, int? keepActivePid, int? keepActiveProcessStarted, String? keepActiveConnectionId, KeepAwakeFailure? keepActiveError, bool releasePending, bool localCleanupConfirmed, bool cleanupConfirmed, bool remoteExitVerified, bool remoteRestoreVerified, List<KeepAwakeSnapshot> pendingCleanup
});


@override $KeepAwakeFailureCopyWith<$Res>? get keepActiveError;

}
/// @nodoc
class __$KeepAwakeSnapshotCopyWithImpl<$Res>
    implements _$KeepAwakeSnapshotCopyWith<$Res> {
  __$KeepAwakeSnapshotCopyWithImpl(this._self, this._then);

  final _KeepAwakeSnapshot _self;
  final $Res Function(_KeepAwakeSnapshot) _then;

/// Create a copy of KeepAwakeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? status = null,Object? keepActive = null,Object? keepActiveApplied = null,Object? keepActiveLeaseActive = null,Object? keepActiveLeaseId = freezed,Object? keepActivePid = freezed,Object? keepActiveProcessStarted = freezed,Object? keepActiveConnectionId = freezed,Object? keepActiveError = freezed,Object? releasePending = null,Object? localCleanupConfirmed = null,Object? cleanupConfirmed = null,Object? remoteExitVerified = null,Object? remoteRestoreVerified = null,Object? pendingCleanup = null,}) {
  return _then(_KeepAwakeSnapshot(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as KeepAwakeStatus,keepActive: null == keepActive ? _self.keepActive : keepActive // ignore: cast_nullable_to_non_nullable
as bool,keepActiveApplied: null == keepActiveApplied ? _self.keepActiveApplied : keepActiveApplied // ignore: cast_nullable_to_non_nullable
as bool,keepActiveLeaseActive: null == keepActiveLeaseActive ? _self.keepActiveLeaseActive : keepActiveLeaseActive // ignore: cast_nullable_to_non_nullable
as bool,keepActiveLeaseId: freezed == keepActiveLeaseId ? _self.keepActiveLeaseId : keepActiveLeaseId // ignore: cast_nullable_to_non_nullable
as String?,keepActivePid: freezed == keepActivePid ? _self.keepActivePid : keepActivePid // ignore: cast_nullable_to_non_nullable
as int?,keepActiveProcessStarted: freezed == keepActiveProcessStarted ? _self.keepActiveProcessStarted : keepActiveProcessStarted // ignore: cast_nullable_to_non_nullable
as int?,keepActiveConnectionId: freezed == keepActiveConnectionId ? _self.keepActiveConnectionId : keepActiveConnectionId // ignore: cast_nullable_to_non_nullable
as String?,keepActiveError: freezed == keepActiveError ? _self.keepActiveError : keepActiveError // ignore: cast_nullable_to_non_nullable
as KeepAwakeFailure?,releasePending: null == releasePending ? _self.releasePending : releasePending // ignore: cast_nullable_to_non_nullable
as bool,localCleanupConfirmed: null == localCleanupConfirmed ? _self.localCleanupConfirmed : localCleanupConfirmed // ignore: cast_nullable_to_non_nullable
as bool,cleanupConfirmed: null == cleanupConfirmed ? _self.cleanupConfirmed : cleanupConfirmed // ignore: cast_nullable_to_non_nullable
as bool,remoteExitVerified: null == remoteExitVerified ? _self.remoteExitVerified : remoteExitVerified // ignore: cast_nullable_to_non_nullable
as bool,remoteRestoreVerified: null == remoteRestoreVerified ? _self.remoteRestoreVerified : remoteRestoreVerified // ignore: cast_nullable_to_non_nullable
as bool,pendingCleanup: null == pendingCleanup ? _self._pendingCleanup : pendingCleanup // ignore: cast_nullable_to_non_nullable
as List<KeepAwakeSnapshot>,
  ));
}

/// Create a copy of KeepAwakeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$KeepAwakeFailureCopyWith<$Res>? get keepActiveError {
    if (_self.keepActiveError == null) {
    return null;
  }

  return $KeepAwakeFailureCopyWith<$Res>(_self.keepActiveError!, (value) {
    return _then(_self.copyWith(keepActiveError: value));
  });
}
}

// dart format on
