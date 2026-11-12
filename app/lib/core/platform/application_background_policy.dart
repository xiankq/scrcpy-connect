import 'background_control.dart';

/// 独立于设备媒体输出应用全局偏好；原生宿主持有前台服务生命周期及显式停止状态。
class ApplicationBackgroundPolicy {
  ApplicationBackgroundPolicy({
    required this.platform,
    required this.audioPolicy,
    required this.onChanged,
    required this.onFailure,
  });

  final BackgroundControl? platform;
  final Future<void> Function(bool) audioPolicy;
  final void Function(BackgroundStatus) onChanged;
  final void Function(Object) onFailure;

  Future<BackgroundStatus?> apply(
    bool enabled, {
    required bool automatic,
  }) async {
    BackgroundStatus? receipt;
    if (platform case final background?) {
      try {
        receipt = await background.requestBackground(
          enabled: enabled,
          automatic: automatic,
        );
        onChanged(receipt);
      } catch (error) {
        // 平台拒绝保留偏好并允许其余启动流程继续，不能据此开始媒体播放。
        onFailure(error);
      }
    }
    await audioPolicy(enabled);
    return receipt;
  }
}
