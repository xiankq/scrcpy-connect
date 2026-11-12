import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/platform/background_control.dart';
import 'package:scrcpy_connect/core/platform/models/background_event.dart';

/// 独立于设备媒体输出应用全局偏好；原生宿主持有前台服务生命周期及显式停止状态。
class BackgroundPolicy {
  BackgroundPolicy({
    required this.platform,
    required this.audioPolicy,
    required this.onEvent,
    required this.isDisposed,
  });

  final BackgroundControl? platform;
  final Future<void> Function(bool) audioPolicy;
  final void Function(BackgroundEvent) onEvent;
  final bool Function() isDisposed;

  void _checkOpen() {
    if (isDisposed()) throw const RequestFailure('disposed', '后台策略已关闭。');
  }

  Future<BackgroundStatus?> apply(
    bool enabled, {
    required bool automatic,
  }) async {
    _checkOpen();
    BackgroundStatus? receipt;
    if (platform case final background?) {
      try {
        receipt = await background.requestBackground(
          enabled: enabled,
          automatic: automatic,
        );
      } catch (error) {
        _checkOpen();
        // 平台拒绝保留偏好并允许其余启动流程继续，不能据此开始媒体播放。
        onEvent(BackgroundFailed('$error'));
      }
    }
    _checkOpen();
    if (receipt != null) onEvent(BackgroundChanged(receipt));
    _checkOpen();
    await audioPolicy(enabled);
    _checkOpen();
    return receipt;
  }
}
