/// 会话事件处理后，视图需要继续协调的连接或可见性工作。
enum RemoteSessionEvent {
  unhandled,
  handled,
  connected,
  disconnected,
  reconciled,
}
