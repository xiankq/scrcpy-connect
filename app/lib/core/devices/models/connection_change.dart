/// 已受理的连接意图。命令入口负责解析，不让连接所有者理解路由或命令名。
enum ConnectionChangeKind {
  setup,
  connect,
  configure,
  stop,
  cancel,
  defaultIdentity,
  deviceIdentity,
  replaceRecords,
}

final class ConnectionChange {
  const ConnectionChange(this.kind, {this.deviceId, this.attemptId});
  final ConnectionChangeKind kind;
  final String? deviceId, attemptId;

  bool get manual =>
      kind == ConnectionChangeKind.setup ||
      kind == ConnectionChangeKind.connect ||
      kind == ConnectionChangeKind.configure;
  bool get stop =>
      kind == ConnectionChangeKind.stop ||
      kind == ConnectionChangeKind.cancel && deviceId != null;
  bool get authorityChange =>
      kind == ConnectionChangeKind.defaultIdentity ||
      kind == ConnectionChangeKind.deviceIdentity ||
      kind == ConnectionChangeKind.replaceRecords;
  bool get supersedesSetup =>
      kind == ConnectionChangeKind.connect ||
      kind == ConnectionChangeKind.configure ||
      kind == ConnectionChangeKind.stop ||
      kind == ConnectionChangeKind.cancel;
}
