import 'file_failure.dart';

enum FileTransferDirection { push, pull }

enum FileTransferConflict {
  ask,
  keepBoth,
  replace,
  skip;

  static FileTransferConflict parse(String value) => switch (value) {
    'ask' => ask,
    'keepBoth' => keepBoth,
    'replace' => replace,
    'skip' => skip,
    _ => throw const FileFailure('invalid_argument', '传输选择或冲突策略无效。'),
  };
}

enum FileTransferDestination {
  localPath,
  privateCache;

  static FileTransferDestination parse(String value) => switch (value) {
    'localPath' => localPath,
    'privateCache' => privateCache,
    _ => throw const FileFailure('cache_unavailable', '私有缓存执行器尚未配置。'),
  };
}

final class FileTransferSelection {
  const FileTransferSelection({
    required this.source,
    required this.destination,
  });
  factory FileTransferSelection.fromJson(Map<String, Object?> value) {
    if (value['source'] is! String || value['destination'] is! String) {
      throw const FileFailure('invalid_argument', '传输来源和目标必须为路径。');
    }
    return FileTransferSelection(
      source: value['source'] as String,
      destination: value['destination'] as String,
    );
  }
  final String source, destination;
  Map<String, Object?> toJson() => {
    'source': source,
    'destination': destination,
  };
}

/// 入口解析后的传输计划。执行器不再读取命令参数或以布尔值猜测传输方向。
final class FileTransferPlan {
  FileTransferPlan({
    required this.deviceId,
    required this.direction,
    required List<FileTransferSelection> items,
    this.conflict = FileTransferConflict.ask,
    this.destination = FileTransferDestination.localPath,
  }) : items = List.unmodifiable(items);
  final String deviceId;
  final FileTransferDirection direction;
  final List<FileTransferSelection> items;
  final FileTransferConflict conflict;
  final FileTransferDestination destination;
}
