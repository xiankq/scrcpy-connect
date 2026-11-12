// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'cached_content.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CachedContent {


/// Create a copy of CachedContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CachedContentCopyWith<CachedContent> get copyWith => _$CachedContentCopyWithImpl<CachedContent>(this as CachedContent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CachedContent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CachedContent&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.leaseId, _this.leaseId) || other.leaseId == _this.leaseId)&&(identical(other.cacheHit, _this.cacheHit) || other.cacheHit == _this.cacheHit)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}


@override
int get hashCode {
  final _this = this as CachedContent;
  return Object.hash(runtimeType,_this.path,_this.leaseId,_this.cacheHit,_this.reason);
}

@override
String toString() {
  final _this = this as CachedContent;
  return 'CachedContent(path: ${_this.path}, leaseId: ${_this.leaseId}, cacheHit: ${_this.cacheHit}, reason: ${_this.reason})';
}


}

/// @nodoc
abstract mixin class $CachedContentCopyWith<$Res>  {
  factory $CachedContentCopyWith(CachedContent value, $Res Function(CachedContent) _then) = _$CachedContentCopyWithImpl;
@useResult
$Res call({
 String path, String? leaseId, bool cacheHit, String? reason
});




}
/// @nodoc
class _$CachedContentCopyWithImpl<$Res>
    implements $CachedContentCopyWith<$Res> {
  _$CachedContentCopyWithImpl(this._self, this._then);

  final CachedContent _self;
  final $Res Function(CachedContent) _then;

/// Create a copy of CachedContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? leaseId = freezed,Object? cacheHit = null,Object? reason = freezed,}) {
  return _then(CachedContent(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,leaseId: freezed == leaseId ? _self.leaseId : leaseId // ignore: cast_nullable_to_non_nullable
as String?,cacheHit: null == cacheHit ? _self.cacheHit : cacheHit // ignore: cast_nullable_to_non_nullable
as bool,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [CachedContent].
extension CachedContentPatterns on CachedContent {
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
