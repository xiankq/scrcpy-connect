import 'package:scrcpy/scrcpy.dart' show readNativeScrcpyLocalStorageFreeBytes;

/// 只读查询暂存所在存储的实际可用量，不申请文件复制作用域。
Future<int?> cacheStorageFreeBytes(String root) async {
  final value = await readNativeScrcpyLocalStorageFreeBytes(root);
  if (value < BigInt.zero || value > BigInt.from(0x7fffffffffffffff)) {
    return null;
  }
  return value.toInt();
}
