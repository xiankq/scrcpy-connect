import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';

part 'recovery_state.freezed.dart';

@freezed
class RecoveryState with _$RecoveryState {
  RecoveryState({
    this.lastEvent,
    this.eventRevision = 0,
    this.reconciliationPending = false,
    this.reconciliationError,
    this.reconciledSnapshot,
  });
  final RuntimeEvent? lastEvent;
  final RuntimeSnapshot? reconciledSnapshot;
  final int eventRevision;
  final String? reconciliationError;
  final bool reconciliationPending;
}
