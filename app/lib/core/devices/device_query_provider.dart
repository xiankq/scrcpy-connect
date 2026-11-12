import 'dart:async';

import 'package:adb/adb.dart' show AdbCancellation;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_assessment.dart';
import 'package:scrcpy_connect/core/devices/device_calls.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_notifications.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';

part 'device_query_provider.g.dart';

/// 同一能力的设备读取共享连接事件筛选；每个查询独立持有取消令牌。
@Riverpod(retry: _noRetry)
Future<DeviceReading<DeviceDetails>> deviceDetails(
  Ref ref,
  String deviceId, {
  String? connectionId,
}) {
  final source = ref.watch(deviceInspectionProvider);
  final cancellation = _observeConnection(
    ref,
    ref.watch(runtimeEventsProvider),
    deviceId,
  );
  return source.readDetails(
    deviceId,
    connectionId: connectionId,
    cancellation: cancellation,
  );
}

@Riverpod(retry: _noRetry)
Future<DeviceCapabilities> deviceCapabilities(
  Ref ref,
  String deviceId, {
  int revision = 0,
}) {
  final source = ref.watch(deviceAssessmentProvider);
  final cancellation = _observeConnection(
    ref,
    ref.watch(runtimeEventsProvider),
    deviceId,
    eventPrefixes: const ['observation.', 'companion.stopped'],
  );
  return source.readCapabilities(deviceId, cancellation: cancellation);
}

@Riverpod(retry: _noRetry)
Future<DeviceDiagnosis> deviceDiagnosis(
  Ref ref,
  String deviceId, {
  int revision = 0,
}) {
  final source = ref.watch(deviceAssessmentProvider);
  final cancellation = _observeConnection(
    ref,
    ref.watch(runtimeEventsProvider),
    deviceId,
  );
  return source.diagnoseDevice(deviceId, cancellation: cancellation);
}

@Riverpod(retry: _noRetry)
Future<List<DeviceApp>> installedDeviceApps(Ref ref, String deviceId) {
  final source = ref.watch(deviceAppsProvider);
  final cancellation = _observeConnection(
    ref,
    ref.watch(runtimeEventsProvider),
    deviceId,
  );
  return source.readInstalledApps(deviceId, cancellation: cancellation);
}

@Riverpod(retry: _noRetry)
Future<RunningDeviceApps> runningDeviceApps(Ref ref, String deviceId) {
  final source = ref.watch(deviceAppsProvider);
  final cancellation = _observeConnection(
    ref,
    ref.watch(runtimeEventsProvider),
    deviceId,
  );
  return source.readRunningApps(deviceId, cancellation: cancellation);
}

@Riverpod(retry: _noRetry)
Future<DeviceAppIcon> deviceAppIcon(
  Ref ref,
  DeviceAppIconTarget target, {
  Object? revision,
}) {
  final source = ref.watch(deviceAppsProvider);
  final cancellation = _observeConnection(
    ref,
    ref.watch(runtimeEventsProvider),
    target.deviceId,
  );
  return source.readAppIcon(
    target.deviceId,
    target.packageName,
    userId: target.userId,
    cancellation: cancellation,
  );
}

@Riverpod(retry: _noRetry)
Future<DeviceCallsSnapshot> deviceCallsSnapshot(Ref ref, String deviceId) {
  final source = ref.watch(deviceCallsProvider);
  final cancellation = _observeConnection(
    ref,
    ref.watch(runtimeEventsProvider),
    deviceId,
    eventPrefixes: const [
      'calls.',
      'call.incoming',
      'observation.',
      'companion.stopped',
    ],
  );
  return source.readCalls(deviceId, cancellation: cancellation);
}

@Riverpod(retry: _noRetry)
Future<DeviceNotificationsSnapshot> deviceNotificationsSnapshot(
  Ref ref,
  String deviceId,
) {
  final source = ref.watch(deviceNotificationsProvider);
  final cancellation = _observeConnection(
    ref,
    ref.watch(runtimeEventsProvider),
    deviceId,
    eventPrefixes: const [
      'notifications.',
      'observation.',
      'companion.stopped',
    ],
  );
  return source.readNotifications(deviceId, cancellation: cancellation);
}

/// 设备查询共享连接事件筛选；释放和源替换同步取消原读取。
AdbCancellation _observeConnection(
  Ref ref,
  Stream<Map<String, dynamic>> events,
  String deviceId, {
  List<String> eventPrefixes = const [],
}) {
  final cancellation = AdbCancellation();
  final subscription = events.listen((event) {
    if (event['data'] is RecoveryEvent) {
      ref.invalidateSelf();
      return;
    }
    final type = event['type'];
    if (type is! String || type == 'session.frame') return;
    final data = event['data'];
    final owner = event['deviceId'] ?? (data is Map ? data['deviceId'] : null);
    if (owner != null && owner != deviceId) return;
    if (type == 'devices.changed' ||
        type.startsWith('device.') ||
        type == 'connections.stopped' ||
        eventPrefixes.any(type.startsWith)) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(() {
    try {
      cancellation.cancel();
    } finally {
      unawaited(subscription.cancel());
    }
  });
  return cancellation;
}

Duration? _noRetry(int _, Object _) => null;
