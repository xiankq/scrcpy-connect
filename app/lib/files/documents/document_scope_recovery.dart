import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';

/// 文档访问的本机边界；启动接管和用户操作必须使用同一资源名称与根集合。
final class DocumentScopeConfiguration {
  DocumentScopeConfiguration._(
    this.environment,
    this.cacheDirectory,
    this.roots,
  );

  final Map<String, dynamic> environment;
  final String cacheDirectory;
  final List<String> roots;

  String get key => p.join(p.normalize(cacheDirectory), 'documents');

  static Future<DocumentScopeConfiguration> fromEnvironment(
    Map<String, dynamic> environment,
  ) async {
    final cache = environment['cacheDirectory'];
    if (cache is! String || !p.isAbsolute(cache)) {
      throw const ApplicationCommandException(
        'cache_unavailable',
        '系统没有提供本机暂存位置。',
      );
    }
    final filtered = Map<String, dynamic>.from(environment);
    final screenshots = environment['screenshotsDirectory'];
    // 可选目录不存在时不创建，也不通过符号链接或上级根扩大访问范围。
    if (screenshots is! String ||
        !p.isAbsolute(screenshots) ||
        await FileSystemEntity.type(screenshots, followLinks: false) !=
            FileSystemEntityType.directory) {
      filtered.remove('screenshotsDirectory');
    }
    return DocumentScopeConfiguration._(
      Map.unmodifiable(filtered),
      cache,
      List.unmodifiable([
        cache,
        if (filtered['screenshotsDirectory'] case final String path) path,
      ]),
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
      throw const ApplicationCommandException(
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
        throw const ApplicationCommandException(
          'document_cleanup_unconfirmed',
          '文档平台代次无效。',
        );
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
      throw const ApplicationCommandException(
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
