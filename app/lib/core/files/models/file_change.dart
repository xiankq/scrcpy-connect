enum FileChangeKind { connection, recovery, directory, transfer }

/// 文件功能消费的变更事实；原始事件类型在功能入口处解释。
final class FileChange {
  const FileChange(this.kind, {this.deviceId, this.path});
  final FileChangeKind kind;
  final String? deviceId;
  final String? path;
}
