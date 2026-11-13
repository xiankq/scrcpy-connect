import 'package:scrcpy_connect/core/files/models/platform_share_notice.dart';
import 'package:scrcpy_connect/core/devices/device_reconnect_service.dart';
import 'package:scrcpy_connect/core/devices/models/connections_stopped.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/audio_platform.dart';
import 'package:scrcpy_connect/core/media/platform_audio.dart';

/// 宿主事实不参与核心事件序列；同步撤销本地准入，再发布事件并交接异步清理。
class PlatformEventHandler {
  PlatformEventHandler({
    required this.reconnections,
    required this.isDisposed,
    required this.emit,
    required this.handleShare,
    required this.handleAudio,
    required this.stopMedia,
    required this.stopConnections,
  });

  final DeviceReconnectService reconnections;
  final bool Function() isDisposed;
  final void Function(AppEvent) emit;
  final Future<void> Function(PlatformShareNotice) handleShare;
  final Future<void> Function(AudioPlatformEvent) handleAudio;
  final Future<void> Function() stopMedia;
  final Future<void> Function() stopConnections;

  Future<void> handle(Map<String, dynamic> event) async {
    if (isDisposed()) return;
    if (event['type'] == 'connections.stopped') {
      // 宿主停止是独立事实，先同步撤销重连；不能等待带序列号的核心事件或媒体清理。
      reconnections.stopAutomaticConnections();
      // 同步执行回调直到其第一次挂起，事件消费者只能看到已经撤销的连接。
      // 两条清理均登记监听；任一路径失败都不能跳过另一条或提前返回。
      final stopped = Future<void>.sync(stopConnections);
      final published = Future<void>.sync(
        () => emit(const ConnectionsStopped()),
      );
      final media = Future<void>.sync(stopMedia);
      await Future.wait([stopped, published, media]);
      return;
    }
    if (event['type'] == 'share.platform.pending') {
      await handleShare(PlatformShareNotice.fromJson(event['data']));
    } else if (decodeAudioPlatformEvent(event) case final audio?) {
      if (audio case AudioVisibilityChanged(:final visible)) {
        reconnections.setVisible(visible);
      }
      await handleAudio(audio);
    }
  }
}
