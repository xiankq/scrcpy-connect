/// 当前可同步的获焦控制画面；所有权由焦点租约维护。
class ClipboardFocus {
  const ClipboardFocus({required this.deviceId, required this.sessionId});

  final String deviceId;
  final String sessionId;
}
