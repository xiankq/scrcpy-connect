/// Transient intent for an already viewed phone screen. Device connectivity
/// alone must never create a session, repeat an app launch, or undo a stop.
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
