import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

part 'recovery_state.freezed.dart';

@freezed
class RecoveryState with _$RecoveryState {
  RecoveryState({
    Json? lastEvent,
    this.eventRevision = 0,
    this.reconciliationPending = false,
    this.reconciliationError,
    this.reconciledSnapshot,
  }) : lastEvent = lastEvent == null ? null : immutableJson(lastEvent);
  final Json? lastEvent;
  final RuntimeSnapshot? reconciledSnapshot;
  final int eventRevision;
  final String? reconciliationError;
  final bool reconciliationPending;
}
