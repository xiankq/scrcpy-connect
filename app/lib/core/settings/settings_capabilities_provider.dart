import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'metadata_management.dart';
import 'settings_management.dart';

final settingsManagementProvider = Provider<SettingsManagement>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.settings)),
);
final metadataManagementProvider = Provider<MetadataManagement>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.metadata)),
);
