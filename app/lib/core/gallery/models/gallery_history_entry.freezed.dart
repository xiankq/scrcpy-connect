// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'gallery_history_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GalleryHistoryEntry {

 DeviceSnapshot get device; GalleryScanSnapshot get result; List<FileCatalogEntry> get items; double get scrollOffset; GalleryScanSnapshot? get pendingResult;
/// Create a copy of GalleryHistoryEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GalleryHistoryEntryCopyWith<GalleryHistoryEntry> get copyWith => _$GalleryHistoryEntryCopyWithImpl<GalleryHistoryEntry>(this as GalleryHistoryEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GalleryHistoryEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryHistoryEntry&&(identical(other.device, _this.device) || other.device == _this.device)&&(identical(other.result, _this.result) || other.result == _this.result)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.scrollOffset, _this.scrollOffset) || other.scrollOffset == _this.scrollOffset)&&(identical(other.pendingResult, _this.pendingResult) || other.pendingResult == _this.pendingResult));
}


@override
int get hashCode {
  final _this = this as GalleryHistoryEntry;
  return Object.hash(runtimeType,_this.device,_this.result,const DeepCollectionEquality().hash(_this.items),_this.scrollOffset,_this.pendingResult);
}

@override
String toString() {
  final _this = this as GalleryHistoryEntry;
  return 'GalleryHistoryEntry(device: ${_this.device}, result: ${_this.result}, items: ${_this.items}, scrollOffset: ${_this.scrollOffset}, pendingResult: ${_this.pendingResult})';
}


}

/// @nodoc
abstract mixin class $GalleryHistoryEntryCopyWith<$Res>  {
  factory $GalleryHistoryEntryCopyWith(GalleryHistoryEntry value, $Res Function(GalleryHistoryEntry) _then) = _$GalleryHistoryEntryCopyWithImpl;
@useResult
$Res call({
 DeviceSnapshot device, GalleryScanSnapshot result, List<FileCatalogEntry> items, double scrollOffset, GalleryScanSnapshot? pendingResult
});


$DeviceSnapshotCopyWith<$Res> get device;$GalleryScanSnapshotCopyWith<$Res> get result;$GalleryScanSnapshotCopyWith<$Res>? get pendingResult;

}
/// @nodoc
class _$GalleryHistoryEntryCopyWithImpl<$Res>
    implements $GalleryHistoryEntryCopyWith<$Res> {
  _$GalleryHistoryEntryCopyWithImpl(this._self, this._then);

  final GalleryHistoryEntry _self;
  final $Res Function(GalleryHistoryEntry) _then;

/// Create a copy of GalleryHistoryEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? device = null,Object? result = null,Object? items = null,Object? scrollOffset = null,Object? pendingResult = freezed,}) {
  return _then(GalleryHistoryEntry(
device: null == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as DeviceSnapshot,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as GalleryScanSnapshot,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,scrollOffset: null == scrollOffset ? _self.scrollOffset : scrollOffset // ignore: cast_nullable_to_non_nullable
as double,pendingResult: freezed == pendingResult ? _self.pendingResult : pendingResult // ignore: cast_nullable_to_non_nullable
as GalleryScanSnapshot?,
  ));
}
/// Create a copy of GalleryHistoryEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceSnapshotCopyWith<$Res> get device {
  
  return $DeviceSnapshotCopyWith<$Res>(_self.device, (value) {
    return _then(_self.copyWith(device: value));
  });
}/// Create a copy of GalleryHistoryEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryScanSnapshotCopyWith<$Res> get result {
  
  return $GalleryScanSnapshotCopyWith<$Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}/// Create a copy of GalleryHistoryEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryScanSnapshotCopyWith<$Res>? get pendingResult {
    if (_self.pendingResult == null) {
    return null;
  }

  return $GalleryScanSnapshotCopyWith<$Res>(_self.pendingResult!, (value) {
    return _then(_self.copyWith(pendingResult: value));
  });
}
}


/// Adds pattern-matching-related methods to [GalleryHistoryEntry].
extension GalleryHistoryEntryPatterns on GalleryHistoryEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GalleryHistoryEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GalleryHistoryEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GalleryHistoryEntry value)  $default,){
final _that = this;
switch (_that) {
case _GalleryHistoryEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GalleryHistoryEntry value)?  $default,){
final _that = this;
switch (_that) {
case _GalleryHistoryEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DeviceSnapshot device,  GalleryScanSnapshot result,  List<FileCatalogEntry> items,  double scrollOffset,  GalleryScanSnapshot? pendingResult)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GalleryHistoryEntry() when $default != null:
return $default(_that.device,_that.result,_that.items,_that.scrollOffset,_that.pendingResult);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DeviceSnapshot device,  GalleryScanSnapshot result,  List<FileCatalogEntry> items,  double scrollOffset,  GalleryScanSnapshot? pendingResult)  $default,) {final _that = this;
switch (_that) {
case _GalleryHistoryEntry():
return $default(_that.device,_that.result,_that.items,_that.scrollOffset,_that.pendingResult);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DeviceSnapshot device,  GalleryScanSnapshot result,  List<FileCatalogEntry> items,  double scrollOffset,  GalleryScanSnapshot? pendingResult)?  $default,) {final _that = this;
switch (_that) {
case _GalleryHistoryEntry() when $default != null:
return $default(_that.device,_that.result,_that.items,_that.scrollOffset,_that.pendingResult);case _:
  return null;

}
}

}

/// @nodoc


class _GalleryHistoryEntry extends GalleryHistoryEntry {
  const _GalleryHistoryEntry({required this.device, required this.result, required  List<FileCatalogEntry> items, required this.scrollOffset, this.pendingResult}): _items = items,super._();
  

@override final  DeviceSnapshot device;
@override final  GalleryScanSnapshot result;
 final  List<FileCatalogEntry> _items;
@override List<FileCatalogEntry> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  double scrollOffset;
@override final  GalleryScanSnapshot? pendingResult;

/// Create a copy of GalleryHistoryEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GalleryHistoryEntryCopyWith<_GalleryHistoryEntry> get copyWith => __$GalleryHistoryEntryCopyWithImpl<_GalleryHistoryEntry>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GalleryHistoryEntry&&(identical(other.device, device) || other.device == device)&&(identical(other.result, result) || other.result == result)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.scrollOffset, scrollOffset) || other.scrollOffset == scrollOffset)&&(identical(other.pendingResult, pendingResult) || other.pendingResult == pendingResult));
}


@override
int get hashCode {
    return Object.hash(runtimeType,device,result,const DeepCollectionEquality().hash(_items),scrollOffset,pendingResult);
}

@override
String toString() {
    return 'GalleryHistoryEntry(device: $device, result: $result, items: $items, scrollOffset: $scrollOffset, pendingResult: $pendingResult)';
}


}

/// @nodoc
abstract mixin class _$GalleryHistoryEntryCopyWith<$Res> implements $GalleryHistoryEntryCopyWith<$Res> {
  factory _$GalleryHistoryEntryCopyWith(_GalleryHistoryEntry value, $Res Function(_GalleryHistoryEntry) _then) = __$GalleryHistoryEntryCopyWithImpl;
@override @useResult
$Res call({
 DeviceSnapshot device, GalleryScanSnapshot result, List<FileCatalogEntry> items, double scrollOffset, GalleryScanSnapshot? pendingResult
});


@override $DeviceSnapshotCopyWith<$Res> get device;@override $GalleryScanSnapshotCopyWith<$Res> get result;@override $GalleryScanSnapshotCopyWith<$Res>? get pendingResult;

}
/// @nodoc
class __$GalleryHistoryEntryCopyWithImpl<$Res>
    implements _$GalleryHistoryEntryCopyWith<$Res> {
  __$GalleryHistoryEntryCopyWithImpl(this._self, this._then);

  final _GalleryHistoryEntry _self;
  final $Res Function(_GalleryHistoryEntry) _then;

/// Create a copy of GalleryHistoryEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? device = null,Object? result = null,Object? items = null,Object? scrollOffset = null,Object? pendingResult = freezed,}) {
  return _then(_GalleryHistoryEntry(
device: null == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as DeviceSnapshot,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as GalleryScanSnapshot,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,scrollOffset: null == scrollOffset ? _self.scrollOffset : scrollOffset // ignore: cast_nullable_to_non_nullable
as double,pendingResult: freezed == pendingResult ? _self.pendingResult : pendingResult // ignore: cast_nullable_to_non_nullable
as GalleryScanSnapshot?,
  ));
}

/// Create a copy of GalleryHistoryEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeviceSnapshotCopyWith<$Res> get device {
  
  return $DeviceSnapshotCopyWith<$Res>(_self.device, (value) {
    return _then(_self.copyWith(device: value));
  });
}/// Create a copy of GalleryHistoryEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryScanSnapshotCopyWith<$Res> get result {
  
  return $GalleryScanSnapshotCopyWith<$Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}/// Create a copy of GalleryHistoryEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryScanSnapshotCopyWith<$Res>? get pendingResult {
    if (_self.pendingResult == null) {
    return null;
  }

  return $GalleryScanSnapshotCopyWith<$Res>(_self.pendingResult!, (value) {
    return _then(_self.copyWith(pendingResult: value));
  });
}
}

// dart format on
