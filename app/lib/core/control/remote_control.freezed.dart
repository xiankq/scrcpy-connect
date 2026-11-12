// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'remote_control.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ControlTarget {

 String? get sessionId; String? get deviceId; int? get captureGeneration; String? get captureRef;
/// Create a copy of ControlTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlTargetCopyWith<ControlTarget> get copyWith => _$ControlTargetCopyWithImpl<ControlTarget>(this as ControlTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ControlTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlTarget&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.captureGeneration, _this.captureGeneration) || other.captureGeneration == _this.captureGeneration)&&(identical(other.captureRef, _this.captureRef) || other.captureRef == _this.captureRef));
}


@override
int get hashCode {
  final _this = this as ControlTarget;
  return Object.hash(runtimeType,_this.sessionId,_this.deviceId,_this.captureGeneration,_this.captureRef);
}

@override
String toString() {
  final _this = this as ControlTarget;
  return 'ControlTarget(sessionId: ${_this.sessionId}, deviceId: ${_this.deviceId}, captureGeneration: ${_this.captureGeneration}, captureRef: ${_this.captureRef})';
}


}

/// @nodoc
abstract mixin class $ControlTargetCopyWith<$Res>  {
  factory $ControlTargetCopyWith(ControlTarget value, $Res Function(ControlTarget) _then) = _$ControlTargetCopyWithImpl;
@useResult
$Res call({
 String? sessionId, String? deviceId, int? captureGeneration, String? captureRef
});




}
/// @nodoc
class _$ControlTargetCopyWithImpl<$Res>
    implements $ControlTargetCopyWith<$Res> {
  _$ControlTargetCopyWithImpl(this._self, this._then);

  final ControlTarget _self;
  final $Res Function(ControlTarget) _then;

/// Create a copy of ControlTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = freezed,Object? deviceId = freezed,Object? captureGeneration = freezed,Object? captureRef = freezed,}) {
  return _then(ControlTarget(
sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,captureGeneration: freezed == captureGeneration ? _self.captureGeneration : captureGeneration // ignore: cast_nullable_to_non_nullable
as int?,captureRef: freezed == captureRef ? _self.captureRef : captureRef // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ControlTarget].
extension ControlTargetPatterns on ControlTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ControlTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ControlTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ControlTarget value)  $default,){
final _that = this;
switch (_that) {
case _ControlTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ControlTarget value)?  $default,){
final _that = this;
switch (_that) {
case _ControlTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? sessionId,  String? deviceId,  int? captureGeneration,  String? captureRef)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ControlTarget() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.captureGeneration,_that.captureRef);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? sessionId,  String? deviceId,  int? captureGeneration,  String? captureRef)  $default,) {final _that = this;
switch (_that) {
case _ControlTarget():
return $default(_that.sessionId,_that.deviceId,_that.captureGeneration,_that.captureRef);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? sessionId,  String? deviceId,  int? captureGeneration,  String? captureRef)?  $default,) {final _that = this;
switch (_that) {
case _ControlTarget() when $default != null:
return $default(_that.sessionId,_that.deviceId,_that.captureGeneration,_that.captureRef);case _:
  return null;

}
}

}

/// @nodoc


class _ControlTarget implements ControlTarget {
  const _ControlTarget({this.sessionId, this.deviceId, this.captureGeneration, this.captureRef});
  

@override final  String? sessionId;
@override final  String? deviceId;
@override final  int? captureGeneration;
@override final  String? captureRef;

/// Create a copy of ControlTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ControlTargetCopyWith<_ControlTarget> get copyWith => __$ControlTargetCopyWithImpl<_ControlTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ControlTarget&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.captureGeneration, captureGeneration) || other.captureGeneration == captureGeneration)&&(identical(other.captureRef, captureRef) || other.captureRef == captureRef));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId,deviceId,captureGeneration,captureRef);
}

@override
String toString() {
    return 'ControlTarget(sessionId: $sessionId, deviceId: $deviceId, captureGeneration: $captureGeneration, captureRef: $captureRef)';
}


}

/// @nodoc
abstract mixin class _$ControlTargetCopyWith<$Res> implements $ControlTargetCopyWith<$Res> {
  factory _$ControlTargetCopyWith(_ControlTarget value, $Res Function(_ControlTarget) _then) = __$ControlTargetCopyWithImpl;
@override @useResult
$Res call({
 String? sessionId, String? deviceId, int? captureGeneration, String? captureRef
});




}
/// @nodoc
class __$ControlTargetCopyWithImpl<$Res>
    implements _$ControlTargetCopyWith<$Res> {
  __$ControlTargetCopyWithImpl(this._self, this._then);

  final _ControlTarget _self;
  final $Res Function(_ControlTarget) _then;

/// Create a copy of ControlTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = freezed,Object? deviceId = freezed,Object? captureGeneration = freezed,Object? captureRef = freezed,}) {
  return _then(_ControlTarget(
sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,captureGeneration: freezed == captureGeneration ? _self.captureGeneration : captureGeneration // ignore: cast_nullable_to_non_nullable
as int?,captureRef: freezed == captureRef ? _self.captureRef : captureRef // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$ControlAction {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlAction);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ControlAction()';
}


}

/// @nodoc
class $ControlActionCopyWith<$Res>  {
$ControlActionCopyWith(ControlAction _, $Res Function(ControlAction) __);
}


/// Adds pattern-matching-related methods to [ControlAction].
extension ControlActionPatterns on ControlAction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ControlKey value)?  key,TResult Function( ControlText value)?  text,TResult Function( ControlTouch value)?  touch,TResult Function( ControlScroll value)?  scroll,TResult Function( ControlRotate value)?  rotate,TResult Function( ControlScreenPower value)?  screenPower,TResult Function( ControlLaunchApplication value)?  launchApplication,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ControlKey() when key != null:
return key(_that);case ControlText() when text != null:
return text(_that);case ControlTouch() when touch != null:
return touch(_that);case ControlScroll() when scroll != null:
return scroll(_that);case ControlRotate() when rotate != null:
return rotate(_that);case ControlScreenPower() when screenPower != null:
return screenPower(_that);case ControlLaunchApplication() when launchApplication != null:
return launchApplication(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ControlKey value)  key,required TResult Function( ControlText value)  text,required TResult Function( ControlTouch value)  touch,required TResult Function( ControlScroll value)  scroll,required TResult Function( ControlRotate value)  rotate,required TResult Function( ControlScreenPower value)  screenPower,required TResult Function( ControlLaunchApplication value)  launchApplication,}){
final _that = this;
switch (_that) {
case ControlKey():
return key(_that);case ControlText():
return text(_that);case ControlTouch():
return touch(_that);case ControlScroll():
return scroll(_that);case ControlRotate():
return rotate(_that);case ControlScreenPower():
return screenPower(_that);case ControlLaunchApplication():
return launchApplication(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ControlKey value)?  key,TResult? Function( ControlText value)?  text,TResult? Function( ControlTouch value)?  touch,TResult? Function( ControlScroll value)?  scroll,TResult? Function( ControlRotate value)?  rotate,TResult? Function( ControlScreenPower value)?  screenPower,TResult? Function( ControlLaunchApplication value)?  launchApplication,}){
final _that = this;
switch (_that) {
case ControlKey() when key != null:
return key(_that);case ControlText() when text != null:
return text(_that);case ControlTouch() when touch != null:
return touch(_that);case ControlScroll() when scroll != null:
return scroll(_that);case ControlRotate() when rotate != null:
return rotate(_that);case ControlScreenPower() when screenPower != null:
return screenPower(_that);case ControlLaunchApplication() when launchApplication != null:
return launchApplication(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int keyCode,  ControlKeyAction action,  int repeat,  int metaState)?  key,TResult Function( String text)?  text,TResult Function( ControlPoint point,  ControlTouchAction action,  int pointerId,  double? pressure,  bool mouse,  int buttons,  int actionButton)?  touch,TResult Function( ControlPoint point,  double horizontal,  double vertical,  int buttons)?  scroll,TResult Function()?  rotate,TResult Function( bool on)?  screenPower,TResult Function( String packageName)?  launchApplication,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ControlKey() when key != null:
return key(_that.keyCode,_that.action,_that.repeat,_that.metaState);case ControlText() when text != null:
return text(_that.text);case ControlTouch() when touch != null:
return touch(_that.point,_that.action,_that.pointerId,_that.pressure,_that.mouse,_that.buttons,_that.actionButton);case ControlScroll() when scroll != null:
return scroll(_that.point,_that.horizontal,_that.vertical,_that.buttons);case ControlRotate() when rotate != null:
return rotate();case ControlScreenPower() when screenPower != null:
return screenPower(_that.on);case ControlLaunchApplication() when launchApplication != null:
return launchApplication(_that.packageName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int keyCode,  ControlKeyAction action,  int repeat,  int metaState)  key,required TResult Function( String text)  text,required TResult Function( ControlPoint point,  ControlTouchAction action,  int pointerId,  double? pressure,  bool mouse,  int buttons,  int actionButton)  touch,required TResult Function( ControlPoint point,  double horizontal,  double vertical,  int buttons)  scroll,required TResult Function()  rotate,required TResult Function( bool on)  screenPower,required TResult Function( String packageName)  launchApplication,}) {final _that = this;
switch (_that) {
case ControlKey():
return key(_that.keyCode,_that.action,_that.repeat,_that.metaState);case ControlText():
return text(_that.text);case ControlTouch():
return touch(_that.point,_that.action,_that.pointerId,_that.pressure,_that.mouse,_that.buttons,_that.actionButton);case ControlScroll():
return scroll(_that.point,_that.horizontal,_that.vertical,_that.buttons);case ControlRotate():
return rotate();case ControlScreenPower():
return screenPower(_that.on);case ControlLaunchApplication():
return launchApplication(_that.packageName);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int keyCode,  ControlKeyAction action,  int repeat,  int metaState)?  key,TResult? Function( String text)?  text,TResult? Function( ControlPoint point,  ControlTouchAction action,  int pointerId,  double? pressure,  bool mouse,  int buttons,  int actionButton)?  touch,TResult? Function( ControlPoint point,  double horizontal,  double vertical,  int buttons)?  scroll,TResult? Function()?  rotate,TResult? Function( bool on)?  screenPower,TResult? Function( String packageName)?  launchApplication,}) {final _that = this;
switch (_that) {
case ControlKey() when key != null:
return key(_that.keyCode,_that.action,_that.repeat,_that.metaState);case ControlText() when text != null:
return text(_that.text);case ControlTouch() when touch != null:
return touch(_that.point,_that.action,_that.pointerId,_that.pressure,_that.mouse,_that.buttons,_that.actionButton);case ControlScroll() when scroll != null:
return scroll(_that.point,_that.horizontal,_that.vertical,_that.buttons);case ControlRotate() when rotate != null:
return rotate();case ControlScreenPower() when screenPower != null:
return screenPower(_that.on);case ControlLaunchApplication() when launchApplication != null:
return launchApplication(_that.packageName);case _:
  return null;

}
}

}

/// @nodoc


class ControlKey extends ControlAction {
  const ControlKey(this.keyCode, {this.action = ControlKeyAction.press, this.repeat = 0, this.metaState = 0}): super._();
  

 final  int keyCode;
@JsonKey() final  ControlKeyAction action;
@JsonKey() final  int repeat;
@JsonKey() final  int metaState;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlKeyCopyWith<ControlKey> get copyWith => _$ControlKeyCopyWithImpl<ControlKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlKey&&(identical(other.keyCode, keyCode) || other.keyCode == keyCode)&&(identical(other.action, action) || other.action == action)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&(identical(other.metaState, metaState) || other.metaState == metaState));
}


@override
int get hashCode {
    return Object.hash(runtimeType,keyCode,action,repeat,metaState);
}

@override
String toString() {
    return 'ControlAction.key(keyCode: $keyCode, action: $action, repeat: $repeat, metaState: $metaState)';
}


}

/// @nodoc
abstract mixin class $ControlKeyCopyWith<$Res> implements $ControlActionCopyWith<$Res> {
  factory $ControlKeyCopyWith(ControlKey value, $Res Function(ControlKey) _then) = _$ControlKeyCopyWithImpl;
@useResult
$Res call({
 int keyCode, ControlKeyAction action, int repeat, int metaState
});




}
/// @nodoc
class _$ControlKeyCopyWithImpl<$Res>
    implements $ControlKeyCopyWith<$Res> {
  _$ControlKeyCopyWithImpl(this._self, this._then);

  final ControlKey _self;
  final $Res Function(ControlKey) _then;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? keyCode = null,Object? action = null,Object? repeat = null,Object? metaState = null,}) {
  return _then(ControlKey(
null == keyCode ? _self.keyCode : keyCode // ignore: cast_nullable_to_non_nullable
as int,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as ControlKeyAction,repeat: null == repeat ? _self.repeat : repeat // ignore: cast_nullable_to_non_nullable
as int,metaState: null == metaState ? _self.metaState : metaState // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ControlText extends ControlAction {
  const ControlText(this.text): super._();
  

 final  String text;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlTextCopyWith<ControlText> get copyWith => _$ControlTextCopyWithImpl<ControlText>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlText&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'ControlAction.text(text: $text)';
}


}

/// @nodoc
abstract mixin class $ControlTextCopyWith<$Res> implements $ControlActionCopyWith<$Res> {
  factory $ControlTextCopyWith(ControlText value, $Res Function(ControlText) _then) = _$ControlTextCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$ControlTextCopyWithImpl<$Res>
    implements $ControlTextCopyWith<$Res> {
  _$ControlTextCopyWithImpl(this._self, this._then);

  final ControlText _self;
  final $Res Function(ControlText) _then;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(ControlText(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ControlTouch extends ControlAction {
  const ControlTouch(this.point, {required this.action, required this.pointerId, this.pressure, this.mouse = false, this.buttons = 0, this.actionButton = 0}): super._();
  

 final  ControlPoint point;
 final  ControlTouchAction action;
 final  int pointerId;
 final  double? pressure;
@JsonKey() final  bool mouse;
@JsonKey() final  int buttons;
@JsonKey() final  int actionButton;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlTouchCopyWith<ControlTouch> get copyWith => _$ControlTouchCopyWithImpl<ControlTouch>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlTouch&&(identical(other.point, point) || other.point == point)&&(identical(other.action, action) || other.action == action)&&(identical(other.pointerId, pointerId) || other.pointerId == pointerId)&&(identical(other.pressure, pressure) || other.pressure == pressure)&&(identical(other.mouse, mouse) || other.mouse == mouse)&&(identical(other.buttons, buttons) || other.buttons == buttons)&&(identical(other.actionButton, actionButton) || other.actionButton == actionButton));
}


@override
int get hashCode {
    return Object.hash(runtimeType,point,action,pointerId,pressure,mouse,buttons,actionButton);
}

@override
String toString() {
    return 'ControlAction.touch(point: $point, action: $action, pointerId: $pointerId, pressure: $pressure, mouse: $mouse, buttons: $buttons, actionButton: $actionButton)';
}


}

/// @nodoc
abstract mixin class $ControlTouchCopyWith<$Res> implements $ControlActionCopyWith<$Res> {
  factory $ControlTouchCopyWith(ControlTouch value, $Res Function(ControlTouch) _then) = _$ControlTouchCopyWithImpl;
@useResult
$Res call({
 ControlPoint point, ControlTouchAction action, int pointerId, double? pressure, bool mouse, int buttons, int actionButton
});




}
/// @nodoc
class _$ControlTouchCopyWithImpl<$Res>
    implements $ControlTouchCopyWith<$Res> {
  _$ControlTouchCopyWithImpl(this._self, this._then);

  final ControlTouch _self;
  final $Res Function(ControlTouch) _then;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? point = null,Object? action = null,Object? pointerId = null,Object? pressure = freezed,Object? mouse = null,Object? buttons = null,Object? actionButton = null,}) {
  return _then(ControlTouch(
null == point ? _self.point : point // ignore: cast_nullable_to_non_nullable
as ControlPoint,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as ControlTouchAction,pointerId: null == pointerId ? _self.pointerId : pointerId // ignore: cast_nullable_to_non_nullable
as int,pressure: freezed == pressure ? _self.pressure : pressure // ignore: cast_nullable_to_non_nullable
as double?,mouse: null == mouse ? _self.mouse : mouse // ignore: cast_nullable_to_non_nullable
as bool,buttons: null == buttons ? _self.buttons : buttons // ignore: cast_nullable_to_non_nullable
as int,actionButton: null == actionButton ? _self.actionButton : actionButton // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ControlScroll extends ControlAction {
  const ControlScroll(this.point, {required this.horizontal, required this.vertical, this.buttons = 0}): super._();
  

 final  ControlPoint point;
 final  double horizontal;
 final  double vertical;
@JsonKey() final  int buttons;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlScrollCopyWith<ControlScroll> get copyWith => _$ControlScrollCopyWithImpl<ControlScroll>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlScroll&&(identical(other.point, point) || other.point == point)&&(identical(other.horizontal, horizontal) || other.horizontal == horizontal)&&(identical(other.vertical, vertical) || other.vertical == vertical)&&(identical(other.buttons, buttons) || other.buttons == buttons));
}


@override
int get hashCode {
    return Object.hash(runtimeType,point,horizontal,vertical,buttons);
}

@override
String toString() {
    return 'ControlAction.scroll(point: $point, horizontal: $horizontal, vertical: $vertical, buttons: $buttons)';
}


}

/// @nodoc
abstract mixin class $ControlScrollCopyWith<$Res> implements $ControlActionCopyWith<$Res> {
  factory $ControlScrollCopyWith(ControlScroll value, $Res Function(ControlScroll) _then) = _$ControlScrollCopyWithImpl;
@useResult
$Res call({
 ControlPoint point, double horizontal, double vertical, int buttons
});




}
/// @nodoc
class _$ControlScrollCopyWithImpl<$Res>
    implements $ControlScrollCopyWith<$Res> {
  _$ControlScrollCopyWithImpl(this._self, this._then);

  final ControlScroll _self;
  final $Res Function(ControlScroll) _then;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? point = null,Object? horizontal = null,Object? vertical = null,Object? buttons = null,}) {
  return _then(ControlScroll(
null == point ? _self.point : point // ignore: cast_nullable_to_non_nullable
as ControlPoint,horizontal: null == horizontal ? _self.horizontal : horizontal // ignore: cast_nullable_to_non_nullable
as double,vertical: null == vertical ? _self.vertical : vertical // ignore: cast_nullable_to_non_nullable
as double,buttons: null == buttons ? _self.buttons : buttons // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ControlRotate extends ControlAction {
  const ControlRotate(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlRotate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ControlAction.rotate()';
}


}




/// @nodoc


class ControlScreenPower extends ControlAction {
  const ControlScreenPower({required this.on}): super._();
  

 final  bool on;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlScreenPowerCopyWith<ControlScreenPower> get copyWith => _$ControlScreenPowerCopyWithImpl<ControlScreenPower>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlScreenPower&&(identical(other.on, on) || other.on == on));
}


@override
int get hashCode {
    return Object.hash(runtimeType,on);
}

@override
String toString() {
    return 'ControlAction.screenPower(on: $on)';
}


}

/// @nodoc
abstract mixin class $ControlScreenPowerCopyWith<$Res> implements $ControlActionCopyWith<$Res> {
  factory $ControlScreenPowerCopyWith(ControlScreenPower value, $Res Function(ControlScreenPower) _then) = _$ControlScreenPowerCopyWithImpl;
@useResult
$Res call({
 bool on
});




}
/// @nodoc
class _$ControlScreenPowerCopyWithImpl<$Res>
    implements $ControlScreenPowerCopyWith<$Res> {
  _$ControlScreenPowerCopyWithImpl(this._self, this._then);

  final ControlScreenPower _self;
  final $Res Function(ControlScreenPower) _then;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? on = null,}) {
  return _then(ControlScreenPower(
on: null == on ? _self.on : on // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class ControlLaunchApplication extends ControlAction {
  const ControlLaunchApplication(this.packageName): super._();
  

 final  String packageName;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlLaunchApplicationCopyWith<ControlLaunchApplication> get copyWith => _$ControlLaunchApplicationCopyWithImpl<ControlLaunchApplication>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlLaunchApplication&&(identical(other.packageName, packageName) || other.packageName == packageName));
}


@override
int get hashCode {
    return Object.hash(runtimeType,packageName);
}

@override
String toString() {
    return 'ControlAction.launchApplication(packageName: $packageName)';
}


}

/// @nodoc
abstract mixin class $ControlLaunchApplicationCopyWith<$Res> implements $ControlActionCopyWith<$Res> {
  factory $ControlLaunchApplicationCopyWith(ControlLaunchApplication value, $Res Function(ControlLaunchApplication) _then) = _$ControlLaunchApplicationCopyWithImpl;
@useResult
$Res call({
 String packageName
});




}
/// @nodoc
class _$ControlLaunchApplicationCopyWithImpl<$Res>
    implements $ControlLaunchApplicationCopyWith<$Res> {
  _$ControlLaunchApplicationCopyWithImpl(this._self, this._then);

  final ControlLaunchApplication _self;
  final $Res Function(ControlLaunchApplication) _then;

/// Create a copy of ControlAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? packageName = null,}) {
  return _then(ControlLaunchApplication(
null == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ControlReceipt {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlReceipt);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ControlReceipt()';
}


}

/// @nodoc
class $ControlReceiptCopyWith<$Res>  {
$ControlReceiptCopyWith(ControlReceipt _, $Res Function(ControlReceipt) __);
}


/// Adds pattern-matching-related methods to [ControlReceipt].
extension ControlReceiptPatterns on ControlReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ControlDelivered value)?  delivered,TResult Function( ControlEmptyText value)?  emptyText,TResult Function( ControlApplicationSubmitted value)?  applicationSubmitted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ControlDelivered() when delivered != null:
return delivered(_that);case ControlEmptyText() when emptyText != null:
return emptyText(_that);case ControlApplicationSubmitted() when applicationSubmitted != null:
return applicationSubmitted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ControlDelivered value)  delivered,required TResult Function( ControlEmptyText value)  emptyText,required TResult Function( ControlApplicationSubmitted value)  applicationSubmitted,}){
final _that = this;
switch (_that) {
case ControlDelivered():
return delivered(_that);case ControlEmptyText():
return emptyText(_that);case ControlApplicationSubmitted():
return applicationSubmitted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ControlDelivered value)?  delivered,TResult? Function( ControlEmptyText value)?  emptyText,TResult? Function( ControlApplicationSubmitted value)?  applicationSubmitted,}){
final _that = this;
switch (_that) {
case ControlDelivered() when delivered != null:
return delivered(_that);case ControlEmptyText() when emptyText != null:
return emptyText(_that);case ControlApplicationSubmitted() when applicationSubmitted != null:
return applicationSubmitted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ScrcpyControlCompletion completion)?  delivered,TResult Function()?  emptyText,TResult Function( String sessionId,  String operationId)?  applicationSubmitted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ControlDelivered() when delivered != null:
return delivered(_that.completion);case ControlEmptyText() when emptyText != null:
return emptyText();case ControlApplicationSubmitted() when applicationSubmitted != null:
return applicationSubmitted(_that.sessionId,_that.operationId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ScrcpyControlCompletion completion)  delivered,required TResult Function()  emptyText,required TResult Function( String sessionId,  String operationId)  applicationSubmitted,}) {final _that = this;
switch (_that) {
case ControlDelivered():
return delivered(_that.completion);case ControlEmptyText():
return emptyText();case ControlApplicationSubmitted():
return applicationSubmitted(_that.sessionId,_that.operationId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ScrcpyControlCompletion completion)?  delivered,TResult? Function()?  emptyText,TResult? Function( String sessionId,  String operationId)?  applicationSubmitted,}) {final _that = this;
switch (_that) {
case ControlDelivered() when delivered != null:
return delivered(_that.completion);case ControlEmptyText() when emptyText != null:
return emptyText();case ControlApplicationSubmitted() when applicationSubmitted != null:
return applicationSubmitted(_that.sessionId,_that.operationId);case _:
  return null;

}
}

}

/// @nodoc


class ControlDelivered implements ControlReceipt {
  const ControlDelivered(this.completion);
  

 final  ScrcpyControlCompletion completion;

/// Create a copy of ControlReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlDeliveredCopyWith<ControlDelivered> get copyWith => _$ControlDeliveredCopyWithImpl<ControlDelivered>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlDelivered&&(identical(other.completion, completion) || other.completion == completion));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completion);
}

@override
String toString() {
    return 'ControlReceipt.delivered(completion: $completion)';
}


}

/// @nodoc
abstract mixin class $ControlDeliveredCopyWith<$Res> implements $ControlReceiptCopyWith<$Res> {
  factory $ControlDeliveredCopyWith(ControlDelivered value, $Res Function(ControlDelivered) _then) = _$ControlDeliveredCopyWithImpl;
@useResult
$Res call({
 ScrcpyControlCompletion completion
});




}
/// @nodoc
class _$ControlDeliveredCopyWithImpl<$Res>
    implements $ControlDeliveredCopyWith<$Res> {
  _$ControlDeliveredCopyWithImpl(this._self, this._then);

  final ControlDelivered _self;
  final $Res Function(ControlDelivered) _then;

/// Create a copy of ControlReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completion = null,}) {
  return _then(ControlDelivered(
null == completion ? _self.completion : completion // ignore: cast_nullable_to_non_nullable
as ScrcpyControlCompletion,
  ));
}


}

/// @nodoc


class ControlEmptyText implements ControlReceipt {
  const ControlEmptyText();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlEmptyText);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ControlReceipt.emptyText()';
}


}




/// @nodoc


class ControlApplicationSubmitted implements ControlReceipt {
  const ControlApplicationSubmitted({required this.sessionId, required this.operationId});
  

 final  String sessionId;
 final  String operationId;

/// Create a copy of ControlReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlApplicationSubmittedCopyWith<ControlApplicationSubmitted> get copyWith => _$ControlApplicationSubmittedCopyWithImpl<ControlApplicationSubmitted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlApplicationSubmitted&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId,operationId);
}

@override
String toString() {
    return 'ControlReceipt.applicationSubmitted(sessionId: $sessionId, operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class $ControlApplicationSubmittedCopyWith<$Res> implements $ControlReceiptCopyWith<$Res> {
  factory $ControlApplicationSubmittedCopyWith(ControlApplicationSubmitted value, $Res Function(ControlApplicationSubmitted) _then) = _$ControlApplicationSubmittedCopyWithImpl;
@useResult
$Res call({
 String sessionId, String operationId
});




}
/// @nodoc
class _$ControlApplicationSubmittedCopyWithImpl<$Res>
    implements $ControlApplicationSubmittedCopyWith<$Res> {
  _$ControlApplicationSubmittedCopyWithImpl(this._self, this._then);

  final ControlApplicationSubmitted _self;
  final $Res Function(ControlApplicationSubmitted) _then;

/// Create a copy of ControlReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? operationId = null,}) {
  return _then(ControlApplicationSubmitted(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
