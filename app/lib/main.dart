import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/bootstrap/app_bootstrap.dart';
import 'package:scrcpy_connect/core/diagnostics/app_diagnostics.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart'
    show DiagnosticLog;
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/pages/startup_error/startup_error_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/core/notifications/local_notification_sink.dart';
import 'package:scrcpy_connect/core/notifications/system_notification_sink_provider.dart';
import 'package:scrcpy_connect/core/platform/window_launch_route.dart';

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  final launch = await _windowLaunch();
  DiagnosticLog? diagnostics;
  try {
    diagnostics = await appDiagnostics();
    diagnostics.record(DiagnosticArea.app, 'bootstrap.started');
    await GlassMaterial.initialize();
    final bootstrap = await bootstrapApp(diagnostics: diagnostics);
    diagnostics.record(DiagnosticArea.app, 'bootstrap.ready');
    runApp(
      ProviderScope(
        overrides: [
          ...bootstrap.overrides,
          systemNotificationSinkProvider.overrideWithValue(
            LocalNotificationSink(),
          ),
        ],
        child: GlassMaterial.wrap(
          child: ConnectApp(initialLocation: launch.initialLocation),
        ),
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
          home: StartupErrorPage(error: error, onRetry: () => main(args)),
        ),
      ),
    );
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
    if (decoded is! Map) return const _WindowLaunch('/devices');
    final type = decoded['type'];
    final deviceId = decoded['deviceId'];
    final packageName = decoded['packageName'];
    final sessionId = decoded['sessionId'];
    if (type != 'remote' || deviceId is! String || packageName is! String) {
      return const _WindowLaunch('/devices');
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
  } on PlatformException {
    return const _WindowLaunch('/devices');
  } on WindowChannelException {
    return const _WindowLaunch('/devices');
  } on FormatException {
    return const _WindowLaunch('/devices');
  } on Exception {
    return const _WindowLaunch('/devices');
  }
}
