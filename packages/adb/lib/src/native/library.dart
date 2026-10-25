import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// 每个 isolate 各自持有，每个动态库独立登记；不能按库路径去重，路径可能有别名。
final _frbShutdownWatchers = <int, _FrbShutdownWatcher>{};

/// 保持指定 FRB 动态库的 isolate 关闭登记，直到当前 isolate 退出。
///
/// FRB 2.13 的 Dart 关闭观察者在多个入口之间只登记首个库，而原生计数由各库
/// 独立持有。补充登记确保任一子 isolate 退出时，不会提前关闭其他 isolate 仍在
/// 使用的回执通道。此方法保留 FRB 原有登记和最终关闭保护，不接管动态库卸载。
void retainFrbLibraryForIsolate(DynamicLibrary library) {
  // 工厂地址标识实际动态库；先去重再调用，避免无观察者承接的原生计数增长。
  final createCallback = library
      .lookup<NativeFunction<Pointer<NativeFinalizerFunction> Function()>>(
        'frb_create_shutdown_callback',
      );
  _frbShutdownWatchers.putIfAbsent(
    createCallback.address,
    () => _FrbShutdownWatcher(
      createCallback
          .asFunction<Pointer<NativeFinalizerFunction> Function()>()(),
    ),
  );
}

final class _FrbShutdownWatcher implements Finalizable {
  _FrbShutdownWatcher(Pointer<NativeFinalizerFunction> callback)
    : _finalizer = NativeFinalizer(callback) {
    _finalizer.attach(this, nullptr);
  }

  // 观察者与终结器共同存活；原生创建时增加的计数由 isolate 退出回调对应释放。
  final NativeFinalizer _finalizer;
}

/// 解析已由 NativeAssets 加载的锚点所在动态库路径。
///
/// 调用方应通过自己的 `@Native(assetId: ...)` 获取锚点地址。此方法只查询
/// 操作系统的库路径，不在进程全局符号表查找 FRB 函数，也不转移动态库所有权。
String nativeLibraryPathFromAddress(Pointer<NativeType> anchor) {
  if (anchor.address == 0) throw ArgumentError.value(anchor, 'anchor');
  if (Platform.isWindows) return _windowsLibraryPath(anchor);
  if (Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isMacOS ||
      Platform.isIOS) {
    final info = calloc<_DlInfo>();
    try {
      if (_dladdr(anchor.cast(), info) == 0 || info.ref.fileName == nullptr) {
        throw StateError('NativeAssets 锚点没有对应的动态库路径');
      }
      return info.ref.fileName.toDartString();
    } finally {
      calloc.free(info);
    }
  }
  throw UnsupportedError('Unsupported native library host');
}

final class _DlInfo extends Struct {
  external Pointer<Utf8> fileName;
  external Pointer<Void> baseAddress;
  external Pointer<Utf8> symbolName;
  external Pointer<Void> symbolAddress;
}

final _dladdr = DynamicLibrary.process()
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<_DlInfo>),
      int Function(Pointer<Void>, Pointer<_DlInfo>)
    >('dladdr');

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _getModuleHandle = _kernel32
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Utf16>, Pointer<Pointer<Void>>),
      int Function(int, Pointer<Utf16>, Pointer<Pointer<Void>>)
    >('GetModuleHandleExW');
final _getModuleFileName = _kernel32
    .lookupFunction<
      Uint32 Function(Pointer<Void>, Pointer<Utf16>, Uint32),
      int Function(Pointer<Void>, Pointer<Utf16>, int)
    >('GetModuleFileNameW');

String _windowsLibraryPath(Pointer<NativeType> anchor) {
  final module = calloc<Pointer<Void>>();
  const capacity = 32768;
  final path = calloc<Uint16>(capacity);
  try {
    // FROM_ADDRESS 和 UNCHANGED_REFCOUNT：按锚点定位模块，不增加或移交卸载责任。
    if (_getModuleHandle(0x4 | 0x2, anchor.cast(), module) == 0) {
      throw StateError('NativeAssets 锚点没有对应的 Windows 模块');
    }
    final length = _getModuleFileName(module.value, path.cast(), capacity);
    if (length == 0 || length >= capacity) {
      throw StateError('NativeAssets Windows 模块路径读取失败');
    }
    return path.cast<Utf16>().toDartString(length: length);
  } finally {
    calloc.free(path);
    calloc.free(module);
  }
}
