import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription.dart';

part 'state_subscription_provider.g.dart';

@Riverpod(keepAlive: true)
StateSubscription stateSubscription(Ref ref) {
  final session = StateSubscription(ref.watch(appDependenciesProvider));
  ref.onDispose(session.dispose);
  return session;
}
