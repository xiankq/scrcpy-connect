// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'document_operation_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DocumentOperationState {

 bool get loaded; bool get refreshing; bool get busy; bool get cancelling; String? get operationId; String? get recordOperationId; DocumentOutcome? get result; String? get error;
/// Create a copy of DocumentOperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DocumentOperationStateCopyWith<DocumentOperationState> get copyWith => _$DocumentOperationStateCopyWithImpl<DocumentOperationState>(this as DocumentOperationState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DocumentOperationState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DocumentOperationState&&(identical(other.loaded, _this.loaded) || other.loaded == _this.loaded)&&(identical(other.refreshing, _this.refreshing) || other.refreshing == _this.refreshing)&&(identical(other.busy, _this.busy) || other.busy == _this.busy)&&(identical(other.cancelling, _this.cancelling) || other.cancelling == _this.cancelling)&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.recordOperationId, _this.recordOperationId) || other.recordOperationId == _this.recordOperationId)&&(identical(other.result, _this.result) || other.result == _this.result)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as DocumentOperationState;
  return Object.hash(runtimeType,_this.loaded,_this.refreshing,_this.busy,_this.cancelling,_this.operationId,_this.recordOperationId,_this.result,_this.error);
}

@override
String toString() {
  final _this = this as DocumentOperationState;
  return 'DocumentOperationState(loaded: ${_this.loaded}, refreshing: ${_this.refreshing}, busy: ${_this.busy}, cancelling: ${_this.cancelling}, operationId: ${_this.operationId}, recordOperationId: ${_this.recordOperationId}, result: ${_this.result}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $DocumentOperationStateCopyWith<$Res>  {
  factory $DocumentOperationStateCopyWith(DocumentOperationState value, $Res Function(DocumentOperationState) _then) = _$DocumentOperationStateCopyWithImpl;
@useResult
$Res call({
 bool loaded, bool refreshing, bool busy, bool cancelling, String? operationId, String? recordOperationId, DocumentOutcome? result, String? error
});


$DocumentOutcomeCopyWith<$Res>? get result;

}
/// @nodoc
class _$DocumentOperationStateCopyWithImpl<$Res>
    implements $DocumentOperationStateCopyWith<$Res> {
  _$DocumentOperationStateCopyWithImpl(this._self, this._then);

  final DocumentOperationState _self;
  final $Res Function(DocumentOperationState) _then;

/// Create a copy of DocumentOperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? loaded = null,Object? refreshing = null,Object? busy = null,Object? cancelling = null,Object? operationId = freezed,Object? recordOperationId = freezed,Object? result = freezed,Object? error = freezed,}) {
  return _then(DocumentOperationState(
loaded: null == loaded ? _self.loaded : loaded // ignore: cast_nullable_to_non_nullable
as bool,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,busy: null == busy ? _self.busy : busy // ignore: cast_nullable_to_non_nullable
as bool,cancelling: null == cancelling ? _self.cancelling : cancelling // ignore: cast_nullable_to_non_nullable
as bool,operationId: freezed == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String?,recordOperationId: freezed == recordOperationId ? _self.recordOperationId : recordOperationId // ignore: cast_nullable_to_non_nullable
as String?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as DocumentOutcome?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of DocumentOperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DocumentOutcomeCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $DocumentOutcomeCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}


/// Adds pattern-matching-related methods to [DocumentOperationState].
extension DocumentOperationStatePatterns on DocumentOperationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DocumentOperationState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DocumentOperationState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DocumentOperationState value)  $default,){
final _that = this;
switch (_that) {
case _DocumentOperationState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DocumentOperationState value)?  $default,){
final _that = this;
switch (_that) {
case _DocumentOperationState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool loaded,  bool refreshing,  bool busy,  bool cancelling,  String? operationId,  String? recordOperationId,  DocumentOutcome? result,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DocumentOperationState() when $default != null:
return $default(_that.loaded,_that.refreshing,_that.busy,_that.cancelling,_that.operationId,_that.recordOperationId,_that.result,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool loaded,  bool refreshing,  bool busy,  bool cancelling,  String? operationId,  String? recordOperationId,  DocumentOutcome? result,  String? error)  $default,) {final _that = this;
switch (_that) {
case _DocumentOperationState():
return $default(_that.loaded,_that.refreshing,_that.busy,_that.cancelling,_that.operationId,_that.recordOperationId,_that.result,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool loaded,  bool refreshing,  bool busy,  bool cancelling,  String? operationId,  String? recordOperationId,  DocumentOutcome? result,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _DocumentOperationState() when $default != null:
return $default(_that.loaded,_that.refreshing,_that.busy,_that.cancelling,_that.operationId,_that.recordOperationId,_that.result,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _DocumentOperationState implements DocumentOperationState {
  const _DocumentOperationState({this.loaded = false, this.refreshing = false, this.busy = false, this.cancelling = false, this.operationId, this.recordOperationId, this.result, this.error});
  

@override@JsonKey() final  bool loaded;
@override@JsonKey() final  bool refreshing;
@override@JsonKey() final  bool busy;
@override@JsonKey() final  bool cancelling;
@override final  String? operationId;
@override final  String? recordOperationId;
@override final  DocumentOutcome? result;
@override final  String? error;

/// Create a copy of DocumentOperationState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DocumentOperationStateCopyWith<_DocumentOperationState> get copyWith => __$DocumentOperationStateCopyWithImpl<_DocumentOperationState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DocumentOperationState&&(identical(other.loaded, loaded) || other.loaded == loaded)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.busy, busy) || other.busy == busy)&&(identical(other.cancelling, cancelling) || other.cancelling == cancelling)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.recordOperationId, recordOperationId) || other.recordOperationId == recordOperationId)&&(identical(other.result, result) || other.result == result)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,loaded,refreshing,busy,cancelling,operationId,recordOperationId,result,error);
}

@override
String toString() {
    return 'DocumentOperationState(loaded: $loaded, refreshing: $refreshing, busy: $busy, cancelling: $cancelling, operationId: $operationId, recordOperationId: $recordOperationId, result: $result, error: $error)';
}


}

/// @nodoc
abstract mixin class _$DocumentOperationStateCopyWith<$Res> implements $DocumentOperationStateCopyWith<$Res> {
  factory _$DocumentOperationStateCopyWith(_DocumentOperationState value, $Res Function(_DocumentOperationState) _then) = __$DocumentOperationStateCopyWithImpl;
@override @useResult
$Res call({
 bool loaded, bool refreshing, bool busy, bool cancelling, String? operationId, String? recordOperationId, DocumentOutcome? result, String? error
});


@override $DocumentOutcomeCopyWith<$Res>? get result;

}
/// @nodoc
class __$DocumentOperationStateCopyWithImpl<$Res>
    implements _$DocumentOperationStateCopyWith<$Res> {
  __$DocumentOperationStateCopyWithImpl(this._self, this._then);

  final _DocumentOperationState _self;
  final $Res Function(_DocumentOperationState) _then;

/// Create a copy of DocumentOperationState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? loaded = null,Object? refreshing = null,Object? busy = null,Object? cancelling = null,Object? operationId = freezed,Object? recordOperationId = freezed,Object? result = freezed,Object? error = freezed,}) {
  return _then(_DocumentOperationState(
loaded: null == loaded ? _self.loaded : loaded // ignore: cast_nullable_to_non_nullable
as bool,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,busy: null == busy ? _self.busy : busy // ignore: cast_nullable_to_non_nullable
as bool,cancelling: null == cancelling ? _self.cancelling : cancelling // ignore: cast_nullable_to_non_nullable
as bool,operationId: freezed == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String?,recordOperationId: freezed == recordOperationId ? _self.recordOperationId : recordOperationId // ignore: cast_nullable_to_non_nullable
as String?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as DocumentOutcome?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of DocumentOperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DocumentOutcomeCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $DocumentOutcomeCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

// dart format on
