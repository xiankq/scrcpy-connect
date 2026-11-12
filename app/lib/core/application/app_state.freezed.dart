// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppState {


/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppStateCopyWith<AppState> get copyWith => _$AppStateCopyWithImpl<AppState>(this as AppState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AppState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppState&&const DeepCollectionEquality().equals(other.devices, _this.devices)&&(identical(other.settings, _this.settings) || other.settings == _this.settings)&&const DeepCollectionEquality().equals(other.pendingShares, _this.pendingShares)&&const DeepCollectionEquality().equals(other.lastEvent, _this.lastEvent)&&(identical(other.eventRevision, _this.eventRevision) || other.eventRevision == _this.eventRevision)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.deviceError, _this.deviceError) || other.deviceError == _this.deviceError)&&(identical(other.settingsError, _this.settingsError) || other.settingsError == _this.settingsError)&&(identical(other.audioError, _this.audioError) || other.audioError == _this.audioError)&&(identical(other.focusedDeviceId, _this.focusedDeviceId) || other.focusedDeviceId == _this.focusedDeviceId)&&(identical(other.reconciliationPending, _this.reconciliationPending) || other.reconciliationPending == _this.reconciliationPending)&&(identical(other.reconciliationError, _this.reconciliationError) || other.reconciliationError == _this.reconciliationError)&&const DeepCollectionEquality().equals(other.reconciledSnapshot, _this.reconciledSnapshot));
}


@override
int get hashCode {
  final _this = this as AppState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.devices),_this.settings,const DeepCollectionEquality().hash(_this.pendingShares),const DeepCollectionEquality().hash(_this.lastEvent),_this.eventRevision,_this.loading,_this.deviceError,_this.settingsError,_this.audioError,_this.focusedDeviceId,_this.reconciliationPending,_this.reconciliationError,const DeepCollectionEquality().hash(_this.reconciledSnapshot));
}

@override
String toString() {
  final _this = this as AppState;
  return 'AppState(devices: ${_this.devices}, settings: ${_this.settings}, pendingShares: ${_this.pendingShares}, lastEvent: ${_this.lastEvent}, eventRevision: ${_this.eventRevision}, loading: ${_this.loading}, deviceError: ${_this.deviceError}, settingsError: ${_this.settingsError}, audioError: ${_this.audioError}, focusedDeviceId: ${_this.focusedDeviceId}, reconciliationPending: ${_this.reconciliationPending}, reconciliationError: ${_this.reconciliationError}, reconciledSnapshot: ${_this.reconciledSnapshot})';
}


}

/// @nodoc
abstract mixin class $AppStateCopyWith<$Res>  {
  factory $AppStateCopyWith(AppState value, $Res Function(AppState) _then) = _$AppStateCopyWithImpl;
@useResult
$Res call({
 List<DeviceSnapshot> devices, Preferences? settings, List<IncomingShare> pendingShares, Json? lastEvent, int eventRevision, bool loading, String? deviceError, String? settingsError, String? audioError, String? focusedDeviceId, bool reconciliationPending, String? reconciliationError, Json? reconciledSnapshot
});


$PreferencesCopyWith<$Res>? get settings;

}
/// @nodoc
class _$AppStateCopyWithImpl<$Res>
    implements $AppStateCopyWith<$Res> {
  _$AppStateCopyWithImpl(this._self, this._then);

  final AppState _self;
  final $Res Function(AppState) _then;

/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? devices = null,Object? settings = freezed,Object? pendingShares = null,Object? lastEvent = freezed,Object? eventRevision = null,Object? loading = null,Object? deviceError = freezed,Object? settingsError = freezed,Object? audioError = freezed,Object? focusedDeviceId = freezed,Object? reconciliationPending = null,Object? reconciliationError = freezed,Object? reconciledSnapshot = freezed,}) {
  return _then(AppState(
devices: null == devices ? _self.devices : devices // ignore: cast_nullable_to_non_nullable
as List<DeviceSnapshot>,settings: freezed == settings ? _self.settings! : settings // ignore: cast_nullable_to_non_nullable
as Preferences?,pendingShares: null == pendingShares ? _self.pendingShares : pendingShares // ignore: cast_nullable_to_non_nullable
as List<IncomingShare>,lastEvent: freezed == lastEvent ? _self.lastEvent : lastEvent // ignore: cast_nullable_to_non_nullable
as Json?,eventRevision: null == eventRevision ? _self.eventRevision : eventRevision // ignore: cast_nullable_to_non_nullable
as int,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,deviceError: freezed == deviceError ? _self.deviceError : deviceError // ignore: cast_nullable_to_non_nullable
as String?,settingsError: freezed == settingsError ? _self.settingsError : settingsError // ignore: cast_nullable_to_non_nullable
as String?,audioError: freezed == audioError ? _self.audioError : audioError // ignore: cast_nullable_to_non_nullable
as String?,focusedDeviceId: freezed == focusedDeviceId ? _self.focusedDeviceId : focusedDeviceId // ignore: cast_nullable_to_non_nullable
as String?,reconciliationPending: null == reconciliationPending ? _self.reconciliationPending : reconciliationPending // ignore: cast_nullable_to_non_nullable
as bool,reconciliationError: freezed == reconciliationError ? _self.reconciliationError : reconciliationError // ignore: cast_nullable_to_non_nullable
as String?,reconciledSnapshot: freezed == reconciledSnapshot ? _self.reconciledSnapshot : reconciledSnapshot // ignore: cast_nullable_to_non_nullable
as Json?,
  ));
}
/// Create a copy of AppState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PreferencesCopyWith<$Res>? get settings {
    if (_self.settings == null) {
    return null;
  }

  return $PreferencesCopyWith<$Res>(_self.settings!, (value) {
    return _then(_self.copyWith(settings: value));
  });
}
}


/// Adds pattern-matching-related methods to [AppState].
extension AppStatePatterns on AppState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

// dart format on
