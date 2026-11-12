import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_setup_receipt.dart';

part 'qr_pairing_state.freezed.dart';

enum QrPairingPhase {
  idle,
  generating,
  waiting,
  cancelling,
  completed,
  expired,
  cancelled,
  failed,
  cleanupRequired,
}

@freezed
abstract class QrPairingState with _$QrPairingState {
  const QrPairingState._();
  const factory QrPairingState({
    @Default(QrPairingPhase.idle) QrPairingPhase phase,
    String? payload,
    DateTime? expiresAt,
    PairingReceipt? receipt,
    String? message,
  }) = _QrPairingState;

  bool get busy => phase == .generating || phase == .cancelling;
  bool get hasQr => phase == .waiting && payload?.isNotEmpty == true;
}
