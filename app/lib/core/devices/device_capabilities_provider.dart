import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'device_apps.dart';
import 'device_assessment.dart';
import 'device_calls.dart';
import 'device_connection_control.dart';
import 'device_inspection.dart';
import 'device_management.dart';
import 'device_notifications.dart';
import 'device_observation.dart';
import 'device_reader.dart';
import 'device_setup.dart';

/// 各入口借用启动装配的能力；查询和页面可独立替换，不接管共享资源。
final deviceReaderProvider = Provider<DeviceReader>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final deviceManagementProvider = Provider<DeviceManagement>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final deviceConnectionsProvider = Provider<DeviceConnectionControl>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final deviceSetupProvider = Provider<DeviceSetup>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final deviceInspectionProvider = Provider<DeviceInspection>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final deviceAppsProvider = Provider<DeviceApps>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final deviceAssessmentProvider = Provider<DeviceAssessment>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final deviceCallsProvider = Provider<DeviceCalls>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final deviceNotificationsProvider = Provider<DeviceNotifications>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final deviceObservationProvider = Provider<DeviceObservation>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final deviceWakeProvider = Provider<DeviceWake>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
