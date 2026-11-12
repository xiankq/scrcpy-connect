import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'activity_management.dart';

final activityManagementProvider = Provider<ActivityManagement>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.activities)),
);
