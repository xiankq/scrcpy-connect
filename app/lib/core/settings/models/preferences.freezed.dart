// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'preferences.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VideoQualityPreferences {


/// Create a copy of VideoQualityPreferences
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoQualityPreferencesCopyWith<VideoQualityPreferences> get copyWith => _$VideoQualityPreferencesCopyWithImpl<VideoQualityPreferences>(this as VideoQualityPreferences, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoQualityPreferences;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoQualityPreferences&&(identical(other.qualityPreset, _this.qualityPreset) || other.qualityPreset == _this.qualityPreset)&&(identical(other.maxSize, _this.maxSize) || other.maxSize == _this.maxSize)&&(identical(other.maxFps, _this.maxFps) || other.maxFps == _this.maxFps)&&(identical(other.videoBitRate, _this.videoBitRate) || other.videoBitRate == _this.videoBitRate)&&(identical(other.videoCodec, _this.videoCodec) || other.videoCodec == _this.videoCodec)&&(identical(other.videoEncoder, _this.videoEncoder) || other.videoEncoder == _this.videoEncoder));
}


@override
int get hashCode {
  final _this = this as VideoQualityPreferences;
  return Object.hash(runtimeType,_this.qualityPreset,_this.maxSize,_this.maxFps,_this.videoBitRate,_this.videoCodec,_this.videoEncoder);
}

@override
String toString() {
  final _this = this as VideoQualityPreferences;
  return 'VideoQualityPreferences(qualityPreset: ${_this.qualityPreset}, maxSize: ${_this.maxSize}, maxFps: ${_this.maxFps}, videoBitRate: ${_this.videoBitRate}, videoCodec: ${_this.videoCodec}, videoEncoder: ${_this.videoEncoder})';
}


}

/// @nodoc
abstract mixin class $VideoQualityPreferencesCopyWith<$Res>  {
  factory $VideoQualityPreferencesCopyWith(VideoQualityPreferences value, $Res Function(VideoQualityPreferences) _then) = _$VideoQualityPreferencesCopyWithImpl;
@useResult
$Res call({
 ({String? name,})? qualityPreset, int? maxSize, int? maxFps, int? videoBitRate, VideoCodec? videoCodec, ({String? name,})? videoEncoder
});




}
/// @nodoc
class _$VideoQualityPreferencesCopyWithImpl<$Res>
    implements $VideoQualityPreferencesCopyWith<$Res> {
  _$VideoQualityPreferencesCopyWithImpl(this._self, this._then);

  final VideoQualityPreferences _self;
  final $Res Function(VideoQualityPreferences) _then;

/// Create a copy of VideoQualityPreferences
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? qualityPreset = freezed,Object? maxSize = freezed,Object? maxFps = freezed,Object? videoBitRate = freezed,Object? videoCodec = freezed,Object? videoEncoder = freezed,}) {
  return _then(VideoQualityPreferences(
qualityPreset: freezed == qualityPreset ? _self.qualityPreset : qualityPreset // ignore: cast_nullable_to_non_nullable
as ({String? name,})?,maxSize: freezed == maxSize ? _self.maxSize : maxSize // ignore: cast_nullable_to_non_nullable
as int?,maxFps: freezed == maxFps ? _self.maxFps : maxFps // ignore: cast_nullable_to_non_nullable
as int?,videoBitRate: freezed == videoBitRate ? _self.videoBitRate : videoBitRate // ignore: cast_nullable_to_non_nullable
as int?,videoCodec: freezed == videoCodec ? _self.videoCodec : videoCodec // ignore: cast_nullable_to_non_nullable
as VideoCodec?,videoEncoder: freezed == videoEncoder ? _self.videoEncoder : videoEncoder // ignore: cast_nullable_to_non_nullable
as ({String? name,})?,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoQualityPreferences].
extension VideoQualityPreferencesPatterns on VideoQualityPreferences {
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
mixin _$DevicePreferences {


/// Create a copy of DevicePreferences
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DevicePreferencesCopyWith<DevicePreferences> get copyWith => _$DevicePreferencesCopyWithImpl<DevicePreferences>(this as DevicePreferences, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DevicePreferences;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DevicePreferences&&(identical(other.clipboardSync, _this.clipboardSync) || other.clipboardSync == _this.clipboardSync)&&(identical(other.showNavigationBar, _this.showNavigationBar) || other.showNavigationBar == _this.showNavigationBar)&&(identical(other.wakeOnConnect, _this.wakeOnConnect) || other.wakeOnConnect == _this.wakeOnConnect)&&(identical(other.lockOnClose, _this.lockOnClose) || other.lockOnClose == _this.lockOnClose)&&(identical(other.stayAwake, _this.stayAwake) || other.stayAwake == _this.stayAwake)&&(identical(other.remoteAspectRatio, _this.remoteAspectRatio) || other.remoteAspectRatio == _this.remoteAspectRatio)&&(identical(other.remoteCustomRatio, _this.remoteCustomRatio) || other.remoteCustomRatio == _this.remoteCustomRatio)&&const DeepCollectionEquality().equals(other.favoriteApps, _this.favoriteApps));
}


@override
int get hashCode {
  final _this = this as DevicePreferences;
  return Object.hash(runtimeType,_this.clipboardSync,_this.showNavigationBar,_this.wakeOnConnect,_this.lockOnClose,_this.stayAwake,_this.remoteAspectRatio,_this.remoteCustomRatio,const DeepCollectionEquality().hash(_this.favoriteApps));
}

@override
String toString() {
  final _this = this as DevicePreferences;
  return 'DevicePreferences(clipboardSync: ${_this.clipboardSync}, showNavigationBar: ${_this.showNavigationBar}, wakeOnConnect: ${_this.wakeOnConnect}, lockOnClose: ${_this.lockOnClose}, stayAwake: ${_this.stayAwake}, remoteAspectRatio: ${_this.remoteAspectRatio}, remoteCustomRatio: ${_this.remoteCustomRatio}, favoriteApps: ${_this.favoriteApps})';
}


}

/// @nodoc
abstract mixin class $DevicePreferencesCopyWith<$Res>  {
  factory $DevicePreferencesCopyWith(DevicePreferences value, $Res Function(DevicePreferences) _then) = _$DevicePreferencesCopyWithImpl;
@useResult
$Res call({
 bool? clipboardSync, bool? showNavigationBar, bool? wakeOnConnect, bool? lockOnClose, bool? stayAwake, ScreenAspectRatio? remoteAspectRatio, String? remoteCustomRatio, List<FavoriteDeviceApp>? favoriteApps
});




}
/// @nodoc
class _$DevicePreferencesCopyWithImpl<$Res>
    implements $DevicePreferencesCopyWith<$Res> {
  _$DevicePreferencesCopyWithImpl(this._self, this._then);

  final DevicePreferences _self;
  final $Res Function(DevicePreferences) _then;

/// Create a copy of DevicePreferences
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? clipboardSync = freezed,Object? showNavigationBar = freezed,Object? wakeOnConnect = freezed,Object? lockOnClose = freezed,Object? stayAwake = freezed,Object? remoteAspectRatio = freezed,Object? remoteCustomRatio = freezed,Object? favoriteApps = freezed,}) {
  return _then(DevicePreferences(
clipboardSync: freezed == clipboardSync ? _self.clipboardSync : clipboardSync // ignore: cast_nullable_to_non_nullable
as bool?,showNavigationBar: freezed == showNavigationBar ? _self.showNavigationBar : showNavigationBar // ignore: cast_nullable_to_non_nullable
as bool?,wakeOnConnect: freezed == wakeOnConnect ? _self.wakeOnConnect : wakeOnConnect // ignore: cast_nullable_to_non_nullable
as bool?,lockOnClose: freezed == lockOnClose ? _self.lockOnClose : lockOnClose // ignore: cast_nullable_to_non_nullable
as bool?,stayAwake: freezed == stayAwake ? _self.stayAwake : stayAwake // ignore: cast_nullable_to_non_nullable
as bool?,remoteAspectRatio: freezed == remoteAspectRatio ? _self.remoteAspectRatio : remoteAspectRatio // ignore: cast_nullable_to_non_nullable
as ScreenAspectRatio?,remoteCustomRatio: freezed == remoteCustomRatio ? _self.remoteCustomRatio : remoteCustomRatio // ignore: cast_nullable_to_non_nullable
as String?,favoriteApps: freezed == favoriteApps ? _self.favoriteApps : favoriteApps // ignore: cast_nullable_to_non_nullable
as List<FavoriteDeviceApp>?,
  ));
}

}


/// Adds pattern-matching-related methods to [DevicePreferences].
extension DevicePreferencesPatterns on DevicePreferences {
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
mixin _$Preferences {


/// Create a copy of Preferences
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PreferencesCopyWith<Preferences> get copyWith => _$PreferencesCopyWithImpl<Preferences>(this as Preferences, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Preferences;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Preferences&&(identical(other.appearance, _this.appearance) || other.appearance == _this.appearance)&&(identical(other.backgroundKeepAlive, _this.backgroundKeepAlive) || other.backgroundKeepAlive == _this.backgroundKeepAlive)&&(identical(other.notificationAlerts, _this.notificationAlerts) || other.notificationAlerts == _this.notificationAlerts)&&(identical(other.callAlerts, _this.callAlerts) || other.callAlerts == _this.callAlerts)&&(identical(other.adbBurstMode, _this.adbBurstMode) || other.adbBurstMode == _this.adbBurstMode)&&(identical(other.fileViewMode, _this.fileViewMode) || other.fileViewMode == _this.fileViewMode)&&(identical(other.fileSortKey, _this.fileSortKey) || other.fileSortKey == _this.fileSortKey)&&(identical(other.fileSortAscending, _this.fileSortAscending) || other.fileSortAscending == _this.fileSortAscending)&&(identical(other.quality, _this.quality) || other.quality == _this.quality)&&const DeepCollectionEquality().equals(other.deviceSettings, _this.deviceSettings)&&const DeepCollectionEquality().equals(other.appOpenModes, _this.appOpenModes)&&const DeepCollectionEquality().equals(other.deviceQuality, _this.deviceQuality));
}


@override
int get hashCode {
  final _this = this as Preferences;
  return Object.hash(runtimeType,_this.appearance,_this.backgroundKeepAlive,_this.notificationAlerts,_this.callAlerts,_this.adbBurstMode,_this.fileViewMode,_this.fileSortKey,_this.fileSortAscending,_this.quality,const DeepCollectionEquality().hash(_this.deviceSettings),const DeepCollectionEquality().hash(_this.appOpenModes),const DeepCollectionEquality().hash(_this.deviceQuality));
}

@override
String toString() {
  final _this = this as Preferences;
  return 'Preferences(appearance: ${_this.appearance}, backgroundKeepAlive: ${_this.backgroundKeepAlive}, notificationAlerts: ${_this.notificationAlerts}, callAlerts: ${_this.callAlerts}, adbBurstMode: ${_this.adbBurstMode}, fileViewMode: ${_this.fileViewMode}, fileSortKey: ${_this.fileSortKey}, fileSortAscending: ${_this.fileSortAscending}, quality: ${_this.quality}, deviceSettings: ${_this.deviceSettings}, appOpenModes: ${_this.appOpenModes}, deviceQuality: ${_this.deviceQuality})';
}


}

/// @nodoc
abstract mixin class $PreferencesCopyWith<$Res>  {
  factory $PreferencesCopyWith(Preferences value, $Res Function(Preferences) _then) = _$PreferencesCopyWithImpl;
@useResult
$Res call({
 Appearance appearance, bool backgroundKeepAlive, bool notificationAlerts, bool callAlerts, bool adbBurstMode, FileViewMode fileViewMode, FileSortKey fileSortKey, bool fileSortAscending, VideoQualityPreferences quality, Map<String, DevicePreferences> deviceSettings, Map<String, Map<String, AppOpenMode>> appOpenModes, Map<String, VideoQualityPreferences> deviceQuality
});


$VideoQualityPreferencesCopyWith<$Res> get quality;

}
/// @nodoc
class _$PreferencesCopyWithImpl<$Res>
    implements $PreferencesCopyWith<$Res> {
  _$PreferencesCopyWithImpl(this._self, this._then);

  final Preferences _self;
  final $Res Function(Preferences) _then;

/// Create a copy of Preferences
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? appearance = null,Object? backgroundKeepAlive = null,Object? notificationAlerts = null,Object? callAlerts = null,Object? adbBurstMode = null,Object? fileViewMode = null,Object? fileSortKey = null,Object? fileSortAscending = null,Object? quality = null,Object? deviceSettings = null,Object? appOpenModes = null,Object? deviceQuality = null,}) {
  return _then(Preferences(
appearance: null == appearance ? _self.appearance : appearance // ignore: cast_nullable_to_non_nullable
as Appearance,backgroundKeepAlive: null == backgroundKeepAlive ? _self.backgroundKeepAlive : backgroundKeepAlive // ignore: cast_nullable_to_non_nullable
as bool,notificationAlerts: null == notificationAlerts ? _self.notificationAlerts : notificationAlerts // ignore: cast_nullable_to_non_nullable
as bool,callAlerts: null == callAlerts ? _self.callAlerts : callAlerts // ignore: cast_nullable_to_non_nullable
as bool,adbBurstMode: null == adbBurstMode ? _self.adbBurstMode : adbBurstMode // ignore: cast_nullable_to_non_nullable
as bool,fileViewMode: null == fileViewMode ? _self.fileViewMode : fileViewMode // ignore: cast_nullable_to_non_nullable
as FileViewMode,fileSortKey: null == fileSortKey ? _self.fileSortKey : fileSortKey // ignore: cast_nullable_to_non_nullable
as FileSortKey,fileSortAscending: null == fileSortAscending ? _self.fileSortAscending : fileSortAscending // ignore: cast_nullable_to_non_nullable
as bool,quality: null == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as VideoQualityPreferences,deviceSettings: null == deviceSettings ? _self.deviceSettings : deviceSettings // ignore: cast_nullable_to_non_nullable
as Map<String, DevicePreferences>,appOpenModes: null == appOpenModes ? _self.appOpenModes : appOpenModes // ignore: cast_nullable_to_non_nullable
as Map<String, Map<String, AppOpenMode>>,deviceQuality: null == deviceQuality ? _self.deviceQuality : deviceQuality // ignore: cast_nullable_to_non_nullable
as Map<String, VideoQualityPreferences>,
  ));
}
/// Create a copy of Preferences
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoQualityPreferencesCopyWith<$Res> get quality {
  
  return $VideoQualityPreferencesCopyWith<$Res>(_self.quality, (value) {
    return _then(_self.copyWith(quality: value));
  });
}
}


/// Adds pattern-matching-related methods to [Preferences].
extension PreferencesPatterns on Preferences {
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
mixin _$PreferenceChanges {


/// Create a copy of PreferenceChanges
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PreferenceChangesCopyWith<PreferenceChanges> get copyWith => _$PreferenceChangesCopyWithImpl<PreferenceChanges>(this as PreferenceChanges, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PreferenceChanges;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PreferenceChanges&&(identical(other.appearance, _this.appearance) || other.appearance == _this.appearance)&&(identical(other.backgroundKeepAlive, _this.backgroundKeepAlive) || other.backgroundKeepAlive == _this.backgroundKeepAlive)&&(identical(other.notificationAlerts, _this.notificationAlerts) || other.notificationAlerts == _this.notificationAlerts)&&(identical(other.callAlerts, _this.callAlerts) || other.callAlerts == _this.callAlerts)&&(identical(other.adbBurstMode, _this.adbBurstMode) || other.adbBurstMode == _this.adbBurstMode)&&(identical(other.fileViewMode, _this.fileViewMode) || other.fileViewMode == _this.fileViewMode)&&(identical(other.fileSortKey, _this.fileSortKey) || other.fileSortKey == _this.fileSortKey)&&(identical(other.fileSortAscending, _this.fileSortAscending) || other.fileSortAscending == _this.fileSortAscending)&&(identical(other.quality, _this.quality) || other.quality == _this.quality)&&const DeepCollectionEquality().equals(other.deviceSettings, _this.deviceSettings)&&const DeepCollectionEquality().equals(other.appOpenModes, _this.appOpenModes)&&const DeepCollectionEquality().equals(other.deviceQuality, _this.deviceQuality));
}


@override
int get hashCode {
  final _this = this as PreferenceChanges;
  return Object.hash(runtimeType,_this.appearance,_this.backgroundKeepAlive,_this.notificationAlerts,_this.callAlerts,_this.adbBurstMode,_this.fileViewMode,_this.fileSortKey,_this.fileSortAscending,_this.quality,const DeepCollectionEquality().hash(_this.deviceSettings),const DeepCollectionEquality().hash(_this.appOpenModes),const DeepCollectionEquality().hash(_this.deviceQuality));
}

@override
String toString() {
  final _this = this as PreferenceChanges;
  return 'PreferenceChanges(appearance: ${_this.appearance}, backgroundKeepAlive: ${_this.backgroundKeepAlive}, notificationAlerts: ${_this.notificationAlerts}, callAlerts: ${_this.callAlerts}, adbBurstMode: ${_this.adbBurstMode}, fileViewMode: ${_this.fileViewMode}, fileSortKey: ${_this.fileSortKey}, fileSortAscending: ${_this.fileSortAscending}, quality: ${_this.quality}, deviceSettings: ${_this.deviceSettings}, appOpenModes: ${_this.appOpenModes}, deviceQuality: ${_this.deviceQuality})';
}


}

/// @nodoc
abstract mixin class $PreferenceChangesCopyWith<$Res>  {
  factory $PreferenceChangesCopyWith(PreferenceChanges value, $Res Function(PreferenceChanges) _then) = _$PreferenceChangesCopyWithImpl;
@useResult
$Res call({
 Appearance? appearance, bool? backgroundKeepAlive, bool? notificationAlerts, bool? callAlerts, bool? adbBurstMode, FileViewMode? fileViewMode, FileSortKey? fileSortKey, bool? fileSortAscending, VideoQualityPreferences quality, Map<String, DevicePreferences>? deviceSettings, Map<String, Map<String, AppOpenMode>>? appOpenModes, Map<String, VideoQualityPreferences>? deviceQuality
});


$VideoQualityPreferencesCopyWith<$Res> get quality;

}
/// @nodoc
class _$PreferenceChangesCopyWithImpl<$Res>
    implements $PreferenceChangesCopyWith<$Res> {
  _$PreferenceChangesCopyWithImpl(this._self, this._then);

  final PreferenceChanges _self;
  final $Res Function(PreferenceChanges) _then;

/// Create a copy of PreferenceChanges
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? appearance = freezed,Object? backgroundKeepAlive = freezed,Object? notificationAlerts = freezed,Object? callAlerts = freezed,Object? adbBurstMode = freezed,Object? fileViewMode = freezed,Object? fileSortKey = freezed,Object? fileSortAscending = freezed,Object? quality = null,Object? deviceSettings = freezed,Object? appOpenModes = freezed,Object? deviceQuality = freezed,}) {
  return _then(PreferenceChanges(
appearance: freezed == appearance ? _self.appearance : appearance // ignore: cast_nullable_to_non_nullable
as Appearance?,backgroundKeepAlive: freezed == backgroundKeepAlive ? _self.backgroundKeepAlive : backgroundKeepAlive // ignore: cast_nullable_to_non_nullable
as bool?,notificationAlerts: freezed == notificationAlerts ? _self.notificationAlerts : notificationAlerts // ignore: cast_nullable_to_non_nullable
as bool?,callAlerts: freezed == callAlerts ? _self.callAlerts : callAlerts // ignore: cast_nullable_to_non_nullable
as bool?,adbBurstMode: freezed == adbBurstMode ? _self.adbBurstMode : adbBurstMode // ignore: cast_nullable_to_non_nullable
as bool?,fileViewMode: freezed == fileViewMode ? _self.fileViewMode : fileViewMode // ignore: cast_nullable_to_non_nullable
as FileViewMode?,fileSortKey: freezed == fileSortKey ? _self.fileSortKey : fileSortKey // ignore: cast_nullable_to_non_nullable
as FileSortKey?,fileSortAscending: freezed == fileSortAscending ? _self.fileSortAscending : fileSortAscending // ignore: cast_nullable_to_non_nullable
as bool?,quality: null == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as VideoQualityPreferences,deviceSettings: freezed == deviceSettings ? _self.deviceSettings : deviceSettings // ignore: cast_nullable_to_non_nullable
as Map<String, DevicePreferences>?,appOpenModes: freezed == appOpenModes ? _self.appOpenModes : appOpenModes // ignore: cast_nullable_to_non_nullable
as Map<String, Map<String, AppOpenMode>>?,deviceQuality: freezed == deviceQuality ? _self.deviceQuality : deviceQuality // ignore: cast_nullable_to_non_nullable
as Map<String, VideoQualityPreferences>?,
  ));
}
/// Create a copy of PreferenceChanges
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoQualityPreferencesCopyWith<$Res> get quality {
  
  return $VideoQualityPreferencesCopyWith<$Res>(_self.quality, (value) {
    return _then(_self.copyWith(quality: value));
  });
}
}


/// Adds pattern-matching-related methods to [PreferenceChanges].
extension PreferenceChangesPatterns on PreferenceChanges {
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
