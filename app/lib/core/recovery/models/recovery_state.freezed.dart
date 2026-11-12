// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recovery_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RecoveryState {


/// Create a copy of RecoveryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryStateCopyWith<RecoveryState> get copyWith => _$RecoveryStateCopyWithImpl<RecoveryState>(this as RecoveryState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryState&&const DeepCollectionEquality().equals(other.lastEvent, _this.lastEvent)&&(identical(other.reconciledSnapshot, _this.reconciledSnapshot) || other.reconciledSnapshot == _this.reconciledSnapshot)&&(identical(other.eventRevision, _this.eventRevision) || other.eventRevision == _this.eventRevision)&&(identical(other.reconciliationError, _this.reconciliationError) || other.reconciliationError == _this.reconciliationError)&&(identical(other.reconciliationPending, _this.reconciliationPending) || other.reconciliationPending == _this.reconciliationPending));
}


@override
int get hashCode {
  final _this = this as RecoveryState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.lastEvent),_this.reconciledSnapshot,_this.eventRevision,_this.reconciliationError,_this.reconciliationPending);
}

@override
String toString() {
  final _this = this as RecoveryState;
  return 'RecoveryState(lastEvent: ${_this.lastEvent}, reconciledSnapshot: ${_this.reconciledSnapshot}, eventRevision: ${_this.eventRevision}, reconciliationError: ${_this.reconciliationError}, reconciliationPending: ${_this.reconciliationPending})';
}


}

/// @nodoc
abstract mixin class $RecoveryStateCopyWith<$Res>  {
  factory $RecoveryStateCopyWith(RecoveryState value, $Res Function(RecoveryState) _then) = _$RecoveryStateCopyWithImpl;
@useResult
$Res call({
 Json? lastEvent, int eventRevision, bool reconciliationPending, String? reconciliationError, RuntimeSnapshot? reconciledSnapshot
});




}
/// @nodoc
class _$RecoveryStateCopyWithImpl<$Res>
    implements $RecoveryStateCopyWith<$Res> {
  _$RecoveryStateCopyWithImpl(this._self, this._then);

  final RecoveryState _self;
  final $Res Function(RecoveryState) _then;

/// Create a copy of RecoveryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lastEvent = freezed,Object? eventRevision = null,Object? reconciliationPending = null,Object? reconciliationError = freezed,Object? reconciledSnapshot = freezed,}) {
  return _then(RecoveryState(
lastEvent: freezed == lastEvent ? _self.lastEvent : lastEvent // ignore: cast_nullable_to_non_nullable
as Json?,eventRevision: null == eventRevision ? _self.eventRevision : eventRevision // ignore: cast_nullable_to_non_nullable
as int,reconciliationPending: null == reconciliationPending ? _self.reconciliationPending : reconciliationPending // ignore: cast_nullable_to_non_nullable
as bool,reconciliationError: freezed == reconciliationError ? _self.reconciliationError : reconciliationError // ignore: cast_nullable_to_non_nullable
as String?,reconciledSnapshot: freezed == reconciledSnapshot ? _self.reconciledSnapshot : reconciledSnapshot // ignore: cast_nullable_to_non_nullable
as RuntimeSnapshot?,
  ));
}

}


/// Adds pattern-matching-related methods to [RecoveryState].
extension RecoveryStatePatterns on RecoveryState {
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
