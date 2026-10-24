import 'package:scrcpy_connect/platform/application_diagnostics.dart';
import 'package:scrcpy_connect/platform/diagnostics/diagnostic_log.dart'
    show DiagnosticLog, DiagnosticArea, LogLevel;
import 'package:scrcpy_connect/application/app_dependencies.dart';
import 'package:scrcpy_connect/application/app_bootstrap.dart';
import 'package:scrcpy_connect/platform/local_notification_sink.dart';
import 'package:scrcpy_connect/platform/system_notification_coordinator.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/startup_error/startup_error_page.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:design_system/design_system.dart';

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
