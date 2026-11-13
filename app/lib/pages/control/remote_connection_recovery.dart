import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/devices/models/device_disconnect_requested.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/models/video_stop_requested.dart';

/// 只为已查看的手机画面保存短暂恢复意图，连接变化本身不能新建会话、重放打开或撤销停止。
class RemoteConnectionRecovery {
  bool _viewed = false;
  bool pending = false;
  bool _connected = false;

  /// 只追踪本窗口的连接意图；返回 true 表示接受了明确停止，调用者须作废在途恢复。
  bool acceptEvent(
    RuntimeEvent event, {
    required String deviceId,
    required String sessionId,
    required bool phoneScreen,
  }) {
    final payload = event.data;
    if ((payload is VideoStopRequested && payload.sessionId == sessionId) ||
        (payload is DeviceDisconnectRequested &&
            payload.deviceId == deviceId)) {
      stop();
      return true;
    }
    if (phoneScreen && payload is DeviceListChanged) {
      final device = payload.devices.where((d) => d.id == deviceId).firstOrNull;
      if (device == null) {
        stop();
      } else {
        observe(device.status, autoReconnect: device.autoReconnect);
      }
    }
    return false;
  }

  void viewed() {
    _viewed = true;
    pending = false;
  }

  void stop() {
    _viewed = false;
    pending = false;
  }

  void observe(DeviceConnectionStatus status, {required bool autoReconnect}) {
    _connected = status == .connected;
    if (!autoReconnect) {
      stop();
    } else if (_viewed && status == .offline) {
      pending = true;
    }
  }

  bool take() {
    if (!pending || !_connected) return false;
    pending = false;
    return true;
  }

  void defer() {
    if (_viewed) pending = true;
  }
}
