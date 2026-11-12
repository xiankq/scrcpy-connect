// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'clipboard_capture.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ClipboardTarget {

 String get deviceId;
/// Create a copy of ClipboardTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClipboardTargetCopyWith<ClipboardTarget> get copyWith => _$ClipboardTargetCopyWithImpl<ClipboardTarget>(this as ClipboardTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ClipboardTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClipboardTarget&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId));
}


@override
int get hashCode {
  final _this = this as ClipboardTarget;
  return Object.hash(runtimeType,_this.deviceId);
}

@override
String toString() {
  final _this = this as ClipboardTarget;
  return 'ClipboardTarget(deviceId: ${_this.deviceId})';
}


}

/// @nodoc
abstract mixin class $ClipboardTargetCopyWith<$Res>  {
  factory $ClipboardTargetCopyWith(ClipboardTarget value, $Res Function(ClipboardTarget) _then) = _$ClipboardTargetCopyWithImpl;
@useResult
$Res call({
 String deviceId
});




}
/// @nodoc
class _$ClipboardTargetCopyWithImpl<$Res>
    implements $ClipboardTargetCopyWith<$Res> {
  _$ClipboardTargetCopyWithImpl(this._self, this._then);

  final ClipboardTarget _self;
  final $Res Function(ClipboardTarget) _then;

/// Create a copy of ClipboardTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,}) {
  return _then(_self.copyWith(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ClipboardTarget].
extension ClipboardTargetPatterns on ClipboardTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DeviceClipboardTarget value)?  device,TResult Function( WindowClipboardTarget value)?  window,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DeviceClipboardTarget() when device != null:
return device(_that);case WindowClipboardTarget() when window != null:
return window(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DeviceClipboardTarget value)  device,required TResult Function( WindowClipboardTarget value)  window,}){
final _that = this;
switch (_that) {
case DeviceClipboardTarget():
return device(_that);case WindowClipboardTarget():
return window(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DeviceClipboardTarget value)?  device,TResult? Function( WindowClipboardTarget value)?  window,}){
final _that = this;
switch (_that) {
case DeviceClipboardTarget() when device != null:
return device(_that);case WindowClipboardTarget() when window != null:
return window(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String deviceId)?  device,TResult Function( String deviceId,  String sessionId,  ClipboardCapture? capture,  int? synchronizationGeneration)?  window,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DeviceClipboardTarget() when device != null:
return device(_that.deviceId);case WindowClipboardTarget() when window != null:
return window(_that.deviceId,_that.sessionId,_that.capture,_that.synchronizationGeneration);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String deviceId)  device,required TResult Function( String deviceId,  String sessionId,  ClipboardCapture? capture,  int? synchronizationGeneration)  window,}) {final _that = this;
switch (_that) {
case DeviceClipboardTarget():
return device(_that.deviceId);case WindowClipboardTarget():
return window(_that.deviceId,_that.sessionId,_that.capture,_that.synchronizationGeneration);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String deviceId)?  device,TResult? Function( String deviceId,  String sessionId,  ClipboardCapture? capture,  int? synchronizationGeneration)?  window,}) {final _that = this;
switch (_that) {
case DeviceClipboardTarget() when device != null:
return device(_that.deviceId);case WindowClipboardTarget() when window != null:
return window(_that.deviceId,_that.sessionId,_that.capture,_that.synchronizationGeneration);case _:
  return null;

}
}

}

/// @nodoc


class DeviceClipboardTarget implements ClipboardTarget {
  const DeviceClipboardTarget({required this.deviceId});
  

@override final  String deviceId;

/// Create a copy of ClipboardTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceClipboardTargetCopyWith<DeviceClipboardTarget> get copyWith => _$DeviceClipboardTargetCopyWithImpl<DeviceClipboardTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceClipboardTarget&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId);
}

@override
String toString() {
    return 'ClipboardTarget.device(deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $DeviceClipboardTargetCopyWith<$Res> implements $ClipboardTargetCopyWith<$Res> {
  factory $DeviceClipboardTargetCopyWith(DeviceClipboardTarget value, $Res Function(DeviceClipboardTarget) _then) = _$DeviceClipboardTargetCopyWithImpl;
@override @useResult
$Res call({
 String deviceId
});




}
/// @nodoc
class _$DeviceClipboardTargetCopyWithImpl<$Res>
    implements $DeviceClipboardTargetCopyWith<$Res> {
  _$DeviceClipboardTargetCopyWithImpl(this._self, this._then);

  final DeviceClipboardTarget _self;
  final $Res Function(DeviceClipboardTarget) _then;

/// Create a copy of ClipboardTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,}) {
  return _then(DeviceClipboardTarget(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class WindowClipboardTarget implements ClipboardTarget {
  const WindowClipboardTarget({required this.deviceId, required this.sessionId, this.capture, this.synchronizationGeneration});
  

@override final  String deviceId;
 final  String sessionId;
 final  ClipboardCapture? capture;
 final  int? synchronizationGeneration;

/// Create a copy of ClipboardTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WindowClipboardTargetCopyWith<WindowClipboardTarget> get copyWith => _$WindowClipboardTargetCopyWithImpl<WindowClipboardTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is WindowClipboardTarget&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.capture, capture) || other.capture == capture)&&(identical(other.synchronizationGeneration, synchronizationGeneration) || other.synchronizationGeneration == synchronizationGeneration));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,sessionId,capture,synchronizationGeneration);
}

@override
String toString() {
    return 'ClipboardTarget.window(deviceId: $deviceId, sessionId: $sessionId, capture: $capture, synchronizationGeneration: $synchronizationGeneration)';
}


}

/// @nodoc
abstract mixin class $WindowClipboardTargetCopyWith<$Res> implements $ClipboardTargetCopyWith<$Res> {
  factory $WindowClipboardTargetCopyWith(WindowClipboardTarget value, $Res Function(WindowClipboardTarget) _then) = _$WindowClipboardTargetCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, String sessionId, ClipboardCapture? capture, int? synchronizationGeneration
});


$ClipboardCaptureCopyWith<$Res>? get capture;

}
/// @nodoc
class _$WindowClipboardTargetCopyWithImpl<$Res>
    implements $WindowClipboardTargetCopyWith<$Res> {
  _$WindowClipboardTargetCopyWithImpl(this._self, this._then);

  final WindowClipboardTarget _self;
  final $Res Function(WindowClipboardTarget) _then;

/// Create a copy of ClipboardTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? sessionId = null,Object? capture = freezed,Object? synchronizationGeneration = freezed,}) {
  return _then(WindowClipboardTarget(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,capture: freezed == capture ? _self.capture : capture // ignore: cast_nullable_to_non_nullable
as ClipboardCapture?,synchronizationGeneration: freezed == synchronizationGeneration ? _self.synchronizationGeneration : synchronizationGeneration // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of ClipboardTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClipboardCaptureCopyWith<$Res>? get capture {
    if (_self.capture == null) {
    return null;
  }

  return $ClipboardCaptureCopyWith<$Res>(_self.capture!, (value) {
    return _then(_self.copyWith(capture: value));
  });
}
}

/// @nodoc
mixin _$ClipboardCapture {

 String get reference; int get generation;
/// Create a copy of ClipboardCapture
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClipboardCaptureCopyWith<ClipboardCapture> get copyWith => _$ClipboardCaptureCopyWithImpl<ClipboardCapture>(this as ClipboardCapture, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ClipboardCapture;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClipboardCapture&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.generation, _this.generation) || other.generation == _this.generation));
}


@override
int get hashCode {
  final _this = this as ClipboardCapture;
  return Object.hash(runtimeType,_this.reference,_this.generation);
}

@override
String toString() {
  final _this = this as ClipboardCapture;
  return 'ClipboardCapture(reference: ${_this.reference}, generation: ${_this.generation})';
}


}

/// @nodoc
abstract mixin class $ClipboardCaptureCopyWith<$Res>  {
  factory $ClipboardCaptureCopyWith(ClipboardCapture value, $Res Function(ClipboardCapture) _then) = _$ClipboardCaptureCopyWithImpl;
@useResult
$Res call({
 String reference, int generation
});




}
/// @nodoc
class _$ClipboardCaptureCopyWithImpl<$Res>
    implements $ClipboardCaptureCopyWith<$Res> {
  _$ClipboardCaptureCopyWithImpl(this._self, this._then);

  final ClipboardCapture _self;
  final $Res Function(ClipboardCapture) _then;

/// Create a copy of ClipboardCapture
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? generation = null,}) {
  return _then(ClipboardCapture(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ClipboardCapture].
extension ClipboardCapturePatterns on ClipboardCapture {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ClipboardCapture value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ClipboardCapture() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ClipboardCapture value)  $default,){
final _that = this;
switch (_that) {
case _ClipboardCapture():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ClipboardCapture value)?  $default,){
final _that = this;
switch (_that) {
case _ClipboardCapture() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String reference,  int generation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ClipboardCapture() when $default != null:
return $default(_that.reference,_that.generation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String reference,  int generation)  $default,) {final _that = this;
switch (_that) {
case _ClipboardCapture():
return $default(_that.reference,_that.generation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String reference,  int generation)?  $default,) {final _that = this;
switch (_that) {
case _ClipboardCapture() when $default != null:
return $default(_that.reference,_that.generation);case _:
  return null;

}
}

}

/// @nodoc


class _ClipboardCapture implements ClipboardCapture {
  const _ClipboardCapture({required this.reference, required this.generation});
  

@override final  String reference;
@override final  int generation;

/// Create a copy of ClipboardCapture
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ClipboardCaptureCopyWith<_ClipboardCapture> get copyWith => __$ClipboardCaptureCopyWithImpl<_ClipboardCapture>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ClipboardCapture&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.generation, generation) || other.generation == generation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,generation);
}

@override
String toString() {
    return 'ClipboardCapture(reference: $reference, generation: $generation)';
}


}

/// @nodoc
abstract mixin class _$ClipboardCaptureCopyWith<$Res> implements $ClipboardCaptureCopyWith<$Res> {
  factory _$ClipboardCaptureCopyWith(_ClipboardCapture value, $Res Function(_ClipboardCapture) _then) = __$ClipboardCaptureCopyWithImpl;
@override @useResult
$Res call({
 String reference, int generation
});




}
/// @nodoc
class __$ClipboardCaptureCopyWithImpl<$Res>
    implements _$ClipboardCaptureCopyWith<$Res> {
  __$ClipboardCaptureCopyWithImpl(this._self, this._then);

  final _ClipboardCapture _self;
  final $Res Function(_ClipboardCapture) _then;

/// Create a copy of ClipboardCapture
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? generation = null,}) {
  return _then(_ClipboardCapture(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$RemoteClipboardText {

 String get text; ClipboardCapture? get capture;
/// Create a copy of RemoteClipboardText
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteClipboardTextCopyWith<RemoteClipboardText> get copyWith => _$RemoteClipboardTextCopyWithImpl<RemoteClipboardText>(this as RemoteClipboardText, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RemoteClipboardText;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteClipboardText&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.capture, _this.capture) || other.capture == _this.capture));
}


@override
int get hashCode {
  final _this = this as RemoteClipboardText;
  return Object.hash(runtimeType,_this.text,_this.capture);
}

@override
String toString() {
  final _this = this as RemoteClipboardText;
  return 'RemoteClipboardText(text: ${_this.text}, capture: ${_this.capture})';
}


}

/// @nodoc
abstract mixin class $RemoteClipboardTextCopyWith<$Res>  {
  factory $RemoteClipboardTextCopyWith(RemoteClipboardText value, $Res Function(RemoteClipboardText) _then) = _$RemoteClipboardTextCopyWithImpl;
@useResult
$Res call({
 String text, ClipboardCapture? capture
});


$ClipboardCaptureCopyWith<$Res>? get capture;

}
/// @nodoc
class _$RemoteClipboardTextCopyWithImpl<$Res>
    implements $RemoteClipboardTextCopyWith<$Res> {
  _$RemoteClipboardTextCopyWithImpl(this._self, this._then);

  final RemoteClipboardText _self;
  final $Res Function(RemoteClipboardText) _then;

/// Create a copy of RemoteClipboardText
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? text = null,Object? capture = freezed,}) {
  return _then(RemoteClipboardText(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,capture: freezed == capture ? _self.capture : capture // ignore: cast_nullable_to_non_nullable
as ClipboardCapture?,
  ));
}
/// Create a copy of RemoteClipboardText
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClipboardCaptureCopyWith<$Res>? get capture {
    if (_self.capture == null) {
    return null;
  }

  return $ClipboardCaptureCopyWith<$Res>(_self.capture!, (value) {
    return _then(_self.copyWith(capture: value));
  });
}
}


/// Adds pattern-matching-related methods to [RemoteClipboardText].
extension RemoteClipboardTextPatterns on RemoteClipboardText {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RemoteClipboardText value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RemoteClipboardText() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RemoteClipboardText value)  $default,){
final _that = this;
switch (_that) {
case _RemoteClipboardText():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RemoteClipboardText value)?  $default,){
final _that = this;
switch (_that) {
case _RemoteClipboardText() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String text,  ClipboardCapture? capture)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RemoteClipboardText() when $default != null:
return $default(_that.text,_that.capture);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String text,  ClipboardCapture? capture)  $default,) {final _that = this;
switch (_that) {
case _RemoteClipboardText():
return $default(_that.text,_that.capture);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String text,  ClipboardCapture? capture)?  $default,) {final _that = this;
switch (_that) {
case _RemoteClipboardText() when $default != null:
return $default(_that.text,_that.capture);case _:
  return null;

}
}

}

/// @nodoc


class _RemoteClipboardText implements RemoteClipboardText {
  const _RemoteClipboardText({required this.text, this.capture});
  

@override final  String text;
@override final  ClipboardCapture? capture;

/// Create a copy of RemoteClipboardText
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RemoteClipboardTextCopyWith<_RemoteClipboardText> get copyWith => __$RemoteClipboardTextCopyWithImpl<_RemoteClipboardText>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RemoteClipboardText&&(identical(other.text, text) || other.text == text)&&(identical(other.capture, capture) || other.capture == capture));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text,capture);
}

@override
String toString() {
    return 'RemoteClipboardText(text: $text, capture: $capture)';
}


}

/// @nodoc
abstract mixin class _$RemoteClipboardTextCopyWith<$Res> implements $RemoteClipboardTextCopyWith<$Res> {
  factory _$RemoteClipboardTextCopyWith(_RemoteClipboardText value, $Res Function(_RemoteClipboardText) _then) = __$RemoteClipboardTextCopyWithImpl;
@override @useResult
$Res call({
 String text, ClipboardCapture? capture
});


@override $ClipboardCaptureCopyWith<$Res>? get capture;

}
/// @nodoc
class __$RemoteClipboardTextCopyWithImpl<$Res>
    implements _$RemoteClipboardTextCopyWith<$Res> {
  __$RemoteClipboardTextCopyWithImpl(this._self, this._then);

  final _RemoteClipboardText _self;
  final $Res Function(_RemoteClipboardText) _then;

/// Create a copy of RemoteClipboardText
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? text = null,Object? capture = freezed,}) {
  return _then(_RemoteClipboardText(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,capture: freezed == capture ? _self.capture : capture // ignore: cast_nullable_to_non_nullable
as ClipboardCapture?,
  ));
}

/// Create a copy of RemoteClipboardText
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClipboardCaptureCopyWith<$Res>? get capture {
    if (_self.capture == null) {
    return null;
  }

  return $ClipboardCaptureCopyWith<$Res>(_self.capture!, (value) {
    return _then(_self.copyWith(capture: value));
  });
}
}

// dart format on
