import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/remote_launch_intent.dart';

/// Explicit user intent is deliberately transient; restored URLs cannot create
/// another stream. Existing sessions are always resolved by their identity.
Future<void> openRemoteRoute(
  BuildContext context, {
  required String deviceId,
  String? sessionId,
  String? packageName,
  bool requestKeyboard = false,
}) {
  if (deviceId.isEmpty || sessionId == '' || packageName == '') {
    return RouteErrorRoute(
      reason: sessionId == '' ? 'missing-session' : 'missing-record',
    ).push<void>(context);
  }
  if (sessionId != null) {
    return RemoteSessionRoute(
      deviceId: deviceId,
      sessionId: sessionId,
      keyboard: requestKeyboard,
    ).push<void>(context);
  }
  if (packageName != null) {
    return RemoteAppRoute(
      deviceId: deviceId,
      packageName: packageName,
      keyboard: requestKeyboard,
      $extra: const RemoteLaunchIntent(),
    ).push<void>(context);
  }
  return RemoteRoute(
    deviceId: deviceId,
    keyboard: requestKeyboard,
    $extra: const RemoteLaunchIntent(),
  ).push<void>(context);
}

void closePage<T>(BuildContext context, [T? result]) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop<T>(result);
  } else {
    const DevicesRoute().go(context);
  }
}

void goDevices(BuildContext context) => const DevicesRoute().go(context);
