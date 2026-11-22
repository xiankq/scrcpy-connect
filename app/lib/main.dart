import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/app_startup.dart';
import 'package:scrcpy_connect/bootstrap/app_bootstrap.dart';
import 'package:scrcpy_connect/core/diagnostics/app_diagnostics.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart'
    show DiagnosticLog;
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/core/platform/window_launch_route.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';

Future<void> main([List<String> args = const []]) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final launch = await _windowLaunch();
  // AppStartup mounts the Riverpod scope and attaches session overrides after the first frame.
  // ignore: riverpod_lint/missing_provider_scope
  runApp(
    AppStartup(
      initialLocation: launch.initialLocation,
      desktopWindow: Platform.isMacOS || Platform.isWindows || Platform.isLinux,
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

final class _WindowLaunch {
  const _WindowLaunch(this.initialLocation);
  final String initialLocation;
}

Future<_WindowLaunch> _windowLaunch() async {
  final requestedRoute =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  final mobileWindow = decodeIndependentWindowLaunchRoute(requestedRoute);
  if (mobileWindow != null) {
    return _WindowLaunch(
      RemoteSessionRoute(
        deviceId: mobileWindow['deviceId']!,
        sessionId: mobileWindow['sessionId']!,
      ).location,
    );
  }
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
    return const _WindowLaunch('/devices');
  }
  try {
    final controller = await WindowController.fromCurrentEngine();
    if (controller.arguments.isEmpty) return const _WindowLaunch('/devices');
    final decoded = jsonDecode(controller.arguments);
    final unavailable = RouteErrorRoute(reason: 'missing-session').location;
    if (decoded is! Map) return _WindowLaunch(unavailable);
    final type = decoded['type'];
    final deviceId = decoded['deviceId'];
    final packageName = decoded['packageName'];
    final sessionId = decoded['sessionId'];
    if (type != 'remote' || deviceId is! String || packageName is! String) {
      return _WindowLaunch(unavailable);
    }
    if (sessionId is String && sessionId.isNotEmpty) {
      return _WindowLaunch(
        RemoteSessionRoute(deviceId: deviceId, sessionId: sessionId).location,
      );
    }
    return _WindowLaunch(
      RemoteAppRoute(deviceId: deviceId, packageName: packageName).location,
    );
  } on MissingPluginException {
    return const _WindowLaunch('/devices');
  } on FormatException {
    return _WindowLaunch(RouteErrorRoute(reason: 'missing-session').location);
  } on Exception catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        context: ErrorDescription('reading the desktop window launch'),
      ),
    );
    return const _WindowLaunch('/devices');
  }
}
