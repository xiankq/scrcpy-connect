import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'diagnostic_log.dart';

final diagnosticLogProvider = Provider<DiagnosticLog?>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.diagnostics)),
);
