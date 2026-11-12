import 'dart:async';

import 'package:scrcpy_connect/core/devices/device_assessment.dart';
import 'package:scrcpy_connect/core/devices/models/device_capability_observation.dart';
import 'package:scrcpy_connect/core/devices/models/device_record.dart';

/// 单次查询绑定的连接事实；快照回调只读取已有所有者，不部署或恢复活动。
final class DeviceCapabilityFacts {
  DeviceCapabilityFacts({
    required this.record,
    required this.connected,
    required this.connectionId,
    required List<String> features,
    required Map<String, DeviceCapabilityObservation> observations,
    required this.identity,
    required List<DeviceCapability> observationCapabilities,
    required this.streaming,
    required this.audioPlaying,
    required this.usbBackendAvailable,
    required this.assertCurrent,
  }) : features = List.unmodifiable(features),
       observations = Map.unmodifiable(observations),
       observationCapabilities = List.unmodifiable(observationCapabilities);

  final DeviceRecord record;
  final bool connected, streaming, audioPlaying;
  final String? connectionId;
  final bool? usbBackendAvailable;
  final List<String> features;
  final Map<String, DeviceCapabilityObservation> observations;
  final DeviceCapabilityObservation identity;
  final List<DeviceCapability> observationCapabilities;

  /// 解释层等待本机媒体信息之后仍须复核原连接、端点和授权身份。
  final Future<void> Function() assertCurrent;

  DeviceCapabilityObservation observation(String group) =>
      observations[group] ?? const DeviceCapabilityObservation.unknown();
}
