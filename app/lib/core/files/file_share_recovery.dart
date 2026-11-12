import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:adb/adb.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_share_owner.dart';

typedef SharePlatformRequest = Future<Map<String, dynamic>> Function(
  String command,
  Map<String, dynamic> params,
);

/// 接管顺序唯一为 SDK 排空、平台认领、读取分享持久记录。
/// 只保留尚未确认的候选；平台已提交但回执丢失时不能创建另一候选绕过确认。
final class FileShareRecovery {
  FileShareRecovery._(this.files, this.platform);
  final Future<LocalFiles> Function() files;
  final SharePlatformRequest platform;
  static FileShareRecovery? _pending;
  FileShareOwner? _candidate;
  String? _expectedLease;
  Future<LocalFileScope>? _opening;
  bool _drained = false;
  Future<FileShareOwner>? _running;

  static bool get pending => _pending != null;

  /// 即使 environment 已 ready，未确认的旧候选也必须先完成同一次确认。
  static Future<FileShareOwner> confirm({
    required Future<LocalFiles> Function() files,
    required SharePlatformRequest platform,
  }) async {
    final recovery = _pending ??= FileShareRecovery._(files, platform);
    final owner = await recovery._run();
    if (identical(_pending, recovery)) _pending = null;
    return owner;
  }

  Future<FileShareOwner> _run() =>
      _running ??= Future<FileShareOwner>.microtask(_recover).whenComplete(() {
        _running = null;
      });

  Future<Map<String, dynamic>> _request(
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
        'share_cleanup_unconfirmed',
        '分享资源接管尚未确认，请重试；不会继续读取或清理来源。',
      );
    }
  }

  Future<FileShareOwner> _recover() async {
    if (_candidate == null) {
      final environment = await _request(
        'sharing.platform.environment',
        const {},
      );
      final cache = environment['cacheDirectory'];
      final lease = environment['ownerLeaseId'];
      if (cache is! String ||
          !p.isAbsolute(cache) ||
          (lease != null && lease is! String)) {
        throw const RequestFailure('cache_unavailable', '系统未提供可信分享暂存位置。');
      }
      final root = await Directory(cache).resolveSymbolicLinks();
      final random = Random.secure();
      _candidate = FileShareOwner(
        cacheDirectory: root,
        leaseId: List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
      );
      _expectedLease = lease as String?;
    }
    final candidate = _candidate!;
    if (!_drained) {
      _opening ??=
          Future<LocalFileScope>.sync(() async {
            return candidate.openScope(await files());
          }).catchError((Object error, StackTrace stack) {
            _opening = null;
            Error.throwWithStackTrace(error, stack);
          });
      await (await _opening!).close();
      _opening = null;
      _drained = true;
    }
    final response = await _request('sharing.platform.claim', {
      'expectedOwnerLeaseId': _expectedLease,
      'ownerLeaseId': candidate.leaseId,
    });
    if (response['claimed'] != true ||
        response['ownerLeaseId'] != candidate.leaseId) {
      throw const RequestFailure('share_cleanup_unconfirmed', '分享平台尚未确认新代次。');
    }
    return candidate;
  }
}
