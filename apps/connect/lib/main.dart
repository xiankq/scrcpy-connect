import 'package:scrcpy_connect/services/app_dependencies.dart';
import 'package:scrcpy_connect/services/app_bootstrap.dart';
import 'package:scrcpy_connect/services/local_notification_sink.dart';
import 'package:scrcpy_connect/services/system_notifications.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/startup_error/startup_error_page.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:design_system/design_system.dart';
import 'package:fvp/fvp.dart' as fvp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  fvp.registerWith(
    options: {
      'platforms': ['windows', 'linux'],
    },
  );
  try {
    final dependencies = await bootstrapApplication();
    runApp(
      ProviderScope(
        overrides: [
          appDependenciesProvider.overrideWithValue(dependencies),
          systemNotificationSinkProvider.overrideWithValue(
            LocalNotificationSink(),
          ),
        ],
        child: const ConnectApp(),
      ),
    );
  } catch (error) {
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
