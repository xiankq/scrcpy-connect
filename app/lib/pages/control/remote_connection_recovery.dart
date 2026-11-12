/// 只为已查看的手机画面保存短暂恢复意图，连接变化本身不能新建会话、重放打开或撤销停止。
class RemoteConnectionRecovery {
  bool _viewed = false;
  bool pending = false;
  bool _connected = false;

  void viewed() {
    _viewed = true;
    pending = false;
  }

  void stop() {
    _viewed = false;
    pending = false;
  }

  void observe(String status, {required bool autoReconnect}) {
    _connected = status == 'connected';
    if (!autoReconnect) {
      stop();
    } else if (_viewed && status == 'offline') {
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
