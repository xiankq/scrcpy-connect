import 'package:freezed_annotation/freezed_annotation.dart';

part 'cache_status.freezed.dart';

/// 任务、保存记录和读租约提供的保护事实，不授予新的读取或导出权限。
@freezed
class CacheProtection with _$CacheProtection {
  const CacheProtection({
    required this.path,
    this.name,
    this.sourceLabel,
    this.sourcePath,
    this.transferId,
    this.reason,
    this.canExport = false,
  });

  final String path;
  final String? name;
  final String? sourceLabel;
  final String? sourcePath;
  final String? transferId;
  final String? reason;
  final bool canExport;
}

/// 缓存所有者按实际文件与重叠路径合并后的受保护内容。
@freezed
class ProtectedCacheItem with _$ProtectedCacheItem {
  const ProtectedCacheItem({
    required this.localPath,
    required this.name,
    required this.sourceLabel,
    required this.bytes,
    required this.reason,
    this.sourcePath,
    this.transferId,
    this.canExport = false,
    this.canShare = false,
    this.externalLifetimeUnknown = false,
  });

  final String localPath;
  final String name;
  final String sourceLabel;
  final String? sourcePath;
  final String? transferId;
  final int bytes;
  final String reason;
  final bool canExport;
  final bool canShare;
  final bool externalLifetimeUnknown;
}

@freezed
class CacheStatus with _$CacheStatus {
  CacheStatus({
    required this.budgetBytes,
    required this.usedBytes,
    required this.protectedBytes,
    required this.reclaimableBytes,
    required this.reservedBytes,
    required this.availableBytes,
    this.freeBytes,
    this.spaceVerified = true,
    List<ProtectedCacheItem> protectedItems = const [],
    this.retainedShareCount = 0,
    this.retentionReason,
  }) : protectedItems = List.unmodifiable(protectedItems);

  final int budgetBytes;
  final int usedBytes;
  final int protectedBytes;
  final int reclaimableBytes;
  final int reservedBytes;
  final int? freeBytes;
  final int availableBytes;
  final bool spaceVerified;
  final List<ProtectedCacheItem> protectedItems;
  final int retainedShareCount;
  final String? retentionReason;
}
