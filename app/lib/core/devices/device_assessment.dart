import 'package:adb/adb.dart' show AdbCancellation;
import 'package:freezed_annotation/freezed_annotation.dart';

import 'device_capability_observation.dart';
import 'device_snapshot.dart';

part 'device_assessment.freezed.dart';

/// 只解释本次读取的事实；不会为检查功能而创建连接、授权身份或互联服务。
abstract interface class DeviceAssessment {
  Future<DeviceCapabilities> readCapabilities(
    String deviceId, {
    AdbCancellation? cancellation,
  });
  Future<DeviceDiagnosis> diagnoseDevice(
    String deviceId, {
    AdbCancellation? cancellation,
  });
}

enum DeviceFeature {
  shell,
  files,
  wirelessPairing,
  screen,
  clipboard,
  apps,
  audio,
  notifications,
  calls,
  background,
}

enum DeviceFeatureStatus {
  unknown,
  available,
  limited,
  unavailable,
  needsSetup,
  stopped,
  unverified;

  static DeviceFeatureStatus fromExternal(String? value) => switch (value) {
    null || 'unknown' => .unknown,
    'available' => .available,
    'limited' => .limited,
    'unavailable' => .unavailable,
    'needsSetup' => .needsSetup,
    'stopped' => .stopped,
    _ => .unverified,
  };
}

@freezed
abstract class DeviceCapability with _$DeviceCapability {
  const factory DeviceCapability({
    required DeviceFeature feature,
    required DeviceFeatureStatus status,
    required String reason,
  }) = _DeviceCapability;
}

@freezed
abstract class DeviceCapabilities with _$DeviceCapabilities {
  const factory DeviceCapabilities({
    required String deviceId,
    String? connectionId,
    @Default([]) List<DeviceCapability> capabilities,
    @Default([]) List<String> features,
  }) = _DeviceCapabilities;
}

@freezed
abstract class DeviceDiagnosis with _$DeviceDiagnosis {
  const factory DeviceDiagnosis({
    required DeviceSnapshot device,
    required bool connected,
    String? connectionId,
    bool? usbBackendAvailable,
    @Default([]) List<String> features,
    @Default(DeviceCapabilityObservation.unknown())
    DeviceCapabilityObservation identity,
    @Default({}) Map<String, DeviceCapabilityObservation> observations,
    bool? tcpReachable,
    String? networkError,
    bool? identityPresent,
    String? identityError,
    required bool adbBurstRequested,
    String? wirelessProperties,
    @Default([]) List<String> notes,
  }) = _DeviceDiagnosis;
}
