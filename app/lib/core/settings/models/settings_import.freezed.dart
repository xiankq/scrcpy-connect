// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_import.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GlobalPreferenceChange {


/// Create a copy of GlobalPreferenceChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GlobalPreferenceChangeCopyWith<GlobalPreferenceChange> get copyWith => _$GlobalPreferenceChangeCopyWithImpl<GlobalPreferenceChange>(this as GlobalPreferenceChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GlobalPreferenceChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GlobalPreferenceChange&&(identical(other.key, _this.key) || other.key == _this.key)&&const DeepCollectionEquality().equals(other.current, _this.current)&&const DeepCollectionEquality().equals(other.imported, _this.imported));
}


@override
int get hashCode {
  final _this = this as GlobalPreferenceChange;
  return Object.hash(runtimeType,_this.key,const DeepCollectionEquality().hash(_this.current),const DeepCollectionEquality().hash(_this.imported));
}

@override
String toString() {
  final _this = this as GlobalPreferenceChange;
  return 'GlobalPreferenceChange(key: ${_this.key}, current: ${_this.current}, imported: ${_this.imported})';
}


}

/// @nodoc
abstract mixin class $GlobalPreferenceChangeCopyWith<$Res>  {
  factory $GlobalPreferenceChangeCopyWith(GlobalPreferenceChange value, $Res Function(GlobalPreferenceChange) _then) = _$GlobalPreferenceChangeCopyWithImpl;
@useResult
$Res call({
 String key, Object? current, Object? imported
});




}
/// @nodoc
class _$GlobalPreferenceChangeCopyWithImpl<$Res>
    implements $GlobalPreferenceChangeCopyWith<$Res> {
  _$GlobalPreferenceChangeCopyWithImpl(this._self, this._then);

  final GlobalPreferenceChange _self;
  final $Res Function(GlobalPreferenceChange) _then;

/// Create a copy of GlobalPreferenceChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? current = freezed,Object? imported = freezed,}) {
  return _then(GlobalPreferenceChange(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,current: freezed == current ? _self.current : current ,imported: freezed == imported ? _self.imported : imported ,
  ));
}

}


/// Adds pattern-matching-related methods to [GlobalPreferenceChange].
extension GlobalPreferenceChangePatterns on GlobalPreferenceChange {
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
mixin _$SettingsImportPreview {


/// Create a copy of SettingsImportPreview
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsImportPreviewCopyWith<SettingsImportPreview> get copyWith => _$SettingsImportPreviewCopyWithImpl<SettingsImportPreview>(this as SettingsImportPreview, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsImportPreview;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsImportPreview&&(identical(other.metadata, _this.metadata) || other.metadata == _this.metadata)&&(identical(other.expectedRevision, _this.expectedRevision) || other.expectedRevision == _this.expectedRevision)&&(identical(other.newRecords, _this.newRecords) || other.newRecords == _this.newRecords)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt)&&(identical(other.preferencesStatus, _this.preferencesStatus) || other.preferencesStatus == _this.preferencesStatus)&&const DeepCollectionEquality().equals(other.globalChanges, _this.globalChanges));
}


@override
int get hashCode {
  final _this = this as SettingsImportPreview;
  return Object.hash(runtimeType,_this.metadata,_this.expectedRevision,_this.newRecords,_this.receipt,_this.preferencesStatus,const DeepCollectionEquality().hash(_this.globalChanges));
}

@override
String toString() {
  final _this = this as SettingsImportPreview;
  return 'SettingsImportPreview(metadata: ${_this.metadata}, expectedRevision: ${_this.expectedRevision}, newRecords: ${_this.newRecords}, receipt: ${_this.receipt}, preferencesStatus: ${_this.preferencesStatus}, globalChanges: ${_this.globalChanges})';
}


}

/// @nodoc
abstract mixin class $SettingsImportPreviewCopyWith<$Res>  {
  factory $SettingsImportPreviewCopyWith(SettingsImportPreview value, $Res Function(SettingsImportPreview) _then) = _$SettingsImportPreviewCopyWithImpl;
@useResult
$Res call({
 DeviceMetadata metadata, int expectedRevision, int newRecords, DeviceRecordsImport? receipt, ImportPreferencesStatus? preferencesStatus, List<GlobalPreferenceChange> globalChanges
});




}
/// @nodoc
class _$SettingsImportPreviewCopyWithImpl<$Res>
    implements $SettingsImportPreviewCopyWith<$Res> {
  _$SettingsImportPreviewCopyWithImpl(this._self, this._then);

  final SettingsImportPreview _self;
  final $Res Function(SettingsImportPreview) _then;

/// Create a copy of SettingsImportPreview
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? metadata = null,Object? expectedRevision = null,Object? newRecords = null,Object? receipt = freezed,Object? preferencesStatus = freezed,Object? globalChanges = null,}) {
  return _then(SettingsImportPreview(
metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as DeviceMetadata,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,newRecords: null == newRecords ? _self.newRecords : newRecords // ignore: cast_nullable_to_non_nullable
as int,receipt: freezed == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as DeviceRecordsImport?,preferencesStatus: freezed == preferencesStatus ? _self.preferencesStatus : preferencesStatus // ignore: cast_nullable_to_non_nullable
as ImportPreferencesStatus?,globalChanges: null == globalChanges ? _self.globalChanges : globalChanges // ignore: cast_nullable_to_non_nullable
as List<GlobalPreferenceChange>,
  ));
}

}


/// Adds pattern-matching-related methods to [SettingsImportPreview].
extension SettingsImportPreviewPatterns on SettingsImportPreview {
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
mixin _$SettingsImportResult {


/// Create a copy of SettingsImportResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsImportResultCopyWith<SettingsImportResult> get copyWith => _$SettingsImportResultCopyWithImpl<SettingsImportResult>(this as SettingsImportResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsImportResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsImportResult&&(identical(other.records, _this.records) || other.records == _this.records)&&(identical(other.preferencesStatus, _this.preferencesStatus) || other.preferencesStatus == _this.preferencesStatus));
}


@override
int get hashCode {
  final _this = this as SettingsImportResult;
  return Object.hash(runtimeType,_this.records,_this.preferencesStatus);
}

@override
String toString() {
  final _this = this as SettingsImportResult;
  return 'SettingsImportResult(records: ${_this.records}, preferencesStatus: ${_this.preferencesStatus})';
}


}

/// @nodoc
abstract mixin class $SettingsImportResultCopyWith<$Res>  {
  factory $SettingsImportResultCopyWith(SettingsImportResult value, $Res Function(SettingsImportResult) _then) = _$SettingsImportResultCopyWithImpl;
@useResult
$Res call({
 DeviceRecordsImport records, ImportPreferencesStatus preferencesStatus
});




}
/// @nodoc
class _$SettingsImportResultCopyWithImpl<$Res>
    implements $SettingsImportResultCopyWith<$Res> {
  _$SettingsImportResultCopyWithImpl(this._self, this._then);

  final SettingsImportResult _self;
  final $Res Function(SettingsImportResult) _then;

/// Create a copy of SettingsImportResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? records = null,Object? preferencesStatus = null,}) {
  return _then(SettingsImportResult(
records: null == records ? _self.records : records // ignore: cast_nullable_to_non_nullable
as DeviceRecordsImport,preferencesStatus: null == preferencesStatus ? _self.preferencesStatus : preferencesStatus // ignore: cast_nullable_to_non_nullable
as ImportPreferencesStatus,
  ));
}

}


/// Adds pattern-matching-related methods to [SettingsImportResult].
extension SettingsImportResultPatterns on SettingsImportResult {
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
