import 'package:adb/adb.dart' show AdbException;
import 'package:scrcpy_connect/core/devices/models/device_record.dart'
    show DeviceRecordsFailure;
import 'package:scrcpy_connect/core/errors/request_failure.dart'
    show RequestFailure;
import 'package:scrcpy_connect/core/identity/adb_identity_service.dart';

export 'package:scrcpy_connect/core/identity/models/authorization_identity.dart';

/// 应用允许修改全局主控身份；已配对设备的专属身份继续由连接尝试管理。
abstract interface class IdentityManagement {
  Future<AuthorizationIdentity> readGlobal();
  Future<AuthorizationIdentity> importGlobal(String privateKeyPem);
  Future<AuthorizationIdentity> resetGlobal();
}

/// 先排空使用全局身份的连接尝试，再持有重连暂停直到变更及状态核对结束。
final class IdentityManager implements IdentityManagement {
  IdentityManager({
    required this.keys,
    required this.prepareChange,
    required this.pauseReconnect,
    required this.publishDevices,
    required this.isDisposed,
  });

  final AdbIdentityService keys;
  final Future<void> Function() prepareChange;
  final Future<void> Function() Function() pauseReconnect;
  final void Function() publishDevices;
  final bool Function() isDisposed;

  void _requireActive() {
    if (isDisposed()) {
      throw const RequestFailure('disposed', '授权身份所有者已关闭。');
    }
  }

  @override
  Future<AuthorizationIdentity> readGlobal() async {
    _requireActive();
    return _withSdkFailures(keys.read);
  }

  @override
  Future<AuthorizationIdentity> importGlobal(String privateKeyPem) async {
    _requireActive();
    if (privateKeyPem.isEmpty || privateKeyPem.contains('\u0000')) {
      throw const RequestFailure('invalid_argument', '私钥文本无效。');
    }
    return _change(() => keys.importKey(privateKeyPem));
  }

  @override
  Future<AuthorizationIdentity> resetGlobal() => _change(keys.resetGlobal);

  Future<AuthorizationIdentity> _change(
    Future<AuthorizationIdentity> Function() work,
  ) async {
    _requireActive();
    await prepareChange();
    _requireActive();
    final resume = pauseReconnect();
    try {
      return await _withSdkFailures(work);
    } finally {
      try {
        publishDevices();
      } finally {
        await resume();
      }
    }
  }

  Future<AuthorizationIdentity> _withSdkFailures(
    Future<AuthorizationIdentity> Function() work,
  ) async {
    try {
      return await work();
    } on AdbException catch (error, stack) {
      Error.throwWithStackTrace(
        RequestFailure(error.code, error.message),
        stack,
      );
    } on DeviceRecordsFailure catch (error, stack) {
      Error.throwWithStackTrace(
        RequestFailure(error.code, error.message, error.details),
        stack,
      );
    }
  }
}
