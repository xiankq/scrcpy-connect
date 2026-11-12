// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'gallery_scan_notifier.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GalleryScanState {

 GalleryScanSnapshot? get result; GalleryScanSnapshot? get latest; GalleryScanSnapshot? get pendingResult; List<FileCatalogEntry> get items; List<FileCatalogEntry> get pendingItems; bool get showingPrevious; bool get starting; bool get paging; bool get stopping; String? get error;
/// Create a copy of GalleryScanState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GalleryScanStateCopyWith<GalleryScanState> get copyWith => _$GalleryScanStateCopyWithImpl<GalleryScanState>(this as GalleryScanState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GalleryScanState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryScanState&&(identical(other.result, _this.result) || other.result == _this.result)&&(identical(other.latest, _this.latest) || other.latest == _this.latest)&&(identical(other.pendingResult, _this.pendingResult) || other.pendingResult == _this.pendingResult)&&const DeepCollectionEquality().equals(other.items, _this.items)&&const DeepCollectionEquality().equals(other.pendingItems, _this.pendingItems)&&(identical(other.showingPrevious, _this.showingPrevious) || other.showingPrevious == _this.showingPrevious)&&(identical(other.starting, _this.starting) || other.starting == _this.starting)&&(identical(other.paging, _this.paging) || other.paging == _this.paging)&&(identical(other.stopping, _this.stopping) || other.stopping == _this.stopping)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as GalleryScanState;
  return Object.hash(runtimeType,_this.result,_this.latest,_this.pendingResult,const DeepCollectionEquality().hash(_this.items),const DeepCollectionEquality().hash(_this.pendingItems),_this.showingPrevious,_this.starting,_this.paging,_this.stopping,_this.error);
}

@override
String toString() {
  final _this = this as GalleryScanState;
  return 'GalleryScanState(result: ${_this.result}, latest: ${_this.latest}, pendingResult: ${_this.pendingResult}, items: ${_this.items}, pendingItems: ${_this.pendingItems}, showingPrevious: ${_this.showingPrevious}, starting: ${_this.starting}, paging: ${_this.paging}, stopping: ${_this.stopping}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $GalleryScanStateCopyWith<$Res>  {
  factory $GalleryScanStateCopyWith(GalleryScanState value, $Res Function(GalleryScanState) _then) = _$GalleryScanStateCopyWithImpl;
@useResult
$Res call({
 GalleryScanSnapshot? result, GalleryScanSnapshot? latest, GalleryScanSnapshot? pendingResult, List<FileCatalogEntry> items, List<FileCatalogEntry> pendingItems, bool showingPrevious, bool starting, bool paging, bool stopping, String? error
});


$GalleryScanSnapshotCopyWith<$Res>? get result;$GalleryScanSnapshotCopyWith<$Res>? get latest;$GalleryScanSnapshotCopyWith<$Res>? get pendingResult;

}
/// @nodoc
class _$GalleryScanStateCopyWithImpl<$Res>
    implements $GalleryScanStateCopyWith<$Res> {
  _$GalleryScanStateCopyWithImpl(this._self, this._then);

  final GalleryScanState _self;
  final $Res Function(GalleryScanState) _then;

/// Create a copy of GalleryScanState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? result = freezed,Object? latest = freezed,Object? pendingResult = freezed,Object? items = null,Object? pendingItems = null,Object? showingPrevious = null,Object? starting = null,Object? paging = null,Object? stopping = null,Object? error = freezed,}) {
  return _then(GalleryScanState(
result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as GalleryScanSnapshot?,latest: freezed == latest ? _self.latest : latest // ignore: cast_nullable_to_non_nullable
as GalleryScanSnapshot?,pendingResult: freezed == pendingResult ? _self.pendingResult : pendingResult // ignore: cast_nullable_to_non_nullable
as GalleryScanSnapshot?,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,pendingItems: null == pendingItems ? _self.pendingItems : pendingItems // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,showingPrevious: null == showingPrevious ? _self.showingPrevious : showingPrevious // ignore: cast_nullable_to_non_nullable
as bool,starting: null == starting ? _self.starting : starting // ignore: cast_nullable_to_non_nullable
as bool,paging: null == paging ? _self.paging : paging // ignore: cast_nullable_to_non_nullable
as bool,stopping: null == stopping ? _self.stopping : stopping // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of GalleryScanState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryScanSnapshotCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $GalleryScanSnapshotCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}/// Create a copy of GalleryScanState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryScanSnapshotCopyWith<$Res>? get latest {
    if (_self.latest == null) {
    return null;
  }

  return $GalleryScanSnapshotCopyWith<$Res>(_self.latest!, (value) {
    return _then(_self.copyWith(latest: value));
  });
}/// Create a copy of GalleryScanState
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


/// Adds pattern-matching-related methods to [GalleryScanState].
extension GalleryScanStatePatterns on GalleryScanState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GalleryScanState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GalleryScanState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GalleryScanState value)  $default,){
final _that = this;
switch (_that) {
case _GalleryScanState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GalleryScanState value)?  $default,){
final _that = this;
switch (_that) {
case _GalleryScanState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( GalleryScanSnapshot? result,  GalleryScanSnapshot? latest,  GalleryScanSnapshot? pendingResult,  List<FileCatalogEntry> items,  List<FileCatalogEntry> pendingItems,  bool showingPrevious,  bool starting,  bool paging,  bool stopping,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GalleryScanState() when $default != null:
return $default(_that.result,_that.latest,_that.pendingResult,_that.items,_that.pendingItems,_that.showingPrevious,_that.starting,_that.paging,_that.stopping,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( GalleryScanSnapshot? result,  GalleryScanSnapshot? latest,  GalleryScanSnapshot? pendingResult,  List<FileCatalogEntry> items,  List<FileCatalogEntry> pendingItems,  bool showingPrevious,  bool starting,  bool paging,  bool stopping,  String? error)  $default,) {final _that = this;
switch (_that) {
case _GalleryScanState():
return $default(_that.result,_that.latest,_that.pendingResult,_that.items,_that.pendingItems,_that.showingPrevious,_that.starting,_that.paging,_that.stopping,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( GalleryScanSnapshot? result,  GalleryScanSnapshot? latest,  GalleryScanSnapshot? pendingResult,  List<FileCatalogEntry> items,  List<FileCatalogEntry> pendingItems,  bool showingPrevious,  bool starting,  bool paging,  bool stopping,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _GalleryScanState() when $default != null:
return $default(_that.result,_that.latest,_that.pendingResult,_that.items,_that.pendingItems,_that.showingPrevious,_that.starting,_that.paging,_that.stopping,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _GalleryScanState extends GalleryScanState {
  const _GalleryScanState({this.result, this.latest, this.pendingResult,  List<FileCatalogEntry> items = const [],  List<FileCatalogEntry> pendingItems = const [], this.showingPrevious = false, this.starting = false, this.paging = false, this.stopping = false, this.error}): _items = items,_pendingItems = pendingItems,super._();
  

@override final  GalleryScanSnapshot? result;
@override final  GalleryScanSnapshot? latest;
@override final  GalleryScanSnapshot? pendingResult;
 final  List<FileCatalogEntry> _items;
@override@JsonKey() List<FileCatalogEntry> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

 final  List<FileCatalogEntry> _pendingItems;
@override@JsonKey() List<FileCatalogEntry> get pendingItems {
  if (_pendingItems is EqualUnmodifiableListView) return _pendingItems;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_pendingItems);
}

@override@JsonKey() final  bool showingPrevious;
@override@JsonKey() final  bool starting;
@override@JsonKey() final  bool paging;
@override@JsonKey() final  bool stopping;
@override final  String? error;

/// Create a copy of GalleryScanState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GalleryScanStateCopyWith<_GalleryScanState> get copyWith => __$GalleryScanStateCopyWithImpl<_GalleryScanState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GalleryScanState&&(identical(other.result, result) || other.result == result)&&(identical(other.latest, latest) || other.latest == latest)&&(identical(other.pendingResult, pendingResult) || other.pendingResult == pendingResult)&&const DeepCollectionEquality().equals(other.items, _items)&&const DeepCollectionEquality().equals(other.pendingItems, _pendingItems)&&(identical(other.showingPrevious, showingPrevious) || other.showingPrevious == showingPrevious)&&(identical(other.starting, starting) || other.starting == starting)&&(identical(other.paging, paging) || other.paging == paging)&&(identical(other.stopping, stopping) || other.stopping == stopping)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,result,latest,pendingResult,const DeepCollectionEquality().hash(_items),const DeepCollectionEquality().hash(_pendingItems),showingPrevious,starting,paging,stopping,error);
}

@override
String toString() {
    return 'GalleryScanState(result: $result, latest: $latest, pendingResult: $pendingResult, items: $items, pendingItems: $pendingItems, showingPrevious: $showingPrevious, starting: $starting, paging: $paging, stopping: $stopping, error: $error)';
}


}

/// @nodoc
abstract mixin class _$GalleryScanStateCopyWith<$Res> implements $GalleryScanStateCopyWith<$Res> {
  factory _$GalleryScanStateCopyWith(_GalleryScanState value, $Res Function(_GalleryScanState) _then) = __$GalleryScanStateCopyWithImpl;
@override @useResult
$Res call({
 GalleryScanSnapshot? result, GalleryScanSnapshot? latest, GalleryScanSnapshot? pendingResult, List<FileCatalogEntry> items, List<FileCatalogEntry> pendingItems, bool showingPrevious, bool starting, bool paging, bool stopping, String? error
});


@override $GalleryScanSnapshotCopyWith<$Res>? get result;@override $GalleryScanSnapshotCopyWith<$Res>? get latest;@override $GalleryScanSnapshotCopyWith<$Res>? get pendingResult;

}
/// @nodoc
class __$GalleryScanStateCopyWithImpl<$Res>
    implements _$GalleryScanStateCopyWith<$Res> {
  __$GalleryScanStateCopyWithImpl(this._self, this._then);

  final _GalleryScanState _self;
  final $Res Function(_GalleryScanState) _then;

/// Create a copy of GalleryScanState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? result = freezed,Object? latest = freezed,Object? pendingResult = freezed,Object? items = null,Object? pendingItems = null,Object? showingPrevious = null,Object? starting = null,Object? paging = null,Object? stopping = null,Object? error = freezed,}) {
  return _then(_GalleryScanState(
result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as GalleryScanSnapshot?,latest: freezed == latest ? _self.latest : latest // ignore: cast_nullable_to_non_nullable
as GalleryScanSnapshot?,pendingResult: freezed == pendingResult ? _self.pendingResult : pendingResult // ignore: cast_nullable_to_non_nullable
as GalleryScanSnapshot?,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,pendingItems: null == pendingItems ? _self._pendingItems : pendingItems // ignore: cast_nullable_to_non_nullable
as List<FileCatalogEntry>,showingPrevious: null == showingPrevious ? _self.showingPrevious : showingPrevious // ignore: cast_nullable_to_non_nullable
as bool,starting: null == starting ? _self.starting : starting // ignore: cast_nullable_to_non_nullable
as bool,paging: null == paging ? _self.paging : paging // ignore: cast_nullable_to_non_nullable
as bool,stopping: null == stopping ? _self.stopping : stopping // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of GalleryScanState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryScanSnapshotCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $GalleryScanSnapshotCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}/// Create a copy of GalleryScanState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryScanSnapshotCopyWith<$Res>? get latest {
    if (_self.latest == null) {
    return null;
  }

  return $GalleryScanSnapshotCopyWith<$Res>(_self.latest!, (value) {
    return _then(_self.copyWith(latest: value));
  });
}/// Create a copy of GalleryScanState
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
