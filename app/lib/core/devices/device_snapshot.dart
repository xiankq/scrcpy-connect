import 'dart:collection';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'device_record.dart';

export 'device_record.dart' show DeviceTransport;

part 'device_snapshot.freezed.dart';
part 'device_snapshot.g.dart';

enum DeviceConnectionStatus {
  offline,
  connecting,
  connected,
  unauthorized,
  authorizing,
  checking,
  reconnecting,
  paired,
  failed,
  unknown,
}

/// 保存的设备描述与本代实际交付的连接事实；离线缓存不能证明连接存活。
@freezed
abstract class DeviceSnapshot with _$DeviceSnapshot {
  // Freezed 将构造器上的序列化选项转给生成类。
  // ignore: invalid_annotation_target
  @JsonSerializable(checked: true)
  const factory DeviceSnapshot({
    required String id,
    String? name,
    String? address,
    int? port,
    @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)
    DeviceTransport? transport,
    @JsonKey(unknownEnumValue: DeviceConnectionStatus.unknown)
    @Default(DeviceConnectionStatus.unknown)
    DeviceConnectionStatus status,
    @JsonKey(includeIfNull: false) String? connectionId,
    String? guid,
    String? serial,
    String? model,
    String? androidVersion,
    int? apiLevel,
    int? battery,
    bool? charging,
    int? batteryUpdatedAt,
    int? lastSeen,
    String? reason,
    @Default(false) bool autoReconnect,
    @Default(true) bool observationWanted,
  }) = _DeviceSnapshot;

  factory DeviceSnapshot.fromJson(Map<String, dynamic> json) =>
      _$DeviceSnapshotFromJson(json);

  static DeviceSnapshot fromRecord(
    DeviceRecord record, {
    required DeviceConnectionStatus status,
    String? connectionId,
  }) => DeviceSnapshot(
    id: record.id,
    name: record.name,
    address: record.address,
    port: record.port,
    transport: record.transport,
    status: status,
    connectionId: connectionId,
    guid: record.guid,
    serial: record.serial,
    model: record.model,
    androidVersion: record.androidVersion,
    apiLevel: record.apiLevel,
    battery: record.battery,
    charging: record.charging,
    batteryUpdatedAt: record.batteryUpdatedAt,
    lastSeen: record.lastSeen,
    reason: record.reason,
    autoReconnect: record.autoReconnect,
    observationWanted: record.observationWanted,
  );
}

/// 隔离可变输入；能力状态的只读投影可复用已冻结列表，避免无关字段触发 select。
List<DeviceSnapshot> immutableDeviceSnapshots(List<DeviceSnapshot> devices) =>
    devices is _DeviceSnapshots ? devices : _DeviceSnapshots(devices);

final class _DeviceSnapshots extends UnmodifiableListView<DeviceSnapshot> {
  _DeviceSnapshots(List<DeviceSnapshot> devices)
    : super(List.of(devices, growable: false));
}
