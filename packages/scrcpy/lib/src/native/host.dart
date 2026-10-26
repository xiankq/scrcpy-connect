import 'dart:typed_data';
import 'dart:io';
import 'dart:ffi';

import 'package:adb/adb.dart';
import 'package:adb/native_asset_library.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import '../session.dart';
import '../models.dart';
import 'adb_api.dart';
import 'local_files.dart';
import 'scrcpy_api.dart';
import 'call.dart';
import 'generated/frb_generated.dart';
import 'generated/third_party/interop_adb_api/api.dart' as adb_native;
import 'generated/third_party/interop_scrcpy_api/api.dart' as scrcpy_native;

@Native<Int32 Function()>(
  symbol: 'frb_get_rust_content_hash',
  assetId: 'package:scrcpy/src/native/generated/frb_generated.io.dart',
)
external int _nativeAssetAnchor();

Future<void>? _initializing;
String? _loadedLibraryPath;
const _adb = FrbNativeAdbApi();
const _scrcpy = FrbNativeScrcpyApi();

/// 初始化独立 scrcpy 动态库；调用方明确提供与目标版本匹配的服务器 JAR 字节。
Future<void> initializeNativeScrcpy({
  required Uint8List serverBytes,
  String? libraryPath,
}) async {
  await ensureScrcpyBindings(libraryPath: libraryPath);
  await nativeScrcpyCall(
    () => scrcpy_native.scrcpyInitializeSdk(serverBytes: serverBytes),
  );
}

/// 初始化同库通用捕获能力；不创建 ADB server、身份或连接。
Future<ScrcpyClient> createNativeScrcpy({
  required Uint8List serverBytes,
  String? libraryPath,
}) async {
  await initializeNativeScrcpy(
    serverBytes: serverBytes,
    libraryPath: libraryPath,
  );
  return const ScrcpyClient(_scrcpy, nativeOwner: _adb);
}

/// 同一动态库的绑定共享初始化；省略路径复用已选库，显式路径须匹配已选规范路径。
Future<void> ensureScrcpyBindings({String? libraryPath}) {
  final current = _initializing;
  if (current == null) {
    // 先登记再加载，确保同步 dlopen 失败不会重新缓存已经失败的 Future。
    return _initializing = Future<void>.microtask(
      () => _initialize(libraryPath),
    );
  }
  if (libraryPath == null) return current;
  return current.then((_) {
    final requested = _libraryPathIdentity(libraryPath);
    if (requested != _loadedLibraryPath) {
      throw const ScrcpyException('native_library_mismatch');
    }
  });
}

String _libraryPathIdentity(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    // Android 可直接加载 APK 内的库；这类加载器路径不是可查询的普通文件。
    return path;
  }
}

Future<void> _initialize(String? libraryPath) async {
  try {
    final path =
        libraryPath ??
        nativeLibraryPathFromAddress(
          Native.addressOf<NativeFunction<Int32 Function()>>(
            _nativeAssetAnchor,
          ),
        );
    final library = ExternalLibrary.open(path);
    retainFrbLibraryForIsolate(library.ffiDynamicLibrary);
    await ScrcpyRustLib.init(externalLibrary: library);
    _loadedLibraryPath = _libraryPathIdentity(path);
  } catch (_) {
    _initializing = null;
    _loadedLibraryPath = null;
    rethrow;
  }
}

/// 配套能力共用一个原生连接注册表；独立 adb 动态库的句柄不可传入本宿主。
final class ScrcpyNativeHost {
  ScrcpyNativeHost._(this._adbOwner);
  final AdbHost _adbOwner;
  AdbClient get adb => _adbOwner.client;

  /// 当前租约和服务器事实投影；恢复权限仍由同库原生登记核验。
  Map<String, Object?>? get nativeConfiguration =>
      _adbOwner.nativeConfiguration;
  final ScrcpyClient scrcpy = const ScrcpyClient(_scrcpy, nativeOwner: _adb);

  /// 先关闭捕获或取消请求，再释放此宿主持有的连接；不会关闭其他宿主的连接。
  Future<void> close() => _adbOwner.close();
}

Future<ScrcpyNativeHost> createNativeScrcpyHost({
  required Uint8List serverBytes,
  required String identityPath,
  Directory? dataDirectory,
  Directory? binaryDirectory,
  String? libraryPath,
}) async {
  await initializeNativeScrcpy(
    serverBytes: serverBytes,
    libraryPath: libraryPath,
  );
  await adb_native.adbInitializeIdentity(identityPath: identityPath);
  final owner = await AdbHost.prepare(
    dataDirectory: dataDirectory ?? File(identityPath).absolute.parent,
    binaryDirectory: binaryDirectory,
    identityPath: identityPath,
    bindings: _adb,
  );
  return ScrcpyNativeHost._(owner);
}

/// 取得此 scrcpy 动态库的配套 ADB 能力，供同库连接枚举与精确认领使用。
Future<NativeAdbApi> createNativeScrcpyAdbApi({String? libraryPath}) async {
  await ensureScrcpyBindings(libraryPath: libraryPath);
  return _adb;
}

/// 列举此 scrcpy 动态库真实持有的服务器；不创建服务器或准备身份。
Future<List<AdbServerInfo>> listNativeScrcpyServers({
  String? libraryPath,
}) async {
  final api = await createNativeScrcpyAdbApi(libraryPath: libraryPath);
  return (api as NativeAdbServerApi).listServers();
}

/// 认领同一动态库的旧租约；不按端点或 PID 推断进程所有权。
Future<ScrcpyNativeHost> restoreNativeScrcpyHost({
  required Uint8List serverBytes,
  required Directory dataDirectory,
  required String leaseId,
  Directory? binaryDirectory,
  String? libraryPath,
}) async {
  await initializeNativeScrcpy(
    serverBytes: serverBytes,
    libraryPath: libraryPath,
  );
  final owner = await AdbHost.restore(
    dataDirectory: dataDirectory,
    binaryDirectory: binaryDirectory,
    leaseId: leaseId,
    bindings: _adb,
  );
  return ScrcpyNativeHost._(owner);
}

/// 使用当前 scrcpy 动态库中的本机文件能力，不加载独立 ADB 动态库。
Future<LocalFiles> createNativeScrcpyLocalFiles({String? libraryPath}) async {
  await ensureScrcpyBindings(libraryPath: libraryPath);
  return LocalFiles(const FrbNativeLocalFiles());
}

/// 同库查询本机现存绝对目录的可用字节数；不初始化捕获或设备连接。
Future<BigInt> readNativeScrcpyLocalStorageFreeBytes(String path) async {
  try {
    await ensureScrcpyBindings();
    return await adb_native.adbLocalStorageFreeBytes(path: path);
  } on adb_native.LocalFileError catch (error) {
    throw LocalFileException(
      LocalFileErrorCode.values.byName(error.code.name),
      error.message,
    );
  } catch (error) {
    throw LocalFileException(LocalFileErrorCode.io, error.toString());
  }
}
