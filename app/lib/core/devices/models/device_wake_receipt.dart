import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_wake_receipt.freezed.dart';

enum DeviceWakeEvidence { shellExitSuccess, legacyShellExitSuccess }

@freezed
abstract class DeviceWakeReceipt with _$DeviceWakeReceipt {
  const factory DeviceWakeReceipt({
    required String deviceId,
    required String connectionId,
    required DeviceWakeEvidence evidence,
  }) = _DeviceWakeReceipt;
}
