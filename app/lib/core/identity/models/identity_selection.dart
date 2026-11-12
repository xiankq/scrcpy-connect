/// 连接尝试持有的身份快照；路径只供 SDK 使用，不进入页面、事件或设备元数据。
final class IdentitySelection {
  const IdentitySelection(
    this.path,
    this.fingerprint,
    this.scope,
    this.generation,
    this.deviceId,
  );
  final String path, fingerprint, scope;
  final int generation;
  final String? deviceId;
}
