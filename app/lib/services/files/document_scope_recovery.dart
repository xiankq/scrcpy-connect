import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/models/application_request.dart';

/// 文档访问的本机边界；启动接管和用户操作必须使用同一资源名称与根集合。
final class DocumentScopeConfiguration {
  DocumentScopeConfiguration._(
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
  final List<(String, String)> _logicalRoots;

  /// 只替换平台授予的逻辑根；内部链接和路径穿越仍交给固定 scope 拒绝。
  /// 调用方保留原始业务路径，只把此结果交给本机文件能力。
  String pathForScope(String path) {
    if (!p.isAbsolute(path) || p.split(path).contains('..')) return path;
    for (final (logical, actual) in _logicalRoots) {
      if (p.equals(logical, path)) return actual;
      if (p.isWithin(logical, path)) {
        return p.join(actual, p.relative(path, from: logical));
      }
    }
    return path;
  }

  static Future<DocumentScopeConfiguration> fromEnvironment(
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
    final logicalRoots = <(String, String)>[
      (p.dirname(scopeKey), cacheRoot),
      if (filtered['_documentScreenshotsRoot'] case final String logical)
        (logical, filtered['screenshotsDirectory'] as String),
    ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
    return DocumentScopeConfiguration._(
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

/// 恢复读取前撤销旧 isolate 的文档 worker；关闭失败仍保留精确 scope 供重试。
final class DocumentScopeRecovery {
  DocumentScopeRecovery({required this.files, required this.platform});

  final Future<LocalFiles> Function() files;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  platform;
  DocumentScopeConfiguration? _configuration;
  String? _expectedLease;
  String? _candidate;
  Future<LocalFileScope>? _opening;
  bool _scopeDrained = false;
  Future<void>? _recovering;

  Future<void> recover() =>
      _recovering ??= Future<void>.microtask(_recover)
          .whenComplete(() => _recovering = null);

  Future<Map<String, dynamic>> _platform(
    String command,
    Map<String, dynamic> params,
  ) async {
    try {
      return await platform(
        command,
        params,
      ).timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw const RequestFailure(
        'document_cleanup_unconfirmed',
        '文档平台接管尚未确认，请重试恢复；不会继续读取缓存。',
      );
    }
  }

  Future<void> _recover() async {
    if (_configuration == null) {
      final environment = await _platform(
        'documents.platform.environment',
        const {},
      );
      final previous = environment['ownerLeaseId'];
      if (previous != null && previous is! String) {
        throw const RequestFailure('document_cleanup_unconfirmed', '文档平台代次无效。');
      }
      _configuration = await DocumentScopeConfiguration.fromEnvironment(
        environment,
      );
      _expectedLease = previous as String?;
      final random = Random.secure();
      _candidate = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
    }
    if (!_scopeDrained) {
      _opening ??=
          Future<LocalFileScope>.sync(() async {
            return _configuration!.open(await files());
          }).catchError((Object error, StackTrace stack) {
            _opening = null;
            Error.throwWithStackTrace(error, stack);
          });
      final scope = await _opening!;
      await scope.close();
      _opening = null;
      _scopeDrained = true;
    }
    // 原生复制件确认排空后，才能撤销旧平台 owner 并关闭其原始 PFD/选择器。
    final response = await _platform('documents.platform.claim', {
      'expectedOwnerLeaseId': _expectedLease,
      'ownerLeaseId': _candidate,
    });
    if (response['claimed'] != true || response['ownerLeaseId'] != _candidate) {
      throw const RequestFailure(
        'document_cleanup_unconfirmed',
        '文档平台尚未确认新代次。',
      );
    }
    _configuration = null;
    _expectedLease = null;
    _candidate = null;
    _scopeDrained = false;
  }
}
