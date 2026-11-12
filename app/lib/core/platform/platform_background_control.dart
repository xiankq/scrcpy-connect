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
            ? '桌面进程中的活动'
            : '后台能力尚未确认',
        reason: Platform.isIOS
            ? 'iOS 当前不支持通用持续后台保持。离开 App 后，连接、传输及提醒可能暂停；请返回前台后核对活动。'
            : Platform.isMacOS || Platform.isWindows || Platform.isLinux
            ? '连接与传输依赖应用进程继续运行。系统休眠、退出或结束进程后不保证活动继续；再次打开会核对实际状态。'
            : '当前平台未确认持续后台能力。请保持 App 在前台，并核对活动的实际状态。',
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
