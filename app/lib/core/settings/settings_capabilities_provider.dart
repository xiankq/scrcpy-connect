import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'metadata_management.dart';
import 'settings_management.dart';

final settingsManagementProvider = Provider<SettingsManagement>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final metadataManagementProvider = Provider<MetadataManagement>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
