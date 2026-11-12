import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app_dependencies_provider.dart';
import 'application_session.dart';

part 'application_session_provider.g.dart';

@Riverpod(keepAlive: true)
ApplicationSession applicationSession(Ref ref) {
  final session = ApplicationSession(ref.watch(appDependenciesProvider));
  ref.onDispose(session.dispose);
  return session;
}
