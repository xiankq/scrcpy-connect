import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

class FileFailure implements Exception {
  const FileFailure(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

class FileCancellation {
  final _cancelled = Completer<void>();
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  /// 监听持续到取消或返回的移除函数被调用。
  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
      return () {};
    }
    void registered() => listener();
    _listeners.add(registered);
    return () => _listeners.remove(registered);
  }

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void check() {
    if (isCancelled) throw const FileFailure('cancelled', '文件任务已取消。');
  }
}

class FileStamp {
  const FileStamp({
    required this.mode,
    required this.size,
    required this.modifiedSeconds,
    this.modifiedNanos = 0,
    this.modifiedResolutionNanos = 1,
  });
  final int mode, size, modifiedSeconds, modifiedNanos;

  /// 可观察时间分辨率：1 为纳秒、1000 为微秒、1e9 为秒；旧日志按纳秒保守核对。
  final int modifiedResolutionNanos;
  bool get isFile => mode & 0xf000 == 0x8000;
  bool get isDirectory => mode & 0xf000 == 0x4000;
  bool get isLink => mode & 0xf000 == 0xa000;
  String get kind => isFile
      ? 'file'
      : isDirectory
      ? 'directory'
      : isLink
      ? 'symlink'
      : 'unsupported';
  Map<String, Object?> toJson() => {
    'mode': mode,
    'size': size,
    'modifiedSeconds': modifiedSeconds,
    'modifiedNanos': modifiedNanos,
    'modifiedResolutionNanos': modifiedResolutionNanos,
  };
  factory FileStamp.fromJson(Map<String, Object?> value) => FileStamp(
    mode: value['mode']! as int,
    size: value['size']! as int,
    modifiedSeconds: value['modifiedSeconds']! as int,
    modifiedNanos: value['modifiedNanos'] as int? ?? 0,
    modifiedResolutionNanos: _resolution(value['modifiedResolutionNanos']),
  );
  static int _resolution(Object? value) {
    if (value == null) return 1;
    if (value is int && (value == 1 || value == 1000 || value == 1000000000)) {
      return value;
    }
    throw const FormatException('文件时间戳分辨率无效。');
  }

  @override
  bool operator ==(Object other) =>
      other is FileStamp &&
      mode == other.mode &&
      size == other.size &&
      modifiedSeconds == other.modifiedSeconds &&
      modifiedNanos == other.modifiedNanos &&
      modifiedResolutionNanos == other.modifiedResolutionNanos;
  @override
  int get hashCode => Object.hash(
    mode,
    size,
    modifiedSeconds,
    modifiedNanos,
    modifiedResolutionNanos,
  );
}

class FileEntryFact {
  const FileEntryFact({required this.nameBytes, this.stamp, this.error});
  final Uint8List nameBytes;
  final FileStamp? stamp;
  final FileFailure? error;
  String get displayName => utf8.decode(nameBytes, allowMalformed: true);
  String? get pathName {
    try {
      final name = utf8.decode(nameBytes);
      return name.isEmpty ||
              name == '.' ||
              name == '..' ||
              name.contains('/') ||
              name.contains('\u0000')
          ? null
          : name;
    } on FormatException {
      return null;
    }
  }
}

class DirectoryFacts {
  const DirectoryFacts(this.entries, {required this.truncated});
  final List<FileEntryFact> entries;
  final bool truncated;
}

/// 执行本机与被控设备文件操作，不持有排序、遍历、冲突策略或任务状态。
/// 实现返回类型化批次并直接写入未发布片段；取消成功前必须完成 worker 清理。
/// 清理失败须保留精确执行对象供重试，不能以调用结束代替实际资源退出。
abstract interface class FileExecutor {
  Future<FileStamp> stat(
    String device,
    String path, {
    required bool local,
    bool followStorageAlias = false,
    required FileCancellation cancellation,
  });
  Future<DirectoryFacts> list(
    String device,
    String path, {
    required bool local,
    required int limit,
    required FileCancellation cancellation,
  });
  Future<int> copy(
    String device,
    String source,
    String temporary, {
    required bool push,
    required FileStamp expected,
    required FileCancellation cancellation,
    required void Function(int) onProgress,
  });
  Future<String> mutate(
    String device,
    String action,
    String path, {
    String destination = '',
    bool local = false,
    bool replace = false,
    required FileCancellation cancellation,
  });
}

/// 已完成执行域接管的事实；同 key 换发 id 前必须实际排空旧域的操作与片段。
///
/// 这两个值来自执行能力的真实 attach，不是产品设备 ID，也不授予旧域关闭权。
abstract interface class ScopedFileExecutor {
  String get fileScopeKey;
  String get fileScopeId;
}

/// 用户明确提交的一批远端变更；创建时固定连接，后续项目不得重选设备连接。
abstract interface class FileMutationExecutor {
  Future<FileMutationBatch> beginMutation(
    String device, {
    required FileCancellation cancellation,
  });
}

/// 保留本批已创建的精确执行句柄；关闭失败时必须保留本对象供重试。
abstract interface class FileMutationBatch {
  Future<String> mutate(String action, String path, {String destination = ''});

  /// 撤销本批准入，并等待已创建或迟到交付的执行资源实际释放。
  Future<void> close();
}

/// 一次精确执行的回收责任；失败后保留同一对象重试，不关闭共享连接。
abstract interface class FileExecutionResource {
  Future<void> close();
}

/// 单次便捷调用回收失败时，把精确执行对象交还调用者，而非只保留错误文本。
final class FileExecutionCleanupFailure extends FileFailure {
  FileExecutionCleanupFailure(this.execution, this.cause)
    : super('file_cleanup_unconfirmed', '文件执行资源尚未确认释放：$cause');
  final FileExecutionResource execution;
  final Object cause;
}

/// 预览读取在创建时固定连接，元数据、传输和发布共用同一资源所有者。
abstract interface class FileReadExecutor {
  Future<FileReadBatch> beginRead(
    String device, {
    required FileCancellation cancellation,
  });
}

/// 暂存片段属于本批；close 先排空全部执行，再精确释放未发布片段。
abstract interface class FileReadBatch implements FileExecutionResource {
  Future<FileStamp> stat(String path);
  Future<int> copy(
    String source,
    String temporary, {
    required FileStamp expected,
    required void Function(int) onProgress,
  });
  Future<void> commit(String temporary, String destination);
}

class FileCacheReservation {
  const FileCacheReservation(this.path, this.bytes);
  final String path;
  final int bytes;
}

/// 本机缓存预算准入与路径租约，不另建任务状态所有者。
abstract interface class FileCacheLeases {
  Future<String> reserve(List<FileCacheReservation> reservations);
  Future<void> release(String lease);
}

/// 记录分享来源与传输批次的发布关系，保护仍被任务引用的导入缓存。
/// 导入描述符只在读取来源期间存活，不由发布记录持有。
abstract interface class FilePublicationLeases {
  Future<Map<String, Object?>?> begin(
    String share,
    Map<String, Object?> request,
  );
  Future<void> finish(
    String share,
    Map<String, Object?>? receipt, {
    bool definitelyUnpublished = false,
  });
  Future<Map<String, Object?>> reconcile(
    Map<String, Object?> durableReferences,
  );
}
