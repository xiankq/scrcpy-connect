import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/app_startup.dart';
import 'package:scrcpy_connect/bootstrap/app_bootstrap.dart';
import 'package:scrcpy_connect/core/diagnostics/app_diagnostics.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart'
    show DiagnosticLog;
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/router/desktop_remote_window.dart';
import 'package:scrcpy_connect/core/platform/platform_window_host.dart';
import 'package:scrcpy_connect/core/platform/window_launch_route.dart';
import 'package:scrcpy_connect/router/mobile_remote_app.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';

Future<void> main([List<String> args = const []]) async {
  enableDesktopRemoteWindows();
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final initialRoute = binding.platformDispatcher.defaultRouteName;
  if (decodeIndependentWindowLaunchRoute(initialRoute) case final windowId?) {
    // This engine borrows the workbench's session capabilities.
    // ignore: riverpod_lint/missing_provider_scope
    runApp(MobileRemoteApp(windowId: windowId));
    return;
  }
  // A second engine cannot own the application's ADB admission scope.
  if (await _isSeparateEngine()) {
    // This message has no application session or provider dependencies.
    // ignore: riverpod_lint/missing_provider_scope
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('请在主窗口的「远控窗口」中继续。'))),
      ),
    );
    return;
  }
  // AppStartup mounts the Riverpod scope and attaches session overrides after the first frame.
  // ignore: riverpod_lint/missing_provider_scope
  runApp(
    AppStartup(
      initialLocation: '/devices',
      desktopWindow: Platform.isMacOS || Platform.isWindows || Platform.isLinux,
      mobileWindow: PlatformWindowHost.supportsMobileWindows,
      initializeGlass: () async {
        await binding.waitUntilFirstFrameRasterized;
        await GlassMaterial.initialize();
      },
      loadSession: () async {
        await binding.waitUntilFirstFrameRasterized;
        return _loadSession();
      },
    ),
  );
}

Future<AppBootstrap> _loadSession() async {
  DiagnosticLog? diagnostics;
  try {
    diagnostics = await appDiagnostics();
    diagnostics.record(DiagnosticArea.app, 'bootstrap.started');
    final session = await bootstrapApp(diagnostics: diagnostics);
    diagnostics.record(DiagnosticArea.app, 'bootstrap.ready');
    return session;
  } catch (error) {
    diagnostics?.record(
      DiagnosticArea.app,
      'bootstrap.failed',
      level: LogLevel.error,
      fields: {'errorType': error.runtimeType.toString()},
    );
    await diagnostics?.flush();
    rethrow;
  }
}

Future<bool> _isSeparateEngine() async {
  final requestedRoute =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  if (Uri.tryParse(requestedRoute)?.path == '/__independent_remote') {
    return true;
  }
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
    return false;
  }
  try {
    final controller = await WindowController.fromCurrentEngine();
    return controller.arguments.isNotEmpty;
  } on MissingPluginException {
    return false;
  } on Exception catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        context: ErrorDescription('reading the desktop window launch'),
      ),
    );
    return false;
  }
}
