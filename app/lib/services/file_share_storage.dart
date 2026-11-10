import 'package:scrcpy_connect/models/file_failure.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

typedef ShareStoreCommit = Future<void> Function(
  File temporary,
  File destination,
);

/// 承担分享账本的有界读取、原子文件替换与失败封存；不解释任务或发布状态。
/// 文件 flush 后 rename 提供本机原子可见性；Dart API 不承诺父目录断电持久化。
final class FileShareStorage {
  FileShareStorage(this.root, ShareStoreCommit? commit)
    : _commit =
          commit ??
          ((temporary, destination) async {
            await temporary.rename(destination.path);
          });
  final Directory root;
  final ShareStoreCommit _commit;
  bool _poisoned = false;
  void writable() {
    if (_poisoned) {
      throw const FileFailure(
        'share_storage_unknown',
        '分享存储提交未确认；请排空任务并重新打开，当前所有者禁止继续写入。',
      );
    }
  }

  Future<List<int>> read(File file, int maximum) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > maximum) {
      throw const FormatException('分享记录不是有界普通文件。');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maximum) throw const FormatException('分享记录超过上限。');
    return bytes;
  }

  Future<void> persist(Future<void> Function() action) async {
    writable();
    try {
      await action();
    } catch (error) {
      _poisoned = true;
      if (error is FileFailure) rethrow;
      throw const FileFailure(
        'share_storage_unknown',
        '分享存储提交或清理未确认；原始来源保留，禁止继续写入。',
      );
    }
  }

  Future<void> write(File destination, Map<String, dynamic> value) async {
    final parent = destination.parent;
    await assertRoot();
    if (p.basename(parent.path) == '.leases') {
      await checkLeaseDirectory();
    } else {
      await directory(p.basename(parent.path));
    }
    final bytes = utf8.encode(jsonEncode(value));
    final temporary = File(
      p.join(parent.path, '.$pid-${Random.secure().nextInt(0x7fffffff)}.tmp'),
    );
    try {
      await temporary.create(exclusive: true);
      final output = await temporary.open(mode: FileMode.writeOnly);
      try {
        await output.writeFrom(bytes);
        await output.flush();
      } finally {
        await output.close();
      }
      try {
        await _commit(temporary, destination);
      } catch (_) {
        // 回执丢失只在目标完整字节得到核验时视为已提交；读取失败仍为未知。
        final actual = await read(
          destination,
          max(bytes.length, 8 * 1024 * 1024),
        );
        if (actual.length != bytes.length ||
            !List.generate(
              bytes.length,
              (i) => actual[i] == bytes[i],
            ).every((same) => same)) {
          rethrow;
        }
      }
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        /* 不改变已经核验的提交事实。 */
      }
    }
  }

  Future<void> assertRoot() async {
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await root.resolveSymbolicLinks() != root.path) {
      _bad('分享根目录已被替换为链接或其他类型。');
    }
  }

  Future<void> checkLeaseDirectory() async {
    await assertRoot();
    if (await FileSystemEntity.type(
          p.join(root.path, '.leases'),
          followLinks: false,
        ) !=
        FileSystemEntityType.directory) {
      _bad('分享租约目录不能是链接。');
    }
  }

  Future<void> directory(String id) async {
    if (!_validId(id)) _bad('分享标识无效。');
    await assertRoot();
    if (await FileSystemEntity.type(
          p.join(root.path, id),
          followLinks: false,
        ) !=
        FileSystemEntityType.directory) {
      _bad('分享来源目录已被替换。');
    }
  }

  Future<void> removeChildren(String id, {required bool keepJournal}) async {
    await directory(id);
    await for (final entry in Directory(
      p.join(root.path, id),
    ).list(followLinks: false)) {
      if (keepJournal && p.basename(entry.path) == '.share') continue;
      // 链接仅删除链接自身，不递归进入指向的内容。
      await entry.delete(recursive: entry is Directory);
    }
  }
}

Never _bad(String message) =>
    throw FileFailure('share_source_invalid', message);
bool _validId(String id) =>
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(id);
