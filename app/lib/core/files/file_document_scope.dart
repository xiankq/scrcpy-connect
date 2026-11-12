import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/application/request_failure.dart';

/// 文档访问的本机边界；启动接管和用户操作必须使用同一资源名称与根集合。
final class FileDocumentScope {
  FileDocumentScope._(
    this.environment,
    this.cacheDirectory,
    this.roots,
    this.key,
    this._logicalRoots,
  );

  final Map<String, dynamic> environment;
  final String cacheDirectory;
  final List<String> roots;

  final String key;
  final List<({String logical, String actual})> _logicalRoots;

  /// 只替换平台授予的逻辑根；内部链接和路径穿越仍交给固定 scope 拒绝。
  /// 调用方保留原始业务路径，只把此结果交给本机文件能力。
  String pathForScope(String path) {
    if (!p.isAbsolute(path) || p.split(path).contains('..')) return path;
    for (final (:logical, :actual) in _logicalRoots) {
      if (p.equals(logical, path)) return actual;
      if (p.isWithin(logical, path)) {
        return p.join(actual, p.relative(path, from: logical));
      }
    }
    return path;
  }

  static Future<FileDocumentScope> fromEnvironment(
    Map<String, dynamic> environment,
  ) async {
    final cache = environment['cacheDirectory'];
    if (cache is! String || !p.isAbsolute(cache)) {
      throw const RequestFailure('cache_unavailable', '系统没有提供本机暂存位置。');
    }
    final filtered = Map<String, dynamic>.from(environment);
    // 只解析平台明确授予的根。账本返回实际路径，复制也必须使用同一根；
    // 不解析内部请求的链接，不授予别名与实际根的共同父目录。
    final cacheRoot =
        await FileSystemEntity.type(cache) == FileSystemEntityType.directory
        ? await Directory(cache).resolveSymbolicLinks()
        : cache;
    final scopeKey =
        environment['_documentScopeKey'] ??
        p.join(p.normalize(cache), 'documents');
    if (scopeKey is! String ||
        !p.isAbsolute(scopeKey) ||
        p.basename(scopeKey) != 'documents') {
      throw const RequestFailure('cache_unavailable', '文档资源名称无效。');
    }
    filtered['cacheDirectory'] = cacheRoot;
    // 平台适配与协调器都会核验环境。保留最初逻辑名称，避免第二次核验
    // canonical 环境时改变 key，使恢复无法排空前代 scope。
    filtered['_documentScopeKey'] = scopeKey;
    final screenshots = environment['screenshotsDirectory'];
    // 可选目录不存在时不创建，也不通过符号链接或上级根扩大访问范围。
    if (screenshots is! String ||
        !p.isAbsolute(screenshots) ||
        await FileSystemEntity.type(screenshots, followLinks: false) !=
            FileSystemEntityType.directory) {
      filtered.remove('screenshotsDirectory');
      filtered.remove('_documentScreenshotsRoot');
    } else {
      filtered['screenshotsDirectory'] = await Directory(screenshots)
          .resolveSymbolicLinks();
      final logicalScreenshots =
          environment['_documentScreenshotsRoot'] ?? screenshots;
      if (logicalScreenshots is! String || !p.isAbsolute(logicalScreenshots)) {
        throw const RequestFailure('cache_unavailable', '截图库位置无效。');
      }
      filtered['_documentScreenshotsRoot'] = logicalScreenshots;
    }
    final logicalRoots = <({String logical, String actual})>[
      (logical: p.dirname(scopeKey), actual: cacheRoot),
      if (filtered['_documentScreenshotsRoot'] case final String logical)
        (logical: logical, actual: filtered['screenshotsDirectory'] as String),
    ]..sort((a, b) => b.logical.length.compareTo(a.logical.length));
    return FileDocumentScope._(
      Map.unmodifiable(filtered),
      cacheRoot,
      List.unmodifiable([
        cacheRoot,
        if (filtered['screenshotsDirectory'] case final String path) path,
      ]),
      scopeKey,
      List.unmodifiable(logicalRoots),
    );
  }

  Future<LocalFileScope> open(LocalFiles files) => files.openScope(
    scopeKey: key,
    allowedRoots: [
      for (final root in roots) Uint8List.fromList(utf8.encode(root)),
    ],
  );
}
