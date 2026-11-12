import 'package:freezed_annotation/freezed_annotation.dart';

import 'request_failure.dart';

import 'package:scrcpy_connect/utils/json_readers.dart';

part 'application_status.freezed.dart';

@freezed
class ApplicationStatus with _$ApplicationStatus {
  ApplicationStatus({
    Json? lastEvent,
    this.eventRevision = 0,
    this.audioError,
    this.focusedDeviceId,
    this.reconciliationPending = false,
    this.reconciliationError,
    Json? reconciledSnapshot,
  }) : lastEvent = lastEvent == null ? null : immutableJson(lastEvent),
       reconciledSnapshot = reconciledSnapshot == null
           ? null
           : immutableJson(reconciledSnapshot);
  final Json? lastEvent, reconciledSnapshot;
  final int eventRevision;
  final String? audioError, focusedDeviceId, reconciliationError;
  final bool reconciliationPending;
}
