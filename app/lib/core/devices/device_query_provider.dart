import 'device_notifications.dart';
import 'device_calls.dart';

import 'dart:async';

import 'package:adb/adb.dart' show AdbCancellation;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/application_session_provider.dart';

import 'device_apps.dart';
import 'device_assessment.dart';
import 'device_inspection.dart';

part 'device_query_provider.g.dart';

/// 同一能力的设备读取共享连接事件筛选；每个查询独立持有取消令牌。
@Riverpod(retry: _noRetry)
Future<DeviceReading<DeviceDetails>> deviceDetails(
  Ref ref,
  String deviceId, {
  String? connectionId,
}) {
  final session = ref.watch(applicationSessionProvider);
  final cancellation = _observeConnection(ref, session.events, deviceId);
  return session.dependencies.inspection.readDetails(
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
  final session = ref.watch(applicationSessionProvider);
  final cancellation = _observeConnection(
    ref,
    session.events,
    deviceId,
    eventPrefixes: const ['observation.', 'companion.stopped'],
  );
  return session.dependencies.assessment.readCapabilities(
    deviceId,
    cancellation: cancellation,
  );
}

@Riverpod(retry: _noRetry)
Future<DeviceDiagnosis> deviceDiagnosis(
  Ref ref,
  String deviceId, {
  int revision = 0,
}) {
  final session = ref.watch(applicationSessionProvider);
  final cancellation = _observeConnection(ref, session.events, deviceId);
  return session.dependencies.assessment.diagnoseDevice(
    deviceId,
    cancellation: cancellation,
  );
}

@Riverpod(retry: _noRetry)
Future<List<DeviceApp>> installedDeviceApps(Ref ref, String deviceId) {
  final session = ref.watch(applicationSessionProvider);
  final cancellation = _observeConnection(ref, session.events, deviceId);
  return session.dependencies.apps.readInstalledApps(
    deviceId,
    cancellation: cancellation,
  );
}

@Riverpod(retry: _noRetry)
Future<RunningDeviceApps> runningDeviceApps(Ref ref, String deviceId) {
  final session = ref.watch(applicationSessionProvider);
  final cancellation = _observeConnection(ref, session.events, deviceId);
  return session.dependencies.apps.readRunningApps(
    deviceId,
    cancellation: cancellation,
  );
}

@Riverpod(retry: _noRetry)
Future<DeviceAppIcon> deviceAppIcon(
  Ref ref,
  DeviceAppIconTarget target, {
  Object? revision,
}) {
  final session = ref.watch(applicationSessionProvider);
  final cancellation = _observeConnection(ref, session.events, target.deviceId);
  return session.dependencies.apps.readAppIcon(
    target.deviceId,
    target.packageName,
    userId: target.userId,
    cancellation: cancellation,
  );
}

@Riverpod(retry: _noRetry)
Future<DeviceCallsSnapshot> deviceCalls(Ref ref, String deviceId) {
  final session = ref.watch(applicationSessionProvider);
  final cancellation = _observeConnection(
    ref,
    session.events,
    deviceId,
    eventPrefixes: const [
      'calls.',
      'call.incoming',
      'observation.',
      'companion.stopped',
    ],
  );
  return session.dependencies.calls.readCalls(
    deviceId,
    cancellation: cancellation,
  );
}

@Riverpod(retry: _noRetry)
Future<DeviceNotificationsSnapshot> deviceNotifications(
  Ref ref,
  String deviceId,
) {
  final session = ref.watch(applicationSessionProvider);
  final cancellation = _observeConnection(
    ref,
    session.events,
    deviceId,
    eventPrefixes: const [
      'notifications.',
      'observation.',
      'companion.stopped',
    ],
  );
  return session.dependencies.notifications.readNotifications(
    deviceId,
    cancellation: cancellation,
  );
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
    final type = event['type'];
    if (type is! String || type == 'session.frame') return;
    final data = event['data'];
    final owner = event['deviceId'] ?? (data is Map ? data['deviceId'] : null);
    if (owner != null && owner != deviceId) return;
    if (type == 'devices.changed' ||
        type.startsWith('device.') ||
        type.startsWith('state.resync') ||
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
