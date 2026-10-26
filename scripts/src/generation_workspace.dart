import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 同步私有生成输入，保持未变文件的时间戳；删除已移除的输入，避免缓存掩盖漂移。
void synchronizeInputs(Map<String, File> inputs, Directory workspace) {
  workspace.createSync(recursive: true);
  for (final entity in workspace.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is Directory) continue;
    final name = p.relative(entity.path, from: workspace.path);
    if (!inputs.containsKey(name) || entity is! File) entity.deleteSync();
  }
  for (final entry in inputs.entries) {
    final target = File(p.join(workspace.path, entry.key));
    final bytes = entry.value.readAsBytesSync();
    if (target.existsSync()) {
      final existing = target.readAsBytesSync();
      if (existing.length == bytes.length &&
          Iterable<int>.generate(bytes.length)
              .every((index) => existing[index] == bytes[index])) {
        continue;
      }
    }
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(bytes);
  }
  final directories =
      workspace
          .listSync(recursive: true, followLinks: false)
          .whereType<Directory>()
          .toList()
        ..sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final directory in directories) {
    if (directory.listSync().isEmpty) directory.deleteSync();
  }
}

/// 连续检查复用同一份源码镜像与 Cargo 缓存，进程退出或中断后由系统释放锁。
Future<T> withGenerationWorkspace<T>(
  Directory cache,
  FutureOr<T> Function(Directory workspace, Directory target) action,
) async {
  cache.createSync(recursive: true);
  final lock = File(p.join(cache.path, 'lock')).openSync(mode: FileMode.append);
  try {
    await lock.lock(FileLock.exclusive);
    return await action(
      Directory(p.join(cache.path, 'workspace')),
      Directory(p.join(cache.path, 'target')),
    );
  } finally {
    lock.closeSync();
  }
}
