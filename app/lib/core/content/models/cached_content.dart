import 'package:freezed_annotation/freezed_annotation.dart';

part 'cached_content.freezed.dart';

/// 交给消费者的本机内容及读保护；缓存校验、传输统计留在内容所有者。
@freezed
class CachedContent with _$CachedContent {
  const CachedContent({
    required this.path,
    this.leaseId,
    this.cacheHit = false,
    this.reason,
  });

  final String path;
  final String? leaseId;
  final bool cacheHit;
  final String? reason;
}
