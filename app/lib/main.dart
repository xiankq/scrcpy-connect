import 'package:scrcpy_connect/core/diagnostics/diagnostic_record.dart';
import 'package:scrcpy_connect/core/diagnostics/application_diagnostics.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart'
    show DiagnosticLog;
import 'package:scrcpy_connect/core/application/app_dependencies_provider.dart';
import 'package:scrcpy_connect/bootstrap/app_bootstrap.dart';
import 'package:scrcpy_connect/widgets/system_notification_sink.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/startup_error/startup_error_page.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DiagnosticLog? diagnostics;
  try {
    diagnostics = await applicationDiagnostics();
    diagnostics.record(DiagnosticArea.app, 'bootstrap.started');
    await GlassMaterial.initialize();
    final dependencies = await bootstrapApplication(diagnostics: diagnostics);
    diagnostics.record(DiagnosticArea.app, 'bootstrap.ready');
    runApp(
      ProviderScope(
        overrides: [
          appDependenciesProvider.overrideWithValue(dependencies),
          systemNotificationSinkProvider.overrideWithValue(
            LocalNotificationSink(),
          ),
        ],
        child: GlassMaterial.wrap(child: const ConnectApp()),
      ),
    );
  } catch (error) {
    diagnostics?.record(
      DiagnosticArea.app,
      'bootstrap.failed',
      level: LogLevel.error,
      fields: {'errorType': error.runtimeType.toString()},
    );
    await diagnostics?.flush();
    runApp(
      ProviderScope(
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: StartupErrorPage(error: error, onRetry: main),
        ),
      ),
    );
  }
}
