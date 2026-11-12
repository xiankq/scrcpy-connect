import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'identity_manager.dart';

final identityManagementProvider = Provider<IdentityManagement>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.identity)),
);
