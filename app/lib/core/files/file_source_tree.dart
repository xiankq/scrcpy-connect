import 'package:scrcpy_connect/core/files/file_failure.dart';

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 有界、无链接的暂存树核验。容量不明时拒绝新增，不猜测可删除内容。
Future<int> sourceTreeBytes(
  String path, {
  int maxEntries = 10001,
  int maxDepth = 65,
  int maxPathBytes = 16 * 1024 * 1024,
  int maxBytes = 8 * 1024 * 1024 * 1024,
}) async {
  var entries = 0, paths = 0, bytes = 0;
  Future<void> visit(String current, int depth) async {
    paths += utf8.encode(p.relative(current, from: path)).length;
    if (++entries > maxEntries || depth > maxDepth || paths > maxPathBytes) {
      throw const FileFailure('source_tree_limit', '暂存目录超过核验预算，已有来源保留。');
    }
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await for (final child in Directory(current).list(followLinks: false)) {
        await visit(child.path, depth + 1);
      }
    } else if (type == FileSystemEntityType.file) {
      bytes += (await File(current).stat()).size;
      if (bytes > maxBytes) {
        throw const FileFailure('source_byte_limit', '暂存已达到总容量，已有来源保留。');
      }
    } else {
      throw const FileFailure('source_changed', '暂存包含链接或无法核验的来源。');
    }
  }

  if (!p.isAbsolute(path)) {
    throw const FileFailure('invalid_path', '暂存来源必须为绝对路径。');
  }
  await visit(path, 0);
  return bytes;
}
