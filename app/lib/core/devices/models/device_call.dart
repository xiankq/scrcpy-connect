import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_call.freezed.dart';
part 'device_call.g.dart';

enum DeviceCallAvailability { unknown, available, limited, stopped }

enum DeviceCallState { unknown, ringing, active, dialing, connecting }

@freezed
abstract class DeviceCall with _$DeviceCall {
  const factory DeviceCall({
    String? id,
    int? generation,
    @JsonKey(unknownEnumValue: DeviceCallState.unknown)
    @Default(DeviceCallState.unknown)
    DeviceCallState state,
    String? name,
    String? number,
    String? deviceName,
    @Default(false) bool aggregate,
  }) = _DeviceCall;
  factory DeviceCall.fromJson(Map<String, dynamic> json) =>
      _$DeviceCallFromJson(json);
}

@freezed
abstract class DeviceCallsSnapshot with _$DeviceCallsSnapshot {
  const DeviceCallsSnapshot._();
  const factory DeviceCallsSnapshot({
    required String deviceId,
    @JsonKey(unknownEnumValue: DeviceCallAvailability.unknown)
    @Default(DeviceCallAvailability.unknown)
    DeviceCallAvailability status,
    @Default(false) bool live,
    int? observationEpoch,
    @Default(false) bool observationEnabled,
    @Default([]) List<DeviceCall> calls,
    String? reason,
    @Default(false) bool canOpenSystemCallUi,
    @Default(false) bool canRetrySystemCallUi,
  }) = _DeviceCallsSnapshot;
  factory DeviceCallsSnapshot.fromJson(Map<String, dynamic> json) =>
      _$DeviceCallsSnapshotFromJson(json);

  bool get verified => live && (status == .available || status == .limited);
}
