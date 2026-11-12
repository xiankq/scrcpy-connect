// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'authorization_identity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AuthorizationIdentity {


/// Create a copy of AuthorizationIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthorizationIdentityCopyWith<AuthorizationIdentity> get copyWith => _$AuthorizationIdentityCopyWithImpl<AuthorizationIdentity>(this as AuthorizationIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AuthorizationIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthorizationIdentity&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.fingerprint, _this.fingerprint) || other.fingerprint == _this.fingerprint)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&const DeepCollectionEquality().equals(other.affectedDeviceIds, _this.affectedDeviceIds));
}


@override
int get hashCode {
  final _this = this as AuthorizationIdentity;
  return Object.hash(runtimeType,_this.scope,_this.fingerprint,_this.deviceId,const DeepCollectionEquality().hash(_this.affectedDeviceIds));
}

@override
String toString() {
  final _this = this as AuthorizationIdentity;
  return 'AuthorizationIdentity(scope: ${_this.scope}, fingerprint: ${_this.fingerprint}, deviceId: ${_this.deviceId}, affectedDeviceIds: ${_this.affectedDeviceIds})';
}


}

/// @nodoc
abstract mixin class $AuthorizationIdentityCopyWith<$Res>  {
  factory $AuthorizationIdentityCopyWith(AuthorizationIdentity value, $Res Function(AuthorizationIdentity) _then) = _$AuthorizationIdentityCopyWithImpl;
@useResult
$Res call({
 IdentityScope scope, String fingerprint, String? deviceId, List<String> affectedDeviceIds
});




}
/// @nodoc
class _$AuthorizationIdentityCopyWithImpl<$Res>
    implements $AuthorizationIdentityCopyWith<$Res> {
  _$AuthorizationIdentityCopyWithImpl(this._self, this._then);

  final AuthorizationIdentity _self;
  final $Res Function(AuthorizationIdentity) _then;

/// Create a copy of AuthorizationIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? fingerprint = null,Object? deviceId = freezed,Object? affectedDeviceIds = null,}) {
  return _then(AuthorizationIdentity(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as IdentityScope,fingerprint: null == fingerprint ? _self.fingerprint : fingerprint // ignore: cast_nullable_to_non_nullable
as String,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,affectedDeviceIds: null == affectedDeviceIds ? _self.affectedDeviceIds : affectedDeviceIds // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [AuthorizationIdentity].
extension AuthorizationIdentityPatterns on AuthorizationIdentity {
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
