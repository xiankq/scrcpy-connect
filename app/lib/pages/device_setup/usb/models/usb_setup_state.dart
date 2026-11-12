import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_setup_receipt.dart';

part 'usb_setup_state.freezed.dart';

enum UsbSetupPhase {
  idle,
  checking,
  cancelling,
  completed,
  cancelled,
  failed,
  cleanupRequired,
}

@freezed
abstract class UsbSetupState with _$UsbSetupState {
  const UsbSetupState._();
  const factory UsbSetupState({
    @Default(UsbSetupPhase.idle) UsbSetupPhase phase,
    UsbSetupResult? result,
    String? message,
  }) = _UsbSetupState;

  bool get hasPendingAttempt => switch (phase) {
    .checking || .cancelling || .cleanupRequired => true,
    _ => false,
  };
}
