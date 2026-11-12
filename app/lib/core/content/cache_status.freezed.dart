// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'cache_status.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CacheProtection {


/// Create a copy of CacheProtection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CacheProtectionCopyWith<CacheProtection> get copyWith => _$CacheProtectionCopyWithImpl<CacheProtection>(this as CacheProtection, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CacheProtection;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CacheProtection&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.sourceLabel, _this.sourceLabel) || other.sourceLabel == _this.sourceLabel)&&(identical(other.sourcePath, _this.sourcePath) || other.sourcePath == _this.sourcePath)&&(identical(other.transferId, _this.transferId) || other.transferId == _this.transferId)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.canExport, _this.canExport) || other.canExport == _this.canExport));
}


@override
int get hashCode {
  final _this = this as CacheProtection;
  return Object.hash(runtimeType,_this.path,_this.name,_this.sourceLabel,_this.sourcePath,_this.transferId,_this.reason,_this.canExport);
}

@override
String toString() {
  final _this = this as CacheProtection;
  return 'CacheProtection(path: ${_this.path}, name: ${_this.name}, sourceLabel: ${_this.sourceLabel}, sourcePath: ${_this.sourcePath}, transferId: ${_this.transferId}, reason: ${_this.reason}, canExport: ${_this.canExport})';
}


}

/// @nodoc
abstract mixin class $CacheProtectionCopyWith<$Res>  {
  factory $CacheProtectionCopyWith(CacheProtection value, $Res Function(CacheProtection) _then) = _$CacheProtectionCopyWithImpl;
@useResult
$Res call({
 String path, String? name, String? sourceLabel, String? sourcePath, String? transferId, String? reason, bool canExport
});




}
/// @nodoc
class _$CacheProtectionCopyWithImpl<$Res>
    implements $CacheProtectionCopyWith<$Res> {
  _$CacheProtectionCopyWithImpl(this._self, this._then);

  final CacheProtection _self;
  final $Res Function(CacheProtection) _then;

/// Create a copy of CacheProtection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? name = freezed,Object? sourceLabel = freezed,Object? sourcePath = freezed,Object? transferId = freezed,Object? reason = freezed,Object? canExport = null,}) {
  return _then(CacheProtection(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,sourceLabel: freezed == sourceLabel ? _self.sourceLabel : sourceLabel // ignore: cast_nullable_to_non_nullable
as String?,sourcePath: freezed == sourcePath ? _self.sourcePath : sourcePath // ignore: cast_nullable_to_non_nullable
as String?,transferId: freezed == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,canExport: null == canExport ? _self.canExport : canExport // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [CacheProtection].
extension CacheProtectionPatterns on CacheProtection {
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

/// @nodoc
mixin _$ProtectedCacheItem {


/// Create a copy of ProtectedCacheItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProtectedCacheItemCopyWith<ProtectedCacheItem> get copyWith => _$ProtectedCacheItemCopyWithImpl<ProtectedCacheItem>(this as ProtectedCacheItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProtectedCacheItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProtectedCacheItem&&(identical(other.localPath, _this.localPath) || other.localPath == _this.localPath)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.sourceLabel, _this.sourceLabel) || other.sourceLabel == _this.sourceLabel)&&(identical(other.sourcePath, _this.sourcePath) || other.sourcePath == _this.sourcePath)&&(identical(other.transferId, _this.transferId) || other.transferId == _this.transferId)&&(identical(other.bytes, _this.bytes) || other.bytes == _this.bytes)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.canExport, _this.canExport) || other.canExport == _this.canExport)&&(identical(other.canShare, _this.canShare) || other.canShare == _this.canShare)&&(identical(other.externalLifetimeUnknown, _this.externalLifetimeUnknown) || other.externalLifetimeUnknown == _this.externalLifetimeUnknown));
}


@override
int get hashCode {
  final _this = this as ProtectedCacheItem;
  return Object.hash(runtimeType,_this.localPath,_this.name,_this.sourceLabel,_this.sourcePath,_this.transferId,_this.bytes,_this.reason,_this.canExport,_this.canShare,_this.externalLifetimeUnknown);
}

@override
String toString() {
  final _this = this as ProtectedCacheItem;
  return 'ProtectedCacheItem(localPath: ${_this.localPath}, name: ${_this.name}, sourceLabel: ${_this.sourceLabel}, sourcePath: ${_this.sourcePath}, transferId: ${_this.transferId}, bytes: ${_this.bytes}, reason: ${_this.reason}, canExport: ${_this.canExport}, canShare: ${_this.canShare}, externalLifetimeUnknown: ${_this.externalLifetimeUnknown})';
}


}

/// @nodoc
abstract mixin class $ProtectedCacheItemCopyWith<$Res>  {
  factory $ProtectedCacheItemCopyWith(ProtectedCacheItem value, $Res Function(ProtectedCacheItem) _then) = _$ProtectedCacheItemCopyWithImpl;
@useResult
$Res call({
 String localPath, String name, String sourceLabel, int bytes, String reason, String? sourcePath, String? transferId, bool canExport, bool canShare, bool externalLifetimeUnknown
});




}
/// @nodoc
class _$ProtectedCacheItemCopyWithImpl<$Res>
    implements $ProtectedCacheItemCopyWith<$Res> {
  _$ProtectedCacheItemCopyWithImpl(this._self, this._then);

  final ProtectedCacheItem _self;
  final $Res Function(ProtectedCacheItem) _then;

/// Create a copy of ProtectedCacheItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? localPath = null,Object? name = null,Object? sourceLabel = null,Object? bytes = null,Object? reason = null,Object? sourcePath = freezed,Object? transferId = freezed,Object? canExport = null,Object? canShare = null,Object? externalLifetimeUnknown = null,}) {
  return _then(ProtectedCacheItem(
localPath: null == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sourceLabel: null == sourceLabel ? _self.sourceLabel : sourceLabel // ignore: cast_nullable_to_non_nullable
as String,bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,sourcePath: freezed == sourcePath ? _self.sourcePath : sourcePath // ignore: cast_nullable_to_non_nullable
as String?,transferId: freezed == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String?,canExport: null == canExport ? _self.canExport : canExport // ignore: cast_nullable_to_non_nullable
as bool,canShare: null == canShare ? _self.canShare : canShare // ignore: cast_nullable_to_non_nullable
as bool,externalLifetimeUnknown: null == externalLifetimeUnknown ? _self.externalLifetimeUnknown : externalLifetimeUnknown // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ProtectedCacheItem].
extension ProtectedCacheItemPatterns on ProtectedCacheItem {
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

/// @nodoc
mixin _$CacheStatus {


/// Create a copy of CacheStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CacheStatusCopyWith<CacheStatus> get copyWith => _$CacheStatusCopyWithImpl<CacheStatus>(this as CacheStatus, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CacheStatus;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CacheStatus&&(identical(other.budgetBytes, _this.budgetBytes) || other.budgetBytes == _this.budgetBytes)&&(identical(other.usedBytes, _this.usedBytes) || other.usedBytes == _this.usedBytes)&&(identical(other.protectedBytes, _this.protectedBytes) || other.protectedBytes == _this.protectedBytes)&&(identical(other.reclaimableBytes, _this.reclaimableBytes) || other.reclaimableBytes == _this.reclaimableBytes)&&(identical(other.reservedBytes, _this.reservedBytes) || other.reservedBytes == _this.reservedBytes)&&(identical(other.freeBytes, _this.freeBytes) || other.freeBytes == _this.freeBytes)&&(identical(other.availableBytes, _this.availableBytes) || other.availableBytes == _this.availableBytes)&&(identical(other.spaceVerified, _this.spaceVerified) || other.spaceVerified == _this.spaceVerified)&&const DeepCollectionEquality().equals(other.protectedItems, _this.protectedItems)&&(identical(other.retainedShareCount, _this.retainedShareCount) || other.retainedShareCount == _this.retainedShareCount)&&(identical(other.retentionReason, _this.retentionReason) || other.retentionReason == _this.retentionReason));
}


@override
int get hashCode {
  final _this = this as CacheStatus;
  return Object.hash(runtimeType,_this.budgetBytes,_this.usedBytes,_this.protectedBytes,_this.reclaimableBytes,_this.reservedBytes,_this.freeBytes,_this.availableBytes,_this.spaceVerified,const DeepCollectionEquality().hash(_this.protectedItems),_this.retainedShareCount,_this.retentionReason);
}

@override
String toString() {
  final _this = this as CacheStatus;
  return 'CacheStatus(budgetBytes: ${_this.budgetBytes}, usedBytes: ${_this.usedBytes}, protectedBytes: ${_this.protectedBytes}, reclaimableBytes: ${_this.reclaimableBytes}, reservedBytes: ${_this.reservedBytes}, freeBytes: ${_this.freeBytes}, availableBytes: ${_this.availableBytes}, spaceVerified: ${_this.spaceVerified}, protectedItems: ${_this.protectedItems}, retainedShareCount: ${_this.retainedShareCount}, retentionReason: ${_this.retentionReason})';
}


}

/// @nodoc
abstract mixin class $CacheStatusCopyWith<$Res>  {
  factory $CacheStatusCopyWith(CacheStatus value, $Res Function(CacheStatus) _then) = _$CacheStatusCopyWithImpl;
@useResult
$Res call({
 int budgetBytes, int usedBytes, int protectedBytes, int reclaimableBytes, int reservedBytes, int availableBytes, int? freeBytes, bool spaceVerified, List<ProtectedCacheItem> protectedItems, int retainedShareCount, String? retentionReason
});




}
/// @nodoc
class _$CacheStatusCopyWithImpl<$Res>
    implements $CacheStatusCopyWith<$Res> {
  _$CacheStatusCopyWithImpl(this._self, this._then);

  final CacheStatus _self;
  final $Res Function(CacheStatus) _then;

/// Create a copy of CacheStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? budgetBytes = null,Object? usedBytes = null,Object? protectedBytes = null,Object? reclaimableBytes = null,Object? reservedBytes = null,Object? availableBytes = null,Object? freeBytes = freezed,Object? spaceVerified = null,Object? protectedItems = null,Object? retainedShareCount = null,Object? retentionReason = freezed,}) {
  return _then(CacheStatus(
budgetBytes: null == budgetBytes ? _self.budgetBytes : budgetBytes // ignore: cast_nullable_to_non_nullable
as int,usedBytes: null == usedBytes ? _self.usedBytes : usedBytes // ignore: cast_nullable_to_non_nullable
as int,protectedBytes: null == protectedBytes ? _self.protectedBytes : protectedBytes // ignore: cast_nullable_to_non_nullable
as int,reclaimableBytes: null == reclaimableBytes ? _self.reclaimableBytes : reclaimableBytes // ignore: cast_nullable_to_non_nullable
as int,reservedBytes: null == reservedBytes ? _self.reservedBytes : reservedBytes // ignore: cast_nullable_to_non_nullable
as int,availableBytes: null == availableBytes ? _self.availableBytes : availableBytes // ignore: cast_nullable_to_non_nullable
as int,freeBytes: freezed == freeBytes ? _self.freeBytes : freeBytes // ignore: cast_nullable_to_non_nullable
as int?,spaceVerified: null == spaceVerified ? _self.spaceVerified : spaceVerified // ignore: cast_nullable_to_non_nullable
as bool,protectedItems: null == protectedItems ? _self.protectedItems : protectedItems // ignore: cast_nullable_to_non_nullable
as List<ProtectedCacheItem>,retainedShareCount: null == retainedShareCount ? _self.retainedShareCount : retainedShareCount // ignore: cast_nullable_to_non_nullable
as int,retentionReason: freezed == retentionReason ? _self.retentionReason : retentionReason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [CacheStatus].
extension CacheStatusPatterns on CacheStatus {
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
