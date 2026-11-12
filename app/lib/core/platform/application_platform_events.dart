import 'package:scrcpy_connect/core/devices/device_reconnect_service.dart';

/// 宿主事实不参与核心事件序列；同步撤销本地准入，再发布事件并交接异步清理。
class ApplicationPlatformEvents {
  ApplicationPlatformEvents({
    required this.reconnections,
    required this.isDisposed,
    required this.emit,
    required this.handleShare,
    required this.handleMedia,
    required this.stopConnections,
  });

  final DeviceReconnectService reconnections;
  final bool Function() isDisposed;
  final void Function(Map<String, dynamic>) emit;
  final Future<void> Function(Map<String, dynamic>) handleShare;
  final Future<void> Function(Map<String, dynamic>) handleMedia;
  final Future<void> Function() stopConnections;

  Future<void> handle(Map<String, dynamic> event) async {
    if (isDisposed()) return;
    if (event['type'] == 'connections.stopped') {
      // 宿主停止是独立事实，先同步撤销重连；不能等待带序列号的核心事件或媒体清理。
      reconnections.stopAutomaticConnections();
      // 同步执行回调直到其第一次挂起，事件消费者只能看到已经撤销的连接。
      // 两条清理均登记监听；任一路径失败都不能跳过另一条或提前返回。
      final stopped = Future<void>.sync(stopConnections);
      final published = Future<void>.sync(() => emit(event));
      final media = Future<void>.sync(() => handleMedia(event));
      await Future.wait([stopped, published, media]);
      return;
    }
    emit(event);
    final data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : const <String, dynamic>{};
    if (data['visible'] is bool &&
        event['type'].toString().startsWith('audio.platform.')) {
      reconnections.setVisible(data['visible'] as bool);
    }
    if (event['type'] == 'share.platform.pending') {
      await handleShare(data);
    } else if (event['type']?.toString().startsWith('audio.platform.') ==
        true) {
      await handleMedia(event);
    }
  }
}
