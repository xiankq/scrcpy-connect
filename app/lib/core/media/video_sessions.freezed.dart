// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'video_sessions.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VideoSessionView {

 VideoSessionSnapshot get session; KeepAwakeSnapshot get wake; VideoOutputReceipt? get output;
/// Create a copy of VideoSessionView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoSessionViewCopyWith<VideoSessionView> get copyWith => _$VideoSessionViewCopyWithImpl<VideoSessionView>(this as VideoSessionView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoSessionView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoSessionView&&(identical(other.session, _this.session) || other.session == _this.session)&&(identical(other.wake, _this.wake) || other.wake == _this.wake)&&(identical(other.output, _this.output) || other.output == _this.output));
}


@override
int get hashCode {
  final _this = this as VideoSessionView;
  return Object.hash(runtimeType,_this.session,_this.wake,_this.output);
}

@override
String toString() {
  final _this = this as VideoSessionView;
  return 'VideoSessionView(session: ${_this.session}, wake: ${_this.wake}, output: ${_this.output})';
}


}

/// @nodoc
abstract mixin class $VideoSessionViewCopyWith<$Res>  {
  factory $VideoSessionViewCopyWith(VideoSessionView value, $Res Function(VideoSessionView) _then) = _$VideoSessionViewCopyWithImpl;
@useResult
$Res call({
 VideoSessionSnapshot session, KeepAwakeSnapshot wake, VideoOutputReceipt? output
});


$VideoSessionSnapshotCopyWith<$Res> get session;$KeepAwakeSnapshotCopyWith<$Res> get wake;$VideoOutputReceiptCopyWith<$Res>? get output;

}
/// @nodoc
class _$VideoSessionViewCopyWithImpl<$Res>
    implements $VideoSessionViewCopyWith<$Res> {
  _$VideoSessionViewCopyWithImpl(this._self, this._then);

  final VideoSessionView _self;
  final $Res Function(VideoSessionView) _then;

/// Create a copy of VideoSessionView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? session = null,Object? wake = null,Object? output = freezed,}) {
  return _then(VideoSessionView(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as VideoSessionSnapshot,wake: null == wake ? _self.wake : wake // ignore: cast_nullable_to_non_nullable
as KeepAwakeSnapshot,output: freezed == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as VideoOutputReceipt?,
  ));
}
/// Create a copy of VideoSessionView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoSessionSnapshotCopyWith<$Res> get session {
  
  return $VideoSessionSnapshotCopyWith<$Res>(_self.session, (value) {
    return _then(_self.copyWith(session: value));
  });
}/// Create a copy of VideoSessionView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$KeepAwakeSnapshotCopyWith<$Res> get wake {
  
  return $KeepAwakeSnapshotCopyWith<$Res>(_self.wake, (value) {
    return _then(_self.copyWith(wake: value));
  });
}/// Create a copy of VideoSessionView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoOutputReceiptCopyWith<$Res>? get output {
    if (_self.output == null) {
    return null;
  }

  return $VideoOutputReceiptCopyWith<$Res>(_self.output!, (value) {
    return _then(_self.copyWith(output: value));
  });
}
}


/// Adds pattern-matching-related methods to [VideoSessionView].
extension VideoSessionViewPatterns on VideoSessionView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoSessionView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoSessionView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoSessionView value)  $default,){
final _that = this;
switch (_that) {
case _VideoSessionView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoSessionView value)?  $default,){
final _that = this;
switch (_that) {
case _VideoSessionView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( VideoSessionSnapshot session,  KeepAwakeSnapshot wake,  VideoOutputReceipt? output)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoSessionView() when $default != null:
return $default(_that.session,_that.wake,_that.output);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( VideoSessionSnapshot session,  KeepAwakeSnapshot wake,  VideoOutputReceipt? output)  $default,) {final _that = this;
switch (_that) {
case _VideoSessionView():
return $default(_that.session,_that.wake,_that.output);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( VideoSessionSnapshot session,  KeepAwakeSnapshot wake,  VideoOutputReceipt? output)?  $default,) {final _that = this;
switch (_that) {
case _VideoSessionView() when $default != null:
return $default(_that.session,_that.wake,_that.output);case _:
  return null;

}
}

}

/// @nodoc


class _VideoSessionView extends VideoSessionView {
  const _VideoSessionView({required this.session, required this.wake, this.output}): super._();
  

@override final  VideoSessionSnapshot session;
@override final  KeepAwakeSnapshot wake;
@override final  VideoOutputReceipt? output;

/// Create a copy of VideoSessionView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoSessionViewCopyWith<_VideoSessionView> get copyWith => __$VideoSessionViewCopyWithImpl<_VideoSessionView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoSessionView&&(identical(other.session, session) || other.session == session)&&(identical(other.wake, wake) || other.wake == wake)&&(identical(other.output, output) || other.output == output));
}


@override
int get hashCode {
    return Object.hash(runtimeType,session,wake,output);
}

@override
String toString() {
    return 'VideoSessionView(session: $session, wake: $wake, output: $output)';
}


}

/// @nodoc
abstract mixin class _$VideoSessionViewCopyWith<$Res> implements $VideoSessionViewCopyWith<$Res> {
  factory _$VideoSessionViewCopyWith(_VideoSessionView value, $Res Function(_VideoSessionView) _then) = __$VideoSessionViewCopyWithImpl;
@override @useResult
$Res call({
 VideoSessionSnapshot session, KeepAwakeSnapshot wake, VideoOutputReceipt? output
});


@override $VideoSessionSnapshotCopyWith<$Res> get session;@override $KeepAwakeSnapshotCopyWith<$Res> get wake;@override $VideoOutputReceiptCopyWith<$Res>? get output;

}
/// @nodoc
class __$VideoSessionViewCopyWithImpl<$Res>
    implements _$VideoSessionViewCopyWith<$Res> {
  __$VideoSessionViewCopyWithImpl(this._self, this._then);

  final _VideoSessionView _self;
  final $Res Function(_VideoSessionView) _then;

/// Create a copy of VideoSessionView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? session = null,Object? wake = null,Object? output = freezed,}) {
  return _then(_VideoSessionView(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as VideoSessionSnapshot,wake: null == wake ? _self.wake : wake // ignore: cast_nullable_to_non_nullable
as KeepAwakeSnapshot,output: freezed == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as VideoOutputReceipt?,
  ));
}

/// Create a copy of VideoSessionView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoSessionSnapshotCopyWith<$Res> get session {
  
  return $VideoSessionSnapshotCopyWith<$Res>(_self.session, (value) {
    return _then(_self.copyWith(session: value));
  });
}/// Create a copy of VideoSessionView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$KeepAwakeSnapshotCopyWith<$Res> get wake {
  
  return $KeepAwakeSnapshotCopyWith<$Res>(_self.wake, (value) {
    return _then(_self.copyWith(wake: value));
  });
}/// Create a copy of VideoSessionView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoOutputReceiptCopyWith<$Res>? get output {
    if (_self.output == null) {
    return null;
  }

  return $VideoOutputReceiptCopyWith<$Res>(_self.output!, (value) {
    return _then(_self.copyWith(output: value));
  });
}
}

// dart format on
