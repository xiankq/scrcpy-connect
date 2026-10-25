import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/models/application_command_exception.dart';

typedef SharePlatformRequest = Future<Map<String, dynamic>> Function(
  String command,
  Map<String, dynamic> params,
);

/// SDK 资源名称由本机暂存根确定；平台租约由平台登记确认，二者不能互相替代。
final class ShareOwner {
  const ShareOwner({required this.cacheDirectory, required this.leaseId});
  final String cacheDirectory, leaseId;
  String get scopeKey => p.join(cacheDirectory, 'incoming');

  Future<LocalFileScope> openScope(LocalFiles files) => files.openScope(
    scopeKey: scopeKey,
    allowedRoots: [Uint8List.fromList(utf8.encode(cacheDirectory))],
  );
}

/// 接管顺序唯一为 SDK 排空、平台认领、读取分享持久记录。
/// 只保留尚未确认的候选；平台已提交但回执丢失时不能创建另一候选绕过确认。
final class ShareScopeRecovery {
  ShareScopeRecovery._(this.files, this.platform);
  final Future<LocalFiles> Function() files;
  final SharePlatformRequest platform;
  static ShareScopeRecovery? _pending;
  ShareOwner? _candidate;
  String? _expectedLease;
  Future<LocalFileScope>? _opening;
  bool _drained = false;
  Future<ShareOwner>? _running;

  static bool get pending => _pending != null;

  /// 即使 environment 已 ready，未确认的旧候选也必须先完成同一次确认。
  static Future<ShareOwner> confirm({
    required Future<LocalFiles> Function() files,
    required SharePlatformRequest platform,
  }) async {
    final recovery = _pending ??= ShareScopeRecovery._(files, platform);
    final owner = await recovery._run();
    if (identical(_pending, recovery)) _pending = null;
    return owner;
  }

  Future<ShareOwner> _run() =>
      _running ??= Future<ShareOwner>.microtask(_recover).whenComplete(() {
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
      throw const ApplicationCommandException(
        'share_cleanup_unconfirmed',
        '分享资源接管尚未确认，请重试；不会继续读取或清理来源。',
      );
    }
  }

  Future<ShareOwner> _recover() async {
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
        throw const ApplicationCommandException(
          'cache_unavailable',
          '系统未提供可信分享暂存位置。',
        );
      }
      final root = await Directory(cache).resolveSymbolicLinks();
      final random = Random.secure();
      _candidate = ShareOwner(
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
      throw const ApplicationCommandException(
        'share_cleanup_unconfirmed',
        '分享平台尚未确认新代次。',
      );
    }
    return candidate;
  }
}
