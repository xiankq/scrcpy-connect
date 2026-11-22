import 'package:flutter/widgets.dart';

import 'package:scrcpy_connect/router/models/remote_control_intent.dart';

import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/models/remote_launch_intent.dart';
import 'package:scrcpy_connect/router/remote_windows.dart';
import 'package:scrcpy_connect/router/route_resource_resolver_provider.dart';

/// 明确打开意图仅保存在内存中，恢复 URL 不能创建新流；已有会话按身份重新查找。
Future<void> openRemoteRoute(
  BuildContext context, {
  required String deviceId,
  String? sessionId,
  String? packageName,
  String? appName,
  bool onPhoneScreen = false,
  bool requestKeyboard = false,
  RemoteControlIntent? action,
}) async {
  if (deviceId.isEmpty || sessionId == '' || packageName == '') {
    await RouteErrorRoute(
      reason: sessionId == '' ? 'missing-session' : 'missing-record',
    ).push<void>(context);
    return;
  }
  final host = RemoteWindows.maybeOf(context);
  var independentPackage = onPhoneScreen ? null : packageName;
  final initialAction = packageName != null && onPhoneScreen
      ? RemoteControlIntent.launchApp(packageName)
      : action;
  final GoRouteData route;
  final Object? extra;
  if (sessionId != null) {
    if (host != null) {
      final resources = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(routeResourceResolverProvider);
      try {
        final existing = await resources.session(deviceId, sessionId);
        independentPackage = existing.session.packageName;
      } on Exception {
        if (context.mounted) {
          await const RouteErrorRoute(reason: 'missing-session')
              .push<void>(context);
        }
        return;
      }
      if (!context.mounted || !host.mounted) return;
    }
    final sessionAction = host == null ? initialAction : null;
    extra = sessionAction;
    route = RemoteSessionRoute(
      deviceId: deviceId,
      sessionId: sessionId,
      keyboard: requestKeyboard,
      $extra: sessionAction,
    );
  } else if (independentPackage != null) {
    extra = const RemoteLaunchIntent();
    route = RemoteAppRoute(
      deviceId: deviceId,
      packageName: independentPackage,
      keyboard: requestKeyboard,
      $extra: extra,
    );
  } else {
    extra = RemoteLaunchIntent(action: host == null ? initialAction : null);
    route = RemoteRoute(
      deviceId: deviceId,
      keyboard: requestKeyboard,
      $extra: extra,
    );
  }
  if (host != null) {
    host.open(
      (deviceId: deviceId, packageName: independentPackage),
      (observer) => createAppRouter(
        initialLocation: route.location,
        initialExtra: extra,
        observer: observer,
      ),
      appName: appName,
      action: initialAction,
      keyboard: requestKeyboard,
    );
  } else {
    await route.push<void>(context);
  }
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
