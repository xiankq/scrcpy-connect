import 'package:adb/adb.dart' show AdbCancellation;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_calls.freezed.dart';
part 'device_calls.g.dart';

abstract interface class DeviceCalls {
  /// 读取当前观察，不部署服务，也不恢复已停止的观察。
  Future<DeviceCallsSnapshot> readCalls(
    String deviceId, {
    AdbCancellation? cancellation,
  });

  /// 返回仅表示手机系统接受请求；实际界面由 Widget 中的远控画面确认。
  /// 当前只请求打开系统通话界面，不能指定或控制某一通电话。
  Future<void> requestCurrentCallUi(
    String deviceId, {
    AdbCancellation? cancellation,
  });
  Future<void> requestPhoneApp(
    String deviceId, {
    AdbCancellation? cancellation,
  });
}

enum DeviceCallAvailability { unknown, available, limited, stopped }

enum DeviceCallState { unknown, ringing, active, dialing, connecting }

@freezed
abstract class DeviceCall with _$DeviceCall {
  const factory DeviceCall({
    String? id,
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
    @Default([]) List<DeviceCall> calls,
    String? reason,
    @Default(false) bool canOpenSystemCallUi,
    @Default(false) bool canRetrySystemCallUi,
  }) = _DeviceCallsSnapshot;
  factory DeviceCallsSnapshot.fromJson(Map<String, dynamic> json) =>
      _$DeviceCallsSnapshotFromJson(json);

  bool get verified => live && (status == .available || status == .limited);
}
