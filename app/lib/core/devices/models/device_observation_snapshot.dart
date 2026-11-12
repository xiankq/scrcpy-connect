import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_observation_snapshot.freezed.dart';
part 'device_observation_snapshot.g.dart';

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
