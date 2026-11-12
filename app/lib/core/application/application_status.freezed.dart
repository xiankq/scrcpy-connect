// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'application_status.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ApplicationStatus {


/// Create a copy of ApplicationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApplicationStatusCopyWith<ApplicationStatus> get copyWith => _$ApplicationStatusCopyWithImpl<ApplicationStatus>(this as ApplicationStatus, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ApplicationStatus;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApplicationStatus&&const DeepCollectionEquality().equals(other.lastEvent, _this.lastEvent)&&const DeepCollectionEquality().equals(other.reconciledSnapshot, _this.reconciledSnapshot)&&(identical(other.eventRevision, _this.eventRevision) || other.eventRevision == _this.eventRevision)&&(identical(other.audioError, _this.audioError) || other.audioError == _this.audioError)&&(identical(other.focusedDeviceId, _this.focusedDeviceId) || other.focusedDeviceId == _this.focusedDeviceId)&&(identical(other.reconciliationError, _this.reconciliationError) || other.reconciliationError == _this.reconciliationError)&&(identical(other.reconciliationPending, _this.reconciliationPending) || other.reconciliationPending == _this.reconciliationPending));
}


@override
int get hashCode {
  final _this = this as ApplicationStatus;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.lastEvent),const DeepCollectionEquality().hash(_this.reconciledSnapshot),_this.eventRevision,_this.audioError,_this.focusedDeviceId,_this.reconciliationError,_this.reconciliationPending);
}

@override
String toString() {
  final _this = this as ApplicationStatus;
  return 'ApplicationStatus(lastEvent: ${_this.lastEvent}, reconciledSnapshot: ${_this.reconciledSnapshot}, eventRevision: ${_this.eventRevision}, audioError: ${_this.audioError}, focusedDeviceId: ${_this.focusedDeviceId}, reconciliationError: ${_this.reconciliationError}, reconciliationPending: ${_this.reconciliationPending})';
}


}

/// @nodoc
abstract mixin class $ApplicationStatusCopyWith<$Res>  {
  factory $ApplicationStatusCopyWith(ApplicationStatus value, $Res Function(ApplicationStatus) _then) = _$ApplicationStatusCopyWithImpl;
@useResult
$Res call({
 Json? lastEvent, int eventRevision, String? audioError, String? focusedDeviceId, bool reconciliationPending, String? reconciliationError, Json? reconciledSnapshot
});




}
/// @nodoc
class _$ApplicationStatusCopyWithImpl<$Res>
    implements $ApplicationStatusCopyWith<$Res> {
  _$ApplicationStatusCopyWithImpl(this._self, this._then);

  final ApplicationStatus _self;
  final $Res Function(ApplicationStatus) _then;

/// Create a copy of ApplicationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lastEvent = freezed,Object? eventRevision = null,Object? audioError = freezed,Object? focusedDeviceId = freezed,Object? reconciliationPending = null,Object? reconciliationError = freezed,Object? reconciledSnapshot = freezed,}) {
  return _then(ApplicationStatus(
lastEvent: freezed == lastEvent ? _self.lastEvent : lastEvent // ignore: cast_nullable_to_non_nullable
as Json?,eventRevision: null == eventRevision ? _self.eventRevision : eventRevision // ignore: cast_nullable_to_non_nullable
as int,audioError: freezed == audioError ? _self.audioError : audioError // ignore: cast_nullable_to_non_nullable
as String?,focusedDeviceId: freezed == focusedDeviceId ? _self.focusedDeviceId : focusedDeviceId // ignore: cast_nullable_to_non_nullable
as String?,reconciliationPending: null == reconciliationPending ? _self.reconciliationPending : reconciliationPending // ignore: cast_nullable_to_non_nullable
as bool,reconciliationError: freezed == reconciliationError ? _self.reconciliationError : reconciliationError // ignore: cast_nullable_to_non_nullable
as String?,reconciledSnapshot: freezed == reconciledSnapshot ? _self.reconciledSnapshot : reconciledSnapshot // ignore: cast_nullable_to_non_nullable
as Json?,
  ));
}

}


/// Adds pattern-matching-related methods to [ApplicationStatus].
extension ApplicationStatusPatterns on ApplicationStatus {
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
