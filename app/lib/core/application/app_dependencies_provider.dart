import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app_dependencies.dart';

export 'app_dependencies.dart';

part 'app_dependencies_provider.g.dart';

@Riverpod(keepAlive: true)
AppDependencies appDependencies(Ref ref) => throw StateError(
  'The application transport must be supplied at bootstrap.',
);
