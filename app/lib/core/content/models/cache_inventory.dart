import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/content/content_cache_failure.dart';

const maximumCacheBytes = 0x7fffffffffffffff;

typedef CacheFileUsage = ({String path, int bytes, DateTime modified});

/// 一次扫描得到的文件占用及仍由活动保护的路径，不持有文件句柄或租约。
final class CacheInventory {
  CacheInventory(
    Iterable<CacheFileUsage> files,
    Iterable<String> protectedPaths,
    this.reservedBytes,
  ) : files = List.unmodifiable(files),
      protectedPaths = Set.unmodifiable(protectedPaths);

  final List<CacheFileUsage> files;
  final Set<String> protectedPaths;
  final int reservedBytes;

  int get usedBytes =>
      files.fold(0, (sum, file) => addCacheBytes(sum, file.bytes));
  int get protectedBytes => files
      .where(
        (file) =>
            protectedPaths.any((path) => cacheContainsPath(path, file.path)),
      )
      .fold(0, (sum, file) => addCacheBytes(sum, file.bytes));
}

int addCacheBytes(int first, int second) {
  if (first > maximumCacheBytes - second) {
    throw const ContentCacheFailure('invalid_argument', '缓存字节数超过容量。');
  }
  return first + second;
}

bool cacheContainsPath(String parent, String child) =>
    p.equals(parent, child) || p.isWithin(parent, child);
