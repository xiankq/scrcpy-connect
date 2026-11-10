import 'package:scrcpy_connect/services/media/audio_player.dart';

/// 独立于设备媒体输出应用全局偏好；原生宿主持有前台服务生命周期及显式停止状态。
class ApplicationBackgroundCoordinator {
  ApplicationBackgroundCoordinator({
    required this.request,
    required this.audioPolicy,
    required this.emit,
  });

  final AudioRequest? request;
  final Future<void> Function(bool) audioPolicy;
  final void Function(AudioJson) emit;

  Future<AudioJson?> apply(bool enabled, {required bool automatic}) async {
    AudioJson? receipt;
    if (request case final platform?) {
      try {
        final status = await platform('background.request', {
          'enabled': enabled,
          'automatic': automatic,
        });
        receipt = status;
        emit({'type': 'background.changed', 'data': status});
      } catch (error) {
        // 平台拒绝以状态呈现，保留偏好并允许其余启动流程继续，不能据此开始媒体播放。
        emit({
          'type': 'background.failed',
          'data': {'reason': '$error'},
        });
      }
    }
    await audioPolicy(enabled);
    return receipt;
  }
}
