import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/platform/independent_window_receipt.dart';
import 'package:scrcpy_connect/core/platform/platform_channels.dart';
import 'package:scrcpy_connect/core/platform/window_launch_route.dart';

typedef DesktopWindowOpener = Future<IndependentWindowReceipt?> Function({
  required String deviceId,
  required String packageName,
  required String sessionId,
});

/// Host boundary for native Activity/scene/window creation.
///
/// Flutter's view and multi-engine APIs do not create a native window by
/// themselves. Unsupported hosts return an explicit same-view fallback, so a
/// logical control session never pretends that a second native window exists.
final class PlatformWindowHost {
  const PlatformWindowHost({
    this.request,
    this.desktopWindowOpen = _openDesktopWindow,
  });

  final Future<Json?> Function(String command, Json params)? request;
  final DesktopWindowOpener desktopWindowOpen;

  Future<IndependentWindowReceipt> open({
    required String deviceId,
    required String packageName,
    required String sessionId,
  }) async {
    final initialRoute = independentWindowLaunchRoute(
      deviceId: deviceId,
      packageName: packageName,
      sessionId: sessionId,
    );
    if (request == null &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      final desktop = await desktopWindowOpen(
        deviceId: deviceId,
        packageName: packageName,
        sessionId: sessionId,
      );
      if (desktop != null) return desktop;
    }
    final requestFn = request ?? const PlatformChannels().requestOptional;
    try {
      final response = await requestFn('window.openIndependent', {
        'deviceId': deviceId,
        'packageName': packageName,
        'sessionId': sessionId,
        'initialRoute': initialRoute,
      });
      if (response?['supported'] == true &&
          response?['windowId'] is String &&
          (response!['windowId'] as String).isNotEmpty) {
        return IndependentWindowReceipt.opened(response['windowId'] as String);
      }
      return IndependentWindowReceipt.fallback(
        response?['reason'] as String? ?? '当前宿主不支持独立原生窗口。',
      );
    } on MissingPluginException {
      return const IndependentWindowReceipt.fallback('当前宿主未提供独立窗口能力。');
    } on PlatformException {
      return const IndependentWindowReceipt.fallback('独立窗口创建失败，已回退到当前窗口。');
    } on WindowChannelException {
      return const IndependentWindowReceipt.fallback('独立窗口创建失败，已回退到当前窗口。');
    }
  }

  static Future<IndependentWindowReceipt?> _openDesktopWindow({
    required String deviceId,
    required String packageName,
    required String sessionId,
  }) async {
    final initialRoute = independentWindowLaunchRoute(
      deviceId: deviceId,
      packageName: packageName,
      sessionId: sessionId,
    );
    try {
      final controller = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({
            'type': 'remote',
            'deviceId': deviceId,
            'packageName': packageName,
            'sessionId': sessionId,
            'initialRoute': initialRoute,
          }),
        ),
      );
      await controller.show();
      return IndependentWindowReceipt.opened(controller.windowId);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on WindowChannelException {
      return null;
    } on Exception {
      return null;
    }
  }
}
