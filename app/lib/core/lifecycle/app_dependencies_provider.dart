import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies.dart';

export 'package:scrcpy_connect/core/lifecycle/app_dependencies.dart';

part 'app_dependencies_provider.g.dart';

@Riverpod(keepAlive: true)
AppDependencies appDependencies(Ref ref) => throw StateError(
  'The application transport must be supplied at bootstrap.',
);
