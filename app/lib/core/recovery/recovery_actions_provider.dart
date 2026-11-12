import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

final reconcileStateProvider = Provider<Future<void> Function()>(
  (ref) =>
      ref.watch(appDependenciesProvider.select((app) => app.reconcileState)),
);
