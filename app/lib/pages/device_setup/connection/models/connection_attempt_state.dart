import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_setup_receipt.dart';

part 'connection_attempt_state.freezed.dart';

enum ConnectionAttemptPhase {
  idle,
  submitting,
  settled,
  checking,
  cancelling,
  cleanupRequired,
}

@freezed
abstract class ConnectionAttemptState with _$ConnectionAttemptState {
  const ConnectionAttemptState._();
  const factory ConnectionAttemptState({
    @Default(ConnectionAttemptPhase.idle) ConnectionAttemptPhase phase,
    String? deviceId,
    String? address,
    String? connectedDeviceId,
    PairingReceipt? pairing,
    SetupIssue? failure,
    String? notice,
  }) = _ConnectionAttemptState;

  bool get busy => phase == .submitting;
  bool get checking => phase == .checking;
  bool get cancelling => phase == .cancelling;
  bool get canSubmit => phase == .idle || phase == .settled;
}
