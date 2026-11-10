import 'package:scrcpy_connect/models/device_capability_observation.dart';

import 'dart:async';

import 'package:scrcpy_connect/models/device_record.dart';

/// 单次查询绑定的连接事实；快照回调只读取已有所有者，不部署或恢复活动。
final class DeviceCapabilityFacts {
  DeviceCapabilityFacts({
    required this.record,
    required this.connected,
    required this.connectionId,
    required List<String> features,
    required Map<String, DeviceCapabilityObservation> observations,
    required this.identity,
    required Map<String, Object?> companion,
    required this.streaming,
    required this.audioPlaying,
    required this.usbBackendAvailable,
    required this.assertCurrent,
  }) : features = List.unmodifiable(features),
       observations = Map.unmodifiable(observations),
       companion = Map.unmodifiable(companion);

  final DeviceRecord record;
  final bool connected, streaming, audioPlaying;
  final String? connectionId;
  final bool? usbBackendAvailable;
  final List<String> features;
  final Map<String, DeviceCapabilityObservation> observations;
  final DeviceCapabilityObservation identity;
  final Map<String, Object?> companion;

  /// 解释层等待本机媒体信息之后仍须复核原连接、端点和授权身份。
  final Future<void> Function() assertCurrent;

  DeviceCapabilityObservation observation(String group) =>
      observations[group] ?? const DeviceCapabilityObservation.unknown();

  Map<String, Object?> toJson() => {
    'deviceId': record.id,
    'device': {
      ...record.toJson(),
      'status': connected
          ? 'connected'
          : record.status == 'unauthorized'
          ? 'unauthorized'
          : 'offline',
      'connectionId': connectionId,
    },
    'connected': connected,
    'connectionId': connectionId,
    'features': features,
    'identity': identity.toJson(),
    'observations': {
      for (final entry in observations.entries) entry.key: entry.value.toJson(),
    },
    'usbBackendAvailable': usbBackendAvailable,
  };
}
