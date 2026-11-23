import 'dart:io';

import 'package:flutter/services.dart';
import 'package:json_annotation/json_annotation.dart'
    show CheckedFromJsonException;
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/platform/background_control.dart';

/// 系统后台保持协议的适配；产品偏好与媒体策略由 BackgroundPolicy 协调。
final class PlatformBackgroundControl implements BackgroundControl {
  PlatformBackgroundControl({required this._request, required this.isDisposed});
  final Future<Json> Function(String, Json) _request;
  final bool Function() isDisposed;
  bool get _disposed => isDisposed();

  @override
  Future<BackgroundStatus> readBackgroundStatus() =>
      _readBackground('background.status', const {});

  @override
  Future<BackgroundStatus> requestBackground({
    required bool enabled,
    bool automatic = false,
    bool askNotificationPermission = false,
  }) => _readBackground('background.request', {
    'enabled': enabled,
    'automatic': automatic,
    'askNotificationPermission': askNotificationPermission,
  });

  Future<BackgroundStatus> _readBackground(
    String method,
    Map<String, Object?> params,
  ) async {
    void check() {
      if (_disposed) throw const RequestFailure('disposed', '应用平台已关闭。');
    }

    check();
    if (!Platform.isAndroid) {
      return BackgroundStatus(
        platform: Platform.operatingSystem,
        title: Platform.isIOS
            ? 'iOS 后台限制'
            : Platform.isMacOS || Platform.isWindows || Platform.isLinux
            ? '应用运行时保持连接'
            : '后台运行状态未知',
        reason: Platform.isIOS
            ? '离开应用后，连接、传输和提醒可能暂停。请回到应用查看进度。'
            : Platform.isMacOS || Platform.isWindows || Platform.isLinux
            ? '退出应用或电脑休眠时，连接和传输可能暂停。再次打开应用可查看进度。'
            : '暂时无法确认后台能否保持连接。请让应用留在前台。',
      );
    }
    try {
      final result = await _request(method, params);
      check();
      return BackgroundStatus.fromJson(result);
    } on CheckedFromJsonException catch (_, stack) {
      Error.throwWithStackTrace(
        const RequestFailure('background_status_invalid', '未能核验系统后台状态，请重新检查。'),
        stack,
      );
    } on PlatformException catch (error, stack) {
      Error.throwWithStackTrace(
        RequestFailure(error.code, error.message ?? '系统后台操作未完成。'),
        stack,
      );
    }
  }
}
