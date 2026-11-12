import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'activity_management.dart';

final activityManagementProvider = Provider<ActivityManagement>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
