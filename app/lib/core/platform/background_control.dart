import 'package:scrcpy_connect/core/platform/models/background_status.dart';

export 'package:scrcpy_connect/core/platform/models/background_status.dart';

/// 状态读取不会申请权限；自动恢复必须保留宿主的显式停止意图。
abstract interface class BackgroundControl {
  Future<BackgroundStatus> readBackgroundStatus();
  Future<BackgroundStatus> requestBackground({
    required bool enabled,
    bool automatic = false,
    bool askNotificationPermission = false,
  });
}
