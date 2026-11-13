import 'package:scrcpy_connect/core/content/content_cache_failure.dart';

const defaultMediaCacheBudget = 512 * 1024 * 1024;

/// 已提交的缓存预算和原件保留记录；文件校验与提交由缓存所有者负责。
final class CacheConfiguration {
  CacheConfiguration({
    this.budgetBytes = defaultMediaCacheBudget,
    this.outgoingDirectory,
    Set<String> retainedShares = const {},
  }) : retainedShares = Set.unmodifiable(retainedShares);

  factory CacheConfiguration.fromJson(Object? value) {
    if (value is! Map ||
        value.keys.any(
          (key) => !const {
            'budgetBytes',
            'outgoingDirectory',
            'retainedShares',
          }.contains(key),
        ) ||
        value['budgetBytes'] is! int ||
        value['retainedShares'] is! List ||
        value['outgoingDirectory'] != null &&
            value['outgoingDirectory'] is! String) {
      throw const ContentCacheFailure('cache_storage_invalid', '媒体缓存所有权记录损坏。');
    }
    final retained = value['retainedShares'] as List;
    if (retained.any((path) => path is! String)) {
      throw const ContentCacheFailure('cache_storage_invalid', '媒体缓存保留路径无效。');
    }
    return CacheConfiguration(
      budgetBytes: value['budgetBytes'] as int,
      outgoingDirectory: value['outgoingDirectory'] as String?,
      retainedShares: retained.cast<String>().toSet(),
    );
  }

  final int budgetBytes;
  final String? outgoingDirectory;
  final Set<String> retainedShares;

  Map<String, Object?> toJson() => {
    'budgetBytes': budgetBytes,
    'outgoingDirectory': outgoingDirectory,
    'retainedShares': retainedShares.toList()..sort(),
  };
}
