import 'dart:convert';

import 'package:path/path.dart' as p;

import 'package:scrcpy_connect/files/execution/file_executor.dart';

/// 被控 Android 路径与单项名称的共同不变量。
abstract final class FilePaths {
  static String name(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\u0000')) {
      throw const FileFailure('invalid_name', '名称无效。');
    }
    return name;
  }

  static String remote(String path) {
    if (!path.startsWith('/') ||
        path.contains('\u0000') ||
        utf8.encode(path).length > 4096 ||
        path.split('/').contains('..')) {
      throw const FileFailure('invalid_path', '设备路径无效。');
    }
    return p.posix.normalize(path);
  }
}
