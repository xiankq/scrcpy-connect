import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

part 'recovery_state.freezed.dart';

@freezed
class RecoveryState with _$RecoveryState {
  RecoveryState({
    Json? lastEvent,
    this.eventRevision = 0,
    this.reconciliationPending = false,
    this.reconciliationError,
    Json? reconciledSnapshot,
  }) : lastEvent = lastEvent == null ? null : immutableJson(lastEvent),
       reconciledSnapshot = reconciledSnapshot == null
           ? null
           : immutableJson(reconciledSnapshot);
  final Json? lastEvent, reconciledSnapshot;
  final int eventRevision;
  final String? reconciliationError;
  final bool reconciliationPending;
}
