import 'package:scrcpy_connect/services/app_dependencies.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/startup_error/startup_error_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:interop_bridge/interop_bridge.dart';
import 'package:path_provider/path_provider.dart';
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
    final directory = await getApplicationSupportDirectory();
    final bridge = await InteropBridge.initialize(
      dataDirectory: directory.path,
    );
    final dependencies = AppDependencies(
      request: (command, [params = const {}]) async {
        try {
          return await bridge.request(command, params);
        } on InteropException catch (error) {
          throw RequestFailure(error.code, error.message, error.details);
        }
      },
      events: bridge.events,
      close: bridge.dispose,
    );
    runApp(
      ProviderScope(
        overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
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
