// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'share_submission_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ShareSubmissionState {

 bool get busy; bool get pushed; bool get copied; bool get completed; bool get showTransfers; String? get error;
/// Create a copy of ShareSubmissionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareSubmissionStateCopyWith<ShareSubmissionState> get copyWith => _$ShareSubmissionStateCopyWithImpl<ShareSubmissionState>(this as ShareSubmissionState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ShareSubmissionState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareSubmissionState&&(identical(other.busy, _this.busy) || other.busy == _this.busy)&&(identical(other.pushed, _this.pushed) || other.pushed == _this.pushed)&&(identical(other.copied, _this.copied) || other.copied == _this.copied)&&(identical(other.completed, _this.completed) || other.completed == _this.completed)&&(identical(other.showTransfers, _this.showTransfers) || other.showTransfers == _this.showTransfers)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as ShareSubmissionState;
  return Object.hash(runtimeType,_this.busy,_this.pushed,_this.copied,_this.completed,_this.showTransfers,_this.error);
}

@override
String toString() {
  final _this = this as ShareSubmissionState;
  return 'ShareSubmissionState(busy: ${_this.busy}, pushed: ${_this.pushed}, copied: ${_this.copied}, completed: ${_this.completed}, showTransfers: ${_this.showTransfers}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $ShareSubmissionStateCopyWith<$Res>  {
  factory $ShareSubmissionStateCopyWith(ShareSubmissionState value, $Res Function(ShareSubmissionState) _then) = _$ShareSubmissionStateCopyWithImpl;
@useResult
$Res call({
 bool busy, bool pushed, bool copied, bool completed, bool showTransfers, String? error
});




}
/// @nodoc
class _$ShareSubmissionStateCopyWithImpl<$Res>
    implements $ShareSubmissionStateCopyWith<$Res> {
  _$ShareSubmissionStateCopyWithImpl(this._self, this._then);

  final ShareSubmissionState _self;
  final $Res Function(ShareSubmissionState) _then;

/// Create a copy of ShareSubmissionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? busy = null,Object? pushed = null,Object? copied = null,Object? completed = null,Object? showTransfers = null,Object? error = freezed,}) {
  return _then(ShareSubmissionState(
busy: null == busy ? _self.busy : busy // ignore: cast_nullable_to_non_nullable
as bool,pushed: null == pushed ? _self.pushed : pushed // ignore: cast_nullable_to_non_nullable
as bool,copied: null == copied ? _self.copied : copied // ignore: cast_nullable_to_non_nullable
as bool,completed: null == completed ? _self.completed : completed // ignore: cast_nullable_to_non_nullable
as bool,showTransfers: null == showTransfers ? _self.showTransfers : showTransfers // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ShareSubmissionState].
extension ShareSubmissionStatePatterns on ShareSubmissionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShareSubmissionState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShareSubmissionState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShareSubmissionState value)  $default,){
final _that = this;
switch (_that) {
case _ShareSubmissionState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShareSubmissionState value)?  $default,){
final _that = this;
switch (_that) {
case _ShareSubmissionState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool busy,  bool pushed,  bool copied,  bool completed,  bool showTransfers,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShareSubmissionState() when $default != null:
return $default(_that.busy,_that.pushed,_that.copied,_that.completed,_that.showTransfers,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool busy,  bool pushed,  bool copied,  bool completed,  bool showTransfers,  String? error)  $default,) {final _that = this;
switch (_that) {
case _ShareSubmissionState():
return $default(_that.busy,_that.pushed,_that.copied,_that.completed,_that.showTransfers,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool busy,  bool pushed,  bool copied,  bool completed,  bool showTransfers,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _ShareSubmissionState() when $default != null:
return $default(_that.busy,_that.pushed,_that.copied,_that.completed,_that.showTransfers,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _ShareSubmissionState implements ShareSubmissionState {
  const _ShareSubmissionState({this.busy = false, this.pushed = false, this.copied = false, this.completed = false, this.showTransfers = false, this.error});
  

@override@JsonKey() final  bool busy;
@override@JsonKey() final  bool pushed;
@override@JsonKey() final  bool copied;
@override@JsonKey() final  bool completed;
@override@JsonKey() final  bool showTransfers;
@override final  String? error;

/// Create a copy of ShareSubmissionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShareSubmissionStateCopyWith<_ShareSubmissionState> get copyWith => __$ShareSubmissionStateCopyWithImpl<_ShareSubmissionState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShareSubmissionState&&(identical(other.busy, busy) || other.busy == busy)&&(identical(other.pushed, pushed) || other.pushed == pushed)&&(identical(other.copied, copied) || other.copied == copied)&&(identical(other.completed, completed) || other.completed == completed)&&(identical(other.showTransfers, showTransfers) || other.showTransfers == showTransfers)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,busy,pushed,copied,completed,showTransfers,error);
}

@override
String toString() {
    return 'ShareSubmissionState(busy: $busy, pushed: $pushed, copied: $copied, completed: $completed, showTransfers: $showTransfers, error: $error)';
}


}

/// @nodoc
abstract mixin class _$ShareSubmissionStateCopyWith<$Res> implements $ShareSubmissionStateCopyWith<$Res> {
  factory _$ShareSubmissionStateCopyWith(_ShareSubmissionState value, $Res Function(_ShareSubmissionState) _then) = __$ShareSubmissionStateCopyWithImpl;
@override @useResult
$Res call({
 bool busy, bool pushed, bool copied, bool completed, bool showTransfers, String? error
});




}
/// @nodoc
class __$ShareSubmissionStateCopyWithImpl<$Res>
    implements _$ShareSubmissionStateCopyWith<$Res> {
  __$ShareSubmissionStateCopyWithImpl(this._self, this._then);

  final _ShareSubmissionState _self;
  final $Res Function(_ShareSubmissionState) _then;

/// Create a copy of ShareSubmissionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? busy = null,Object? pushed = null,Object? copied = null,Object? completed = null,Object? showTransfers = null,Object? error = freezed,}) {
  return _then(_ShareSubmissionState(
busy: null == busy ? _self.busy : busy // ignore: cast_nullable_to_non_nullable
as bool,pushed: null == pushed ? _self.pushed : pushed // ignore: cast_nullable_to_non_nullable
as bool,copied: null == copied ? _self.copied : copied // ignore: cast_nullable_to_non_nullable
as bool,completed: null == completed ? _self.completed : completed // ignore: cast_nullable_to_non_nullable
as bool,showTransfers: null == showTransfers ? _self.showTransfers : showTransfers // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
