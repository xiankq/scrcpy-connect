/// 分享入口的产品容量；复制、授权和平台句柄不属于此配置。
final class ShareLimits {
  const ShareLimits({
    this.pending = 8,
    this.batches = 64,
    this.leases = 128,
    this.sources = 32,
    this.fileBytes = 512 * 1024 * 1024,
    this.batchBytes = 1024 * 1024 * 1024,
    this.totalBytes = 2 * 1024 * 1024 * 1024,
    this.timeout = const Duration(seconds: 120),
    this.pendingExpiry = const Duration(days: 1),
    this.references = 1024,
    this.pathsPerReference = 2048,
    this.totalPaths = 8192,
    this.minimumFreeBytes = 32 * 1024 * 1024,
  });
  final int pending, batches, leases, sources;
  final int fileBytes, batchBytes, totalBytes;
  final int references, pathsPerReference, totalPaths, minimumFreeBytes;
  final Duration timeout, pendingExpiry;
}
