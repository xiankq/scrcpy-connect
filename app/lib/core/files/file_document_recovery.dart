import 'dart:async';
import 'dart:math';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_document_scope.dart';

/// 恢复读取前撤销旧 isolate 的文档 worker；关闭失败仍保留精确 scope 供重试。
final class FileDocumentRecovery {
  FileDocumentRecovery({required this.files, required this.platform});

  final Future<LocalFiles> Function() files;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  platform;
  FileDocumentScope? _configuration;
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
      _configuration = await FileDocumentScope.fromEnvironment(environment);
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
