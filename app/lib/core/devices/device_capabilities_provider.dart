import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'device_apps.dart';
import 'device_assessment.dart';
import 'device_calls.dart';
import 'device_connection_control.dart';
import 'device_inspection.dart';
import 'device_management.dart';
import 'device_notifications.dart';
import 'device_observation.dart';
import 'device_setup.dart';

/// 各入口借用启动装配的能力；查询和页面可独立替换，不接管共享资源。
final deviceManagementProvider = Provider<DeviceManagement>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.devices)),
);
final deviceConnectionsProvider = Provider<DeviceConnectionControl>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.connections)),
);
final deviceSetupProvider = Provider<DeviceSetup>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.setup)),
);
final deviceInspectionProvider = Provider<DeviceInspection>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.inspection)),
);
final deviceAppsProvider = Provider<DeviceApps>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.apps)),
);
final deviceAssessmentProvider = Provider<DeviceAssessment>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.assessment)),
);
final deviceCallsProvider = Provider<DeviceCalls>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.calls)),
);
final deviceNotificationsProvider = Provider<DeviceNotifications>(
  (ref) =>
      ref.watch(appDependenciesProvider.select((app) => app.notifications)),
);
final deviceObservationProvider = Provider<DeviceObservation>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.observation)),
);
final deviceWakeProvider = Provider<DeviceWake>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.wake)),
);
