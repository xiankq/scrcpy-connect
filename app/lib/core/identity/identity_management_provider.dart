import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'identity_manager.dart';

final identityManagementProvider = Provider<IdentityManagement>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
