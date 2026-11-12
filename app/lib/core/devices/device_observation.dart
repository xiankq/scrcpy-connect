import 'package:adb/adb.dart' show AdbCancellation;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_observation.freezed.dart';
part 'device_observation.g.dart';

/// 设备记录保存观察意图；当前连接拥有监听和本代状态。
/// 只读操作不会建立连接、部署互联服务或恢复已停止的观察。
abstract interface class DeviceObservation {
  Future<List<DeviceObservationSnapshot>> readObservations({
    AdbCancellation? cancellation,
  });
  Future<DeviceObservationSnapshot> readObservation(
    String deviceId, {
    AdbCancellation? cancellation,
  });
  Future<DeviceObservationSnapshot> startObservation(
    String deviceId, {
    bool allowStart = true,
    AdbCancellation? cancellation,
  });
  Future<DeviceObservationSnapshot> stopObservation(
    String deviceId, {
    AdbCancellation? cancellation,
  });
}

enum DeviceObservationPhase {
  @JsonValue('waiting_connection')
  waitingConnection,
  stopped,
  starting,
  observing,
  limited,
  failed,
}

/// 观察生命周期的只读事实；通知和电话的实时内容由各自读取接口交付。
@freezed
abstract class DeviceObservationSnapshot with _$DeviceObservationSnapshot {
  const factory DeviceObservationSnapshot({
    required String deviceId,
    required bool wanted,
    required DeviceObservationPhase phase,
    required int generation,
    @Default(false) bool notificationsLive,
    @Default(false) bool callsLive,
  }) = _DeviceObservationSnapshot;

  factory DeviceObservationSnapshot.fromJson(Map<String, dynamic> json) =>
      _$DeviceObservationSnapshotFromJson(json);
}
