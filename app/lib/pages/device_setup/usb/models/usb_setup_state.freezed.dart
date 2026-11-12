// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'usb_setup_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UsbSetupState {

 UsbSetupPhase get phase; UsbSetupResult? get result; String? get message;
/// Create a copy of UsbSetupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsbSetupStateCopyWith<UsbSetupState> get copyWith => _$UsbSetupStateCopyWithImpl<UsbSetupState>(this as UsbSetupState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UsbSetupState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbSetupState&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.result, _this.result) || other.result == _this.result)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as UsbSetupState;
  return Object.hash(runtimeType,_this.phase,_this.result,_this.message);
}

@override
String toString() {
  final _this = this as UsbSetupState;
  return 'UsbSetupState(phase: ${_this.phase}, result: ${_this.result}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $UsbSetupStateCopyWith<$Res>  {
  factory $UsbSetupStateCopyWith(UsbSetupState value, $Res Function(UsbSetupState) _then) = _$UsbSetupStateCopyWithImpl;
@useResult
$Res call({
 UsbSetupPhase phase, UsbSetupResult? result, String? message
});


$UsbSetupResultCopyWith<$Res>? get result;

}
/// @nodoc
class _$UsbSetupStateCopyWithImpl<$Res>
    implements $UsbSetupStateCopyWith<$Res> {
  _$UsbSetupStateCopyWithImpl(this._self, this._then);

  final UsbSetupState _self;
  final $Res Function(UsbSetupState) _then;

/// Create a copy of UsbSetupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? result = freezed,Object? message = freezed,}) {
  return _then(UsbSetupState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as UsbSetupPhase,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as UsbSetupResult?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of UsbSetupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UsbSetupResultCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $UsbSetupResultCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}


/// Adds pattern-matching-related methods to [UsbSetupState].
extension UsbSetupStatePatterns on UsbSetupState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UsbSetupState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UsbSetupState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UsbSetupState value)  $default,){
final _that = this;
switch (_that) {
case _UsbSetupState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UsbSetupState value)?  $default,){
final _that = this;
switch (_that) {
case _UsbSetupState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( UsbSetupPhase phase,  UsbSetupResult? result,  String? message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UsbSetupState() when $default != null:
return $default(_that.phase,_that.result,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( UsbSetupPhase phase,  UsbSetupResult? result,  String? message)  $default,) {final _that = this;
switch (_that) {
case _UsbSetupState():
return $default(_that.phase,_that.result,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( UsbSetupPhase phase,  UsbSetupResult? result,  String? message)?  $default,) {final _that = this;
switch (_that) {
case _UsbSetupState() when $default != null:
return $default(_that.phase,_that.result,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _UsbSetupState extends UsbSetupState {
  const _UsbSetupState({this.phase = UsbSetupPhase.idle, this.result, this.message}): super._();
  

@override@JsonKey() final  UsbSetupPhase phase;
@override final  UsbSetupResult? result;
@override final  String? message;

/// Create a copy of UsbSetupState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UsbSetupStateCopyWith<_UsbSetupState> get copyWith => __$UsbSetupStateCopyWithImpl<_UsbSetupState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UsbSetupState&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.result, result) || other.result == result)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,result,message);
}

@override
String toString() {
    return 'UsbSetupState(phase: $phase, result: $result, message: $message)';
}


}

/// @nodoc
abstract mixin class _$UsbSetupStateCopyWith<$Res> implements $UsbSetupStateCopyWith<$Res> {
  factory _$UsbSetupStateCopyWith(_UsbSetupState value, $Res Function(_UsbSetupState) _then) = __$UsbSetupStateCopyWithImpl;
@override @useResult
$Res call({
 UsbSetupPhase phase, UsbSetupResult? result, String? message
});


@override $UsbSetupResultCopyWith<$Res>? get result;

}
/// @nodoc
class __$UsbSetupStateCopyWithImpl<$Res>
    implements _$UsbSetupStateCopyWith<$Res> {
  __$UsbSetupStateCopyWithImpl(this._self, this._then);

  final _UsbSetupState _self;
  final $Res Function(_UsbSetupState) _then;

/// Create a copy of UsbSetupState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? result = freezed,Object? message = freezed,}) {
  return _then(_UsbSetupState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as UsbSetupPhase,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as UsbSetupResult?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of UsbSetupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UsbSetupResultCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $UsbSetupResultCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

// dart format on
