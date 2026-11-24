import 'dart:io';

import 'package:flutter/services.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/platform/independent_window_receipt.dart';
import 'package:scrcpy_connect/core/platform/platform_channels.dart';
import 'package:scrcpy_connect/core/platform/window_launch_route.dart';

final class PlatformWindowHost {
  const PlatformWindowHost({this.request});

  static bool get supportsMobileWindows => Platform.isAndroid || Platform.isIOS;
  static const lifecycle = MethodChannel('dev.scrcpyconnect/window_lifecycle');

  final Future<Json?> Function(String command, Json params)? request;
  Future<Json?> _request(String command, Json params) =>
      (request ?? const PlatformChannels().requestOptional)(command, params);

  Future<IndependentWindowReceipt> open({
    required String windowId,
    required String title,
    double? aspectRatio,
    double navigationHeight = 0,
  }) async {
    try {
      final response = await _request('window.openIndependent', {
        'windowId': windowId,
        'initialRoute': independentWindowLaunchRoute(windowId),
        'title': title,
        'aspectRatio': ?aspectRatio,
        'navigationHeight': navigationHeight,
      });
      if (response?['supported'] == true && response?['windowId'] == windowId) {
        return IndependentWindowReceipt.opened(windowId);
      }
      return IndependentWindowReceipt.fallback(
        response?['reason'] as String? ?? '当前宿主不支持独立原生窗口。',
      );
    } on MissingPluginException {
      return const IndependentWindowReceipt.fallback('当前宿主未提供独立窗口能力。');
    } on PlatformException {
      return const IndependentWindowReceipt.fallback('系统未能打开独立窗口。');
    }
  }

  Future<void> close(String windowId) =>
      _request('window.closeIndependent', {'windowId': windowId});

  Future<void> showWorkbench() => _request('window.showWorkbench', {});
}
