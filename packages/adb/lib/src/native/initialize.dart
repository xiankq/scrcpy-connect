import 'dart:ffi';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:meta/meta.dart';

import '../../native_asset_library.dart';
import '../api.dart';
import '../local_files.dart';
import 'frb_native_local_files.dart';
import 'frb_native_adb_api.dart';
import 'generated/frb_generated.dart';
import 'generated/third_party/interop_adb_api/api.dart' as native;

Future<void>? _initializing;
const _api = FrbNativeAdbApi();

@Native<Int32 Function()>(
  symbol: 'frb_get_rust_content_hash',
  assetId: 'package:adb/src/native/generated/frb_generated.io.dart',
)
external int _adbContentHash();

/// 初始化独立 ADB SDK 动态库；不会创建服务器、连接设备或修改授权身份。
@RecordUse()
Future<void> initializeNativeAdb() =>
    // 先登记 Future，再执行可能同步失败的路径解析和 dlopen，失败才能清掉同一次登记。
    _initializing ??= Future<void>.microtask(_initialize);

/// 原子创建或验证指定的持久身份；不会覆盖已有身份或创建任何设备连接。
Future<void> prepareAdbIdentity(String identityPath) async {
  await initializeNativeAdb();
  try {
    await native.adbInitializeIdentity(identityPath: identityPath);
  } catch (error) {
    throw AdbException('native_adb_identity', error.toString());
  }
}

Future<void> _initialize() async {
  try {
    final path = nativeLibraryPathFromAddress(
      Native.addressOf<NativeFunction<Int32 Function()>>(_adbContentHash),
    );
    final library = ExternalLibrary.open(path);
    retainFrbLibraryForIsolate(library.ffiDynamicLibrary);
    await AdbRustLib.init(externalLibrary: library);
  } catch (_) {
    _initializing = null;
    rethrow;
  }
}

/// 返回本包独立宿主的能力接口；产品宿主可以继续注入自己的实现。
Future<NativeAdbApi> createNativeAdbApi() async {
  await initializeNativeAdb();
  return _api;
}

/// 创建独立 ADB 动态库中的本机文件能力，不创建设备连接或服务器。
Future<LocalFiles> createNativeLocalFiles() async {
  await initializeNativeAdb();
  return LocalFiles(const FrbNativeLocalFiles());
}
