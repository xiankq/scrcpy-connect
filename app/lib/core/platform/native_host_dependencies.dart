import 'package:scrcpy_connect/core/platform/bundled_server_files.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/platform/bundled_servers.dart';
import 'package:scrcpy_connect/core/platform/usb_recovery.dart';

/// 测试替换执行能力，不另造应用原生桥或第二套进程所有者。
class NativeHostDependencies {
  const NativeHostDependencies();
  bool get desktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  UsbRecovery? usbRecovery() => Platform.isAndroid ? UsbRecovery() : null;
  Future<NativeAdbApi> bindings() => createNativeScrcpyAdbApi();
  Future<ScrcpyClient> createScrcpy(Uint8List bytes) =>
      createNativeScrcpy(serverBytes: bytes);
  Future<BundledServerFiles> assets(Directory directory) =>
      BundledServers().prepare(directory);
  Future<AdbHost> prepareServer({
    required Directory directory,
    required String identityPath,
    required NativeAdbApi bindings,
    required AdbAdmissionScopeInfo admissionScope,
    Directory? binaryDirectory,
  }) => AdbHost.prepare(
    dataDirectory: directory,
    identityPath: identityPath,
    bindings: bindings,
    admissionScope: admissionScope,
    binaryDirectory: binaryDirectory,
  );
  Future<AdbHost> restoreServer({
    required Directory directory,
    required String leaseId,
    required NativeAdbApi bindings,
    required AdbAdmissionScopeInfo admissionScope,
    Directory? binaryDirectory,
  }) => AdbHost.restore(
    dataDirectory: directory,
    leaseId: leaseId,
    bindings: bindings,
    admissionScope: admissionScope,
    binaryDirectory: binaryDirectory,
  );
}
