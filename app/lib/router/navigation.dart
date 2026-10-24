import 'package:flutter/widgets.dart';

import 'remote_control_intent.dart';

import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/remote_launch_intent.dart';

/// 明确打开意图仅保存在内存中，恢复 URL 不能创建新流；已有会话按身份重新查找。
Future<void> openRemoteRoute(
  BuildContext context, {
  required String deviceId,
  String? sessionId,
  String? packageName,
  bool onPhoneScreen = false,
  bool requestKeyboard = false,
  RemoteControlIntent? action,
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
      $extra: action,
    ).push<void>(context);
  }
  if (packageName != null) {
    if (onPhoneScreen) {
      return RemoteRoute(
        deviceId: deviceId,
        keyboard: requestKeyboard,
        $extra: RemoteLaunchIntent(
          action: RemoteControlIntent.launchApp(packageName),
        ),
      ).push<void>(context);
    }
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
