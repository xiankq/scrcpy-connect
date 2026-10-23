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
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
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
  });
  final int mode, size, modifiedSeconds, modifiedNanos;
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
  };
  factory FileStamp.fromJson(Map<String, Object?> value) => FileStamp(
    mode: value['mode']! as int,
    size: value['size']! as int,
    modifiedSeconds: value['modifiedSeconds']! as int,
    modifiedNanos: value['modifiedNanos'] as int? ?? 0,
  );
  @override
  bool operator ==(Object other) =>
      other is FileStamp &&
      mode == other.mode &&
      size == other.size &&
      modifiedSeconds == other.modifiedSeconds &&
      modifiedNanos == other.modifiedNanos;
  @override
  int get hashCode => Object.hash(mode, size, modifiedSeconds, modifiedNanos);
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

/// Device execution only: no sorting, traversal, conflict policy or task state.
/// Implementations return typed batches and copy files directly into unpublished
/// parts. A cancelled call must finish cleaning up its worker before returning.
abstract interface class RemoteFileExecutor {
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

class FileCacheReservation {
  const FileCacheReservation(this.path, this.bytes);
  final String path;
  final int bytes;
}

/// Native cache admission and path leases, without a second task-state owner.
abstract interface class RemoteFileCache {
  Future<String> reserve(List<FileCacheReservation> reservations);
  Future<void> release(String lease);
}

/// Retains OS imported-source descriptors while the Dart journal owns a task.
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
