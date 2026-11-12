import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'diagnostic_log.dart';

final diagnosticLogProvider = Provider<DiagnosticLog?>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
