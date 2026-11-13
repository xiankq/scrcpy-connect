import 'package:flutter/services.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/platform/independent_window_receipt.dart';
import 'package:scrcpy_connect/core/platform/platform_channels.dart';

/// Host boundary for native Activity/scene/window creation.
///
/// Flutter's view and multi-engine APIs do not create a native window by
/// themselves. Unsupported hosts return an explicit same-view fallback, so a
/// logical control session never pretends that a second native window exists.
final class PlatformWindowHost {
  const PlatformWindowHost({this.request});

  final Future<Json?> Function(String command, Json params)? request;

  Future<IndependentWindowReceipt> open({
    required String deviceId,
    required String packageName,
    required String sessionId,
  }) async {
    final requestFn = request ?? const PlatformChannels().requestOptional;
    try {
      final response = await requestFn('window.openIndependent', {
        'deviceId': deviceId,
        'packageName': packageName,
        'sessionId': sessionId,
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
    }
  }
}
