/// 系统文档操作的应用预算；本机文件能力只执行调用方明确给出的限制。
final class DocumentLimits {
  const DocumentLimits({
    this.maxBytes = 8 * 1024 * 1024 * 1024,
    this.maxEntries = 10000,
    this.maxDepth = 64,
    this.maxPathBytes = 16 * 1024 * 1024,
    this.timeout = const Duration(minutes: 10),
    this.reserveBytes = 32 * 1024 * 1024,
    this.maxErrors = 1000,
    this.maxSelected = 1000,
  }) : assert(maxBytes > 0),
       assert(maxEntries > 0),
       assert(maxDepth >= 0),
       assert(maxPathBytes > 0),
       assert(reserveBytes >= 0),
       assert(maxErrors > 0),
       assert(maxSelected > 0);

  final int maxBytes;
  final int maxEntries;
  final int maxDepth;
  final int maxPathBytes;
  final Duration timeout;
  final int reserveBytes;
  final int maxErrors;
  final int maxSelected;
}
