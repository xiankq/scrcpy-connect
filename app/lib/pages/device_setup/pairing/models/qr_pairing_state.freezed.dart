// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'qr_pairing_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$QrPairingState {

 QrPairingPhase get phase; String? get payload; DateTime? get expiresAt; PairingReceipt? get receipt; String? get message;
/// Create a copy of QrPairingState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QrPairingStateCopyWith<QrPairingState> get copyWith => _$QrPairingStateCopyWithImpl<QrPairingState>(this as QrPairingState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QrPairingState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QrPairingState&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.payload, _this.payload) || other.payload == _this.payload)&&(identical(other.expiresAt, _this.expiresAt) || other.expiresAt == _this.expiresAt)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as QrPairingState;
  return Object.hash(runtimeType,_this.phase,_this.payload,_this.expiresAt,_this.receipt,_this.message);
}

@override
String toString() {
  final _this = this as QrPairingState;
  return 'QrPairingState(phase: ${_this.phase}, payload: ${_this.payload}, expiresAt: ${_this.expiresAt}, receipt: ${_this.receipt}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $QrPairingStateCopyWith<$Res>  {
  factory $QrPairingStateCopyWith(QrPairingState value, $Res Function(QrPairingState) _then) = _$QrPairingStateCopyWithImpl;
@useResult
$Res call({
 QrPairingPhase phase, String? payload, DateTime? expiresAt, PairingReceipt? receipt, String? message
});


$PairingReceiptCopyWith<$Res>? get receipt;

}
/// @nodoc
class _$QrPairingStateCopyWithImpl<$Res>
    implements $QrPairingStateCopyWith<$Res> {
  _$QrPairingStateCopyWithImpl(this._self, this._then);

  final QrPairingState _self;
  final $Res Function(QrPairingState) _then;

/// Create a copy of QrPairingState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? payload = freezed,Object? expiresAt = freezed,Object? receipt = freezed,Object? message = freezed,}) {
  return _then(QrPairingState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as QrPairingPhase,payload: freezed == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as String?,expiresAt: freezed == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as DateTime?,receipt: freezed == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as PairingReceipt?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of QrPairingState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PairingReceiptCopyWith<$Res>? get receipt {
    if (_self.receipt == null) {
    return null;
  }

  return $PairingReceiptCopyWith<$Res>(_self.receipt!, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [QrPairingState].
extension QrPairingStatePatterns on QrPairingState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QrPairingState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QrPairingState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QrPairingState value)  $default,){
final _that = this;
switch (_that) {
case _QrPairingState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QrPairingState value)?  $default,){
final _that = this;
switch (_that) {
case _QrPairingState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( QrPairingPhase phase,  String? payload,  DateTime? expiresAt,  PairingReceipt? receipt,  String? message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QrPairingState() when $default != null:
return $default(_that.phase,_that.payload,_that.expiresAt,_that.receipt,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( QrPairingPhase phase,  String? payload,  DateTime? expiresAt,  PairingReceipt? receipt,  String? message)  $default,) {final _that = this;
switch (_that) {
case _QrPairingState():
return $default(_that.phase,_that.payload,_that.expiresAt,_that.receipt,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( QrPairingPhase phase,  String? payload,  DateTime? expiresAt,  PairingReceipt? receipt,  String? message)?  $default,) {final _that = this;
switch (_that) {
case _QrPairingState() when $default != null:
return $default(_that.phase,_that.payload,_that.expiresAt,_that.receipt,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _QrPairingState extends QrPairingState {
  const _QrPairingState({this.phase = QrPairingPhase.idle, this.payload, this.expiresAt, this.receipt, this.message}): super._();
  

@override@JsonKey() final  QrPairingPhase phase;
@override final  String? payload;
@override final  DateTime? expiresAt;
@override final  PairingReceipt? receipt;
@override final  String? message;

/// Create a copy of QrPairingState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QrPairingStateCopyWith<_QrPairingState> get copyWith => __$QrPairingStateCopyWithImpl<_QrPairingState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QrPairingState&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.payload, payload) || other.payload == payload)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,payload,expiresAt,receipt,message);
}

@override
String toString() {
    return 'QrPairingState(phase: $phase, payload: $payload, expiresAt: $expiresAt, receipt: $receipt, message: $message)';
}


}

/// @nodoc
abstract mixin class _$QrPairingStateCopyWith<$Res> implements $QrPairingStateCopyWith<$Res> {
  factory _$QrPairingStateCopyWith(_QrPairingState value, $Res Function(_QrPairingState) _then) = __$QrPairingStateCopyWithImpl;
@override @useResult
$Res call({
 QrPairingPhase phase, String? payload, DateTime? expiresAt, PairingReceipt? receipt, String? message
});


@override $PairingReceiptCopyWith<$Res>? get receipt;

}
/// @nodoc
class __$QrPairingStateCopyWithImpl<$Res>
    implements _$QrPairingStateCopyWith<$Res> {
  __$QrPairingStateCopyWithImpl(this._self, this._then);

  final _QrPairingState _self;
  final $Res Function(_QrPairingState) _then;

/// Create a copy of QrPairingState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? payload = freezed,Object? expiresAt = freezed,Object? receipt = freezed,Object? message = freezed,}) {
  return _then(_QrPairingState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as QrPairingPhase,payload: freezed == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as String?,expiresAt: freezed == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as DateTime?,receipt: freezed == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as PairingReceipt?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of QrPairingState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PairingReceiptCopyWith<$Res>? get receipt {
    if (_self.receipt == null) {
    return null;
  }

  return $PairingReceiptCopyWith<$Res>(_self.receipt!, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}

// dart format on
