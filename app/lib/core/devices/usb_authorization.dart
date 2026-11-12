import 'package:flutter/services.dart';
import 'package:scrcpy_connect/core/devices/models/usb_authorization_request.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

export 'package:scrcpy_connect/core/devices/models/usb_authorization_request.dart';

/// 授权与清理都绑定宿主恢复确认后的精确 USB 租约。
final class UsbAuthorization {
  UsbAuthorization({
    required this.ownerLeaseId,
    required this._request,
    required this.isDisposed,
  });
  final String? ownerLeaseId;
  final Future<Json?> Function(String, Json) _request;
  final bool Function() isDisposed;
  bool get _disposed => isDisposed();

  Future<UsbAccess> authorize(UsbAuthorizationRequest request) async {
    if (_disposed) {
      throw const RequestFailure('cancelled', 'USB 授权已停止。');
    }
    final owned = _usbParams({
      'attemptId': request.attemptId,
      'deviceId': ?request.deviceId,
      'serial': ?request.serial,
      'usbDeviceId': ?request.usbDeviceId,
      if (request.connect) 'connect': true,
    });
    try {
      final permission = await _request('usb.authorize', owned);
      if (permission == null) {
        throw const RequestFailure('cancelled', '尚未允许 USB 访问。');
      }
      if (permission['ownerLeaseId'] != ownerLeaseId) {
        throw const RequestFailure('usb_owner_mismatch', 'USB 授权回执不属于本次平台权限。');
      }
      // 成功回执可能晚于取消或 dispose；仍交回精确 lease，由 setup 排空后释放。
      return UsbAccess._(this, request.attemptId, Map.unmodifiable(permission));
    } on PlatformException catch (error) {
      throw RequestFailure(
        error.code,
        error.message ?? 'USB 访问未完成，请重新检查。',
        error.details,
      );
    }
  }

  Map<String, dynamic> _usbParams(Map<String, dynamic> params) {
    final owner = ownerLeaseId;
    if (owner == null ||
        owner.length > 256 ||
        owner.trim().isEmpty ||
        owner.runes.any((code) => code < 32 || code >= 127 && code <= 159)) {
      throw const RequestFailure('usb_owner_unavailable', '尚未完成本机 USB 资源恢复。');
    }
    return {...params, 'ownerLeaseId': owner};
  }

  /// 精确清理不受页面或应用 dispose 阻断，失败保留调用方原 lease 的重试权。
  Future<void> cancel(String attemptId) async =>
      _cleanupUsb('usb.cancel', 'cancelled', {'attemptId': attemptId});
  Future<void> _release(String leaseId) async =>
      _cleanupUsb('usb.release', 'released', {'usbLeaseId': leaseId});

  Future<void> _cleanupUsb(
    String command,
    String confirmation,
    Map<String, dynamic> params,
  ) async {
    final owned = _usbParams(params);
    final response = await _request(command, owned);
    if (response == null ||
        response[confirmation] != true ||
        response['ownerLeaseId'] != ownerLeaseId) {
      throw const RequestFailure(
        'usb_cleanup_unconfirmed',
        'USB 平台尚未确认原资源已回收，请保留原权限与标识重试。',
      );
    }
  }
}

/// 借给原生 ADB 的平台描述符与精确回收权，交接后仍由原授权所有者确认释放。
/// 调用方先持有句柄，再读取字段；无效回执也不能丢掉已经交付的租约。
final class UsbAccess {
  UsbAccess._(this._owner, this._attemptId, this._receipt);

  final UsbAuthorization _owner;
  final String _attemptId;
  final Json _receipt;
  Future<void>? _closing;
  bool _closed = false;
  bool _retired = false;

  int get fd {
    if (_retired) {
      throw const RequestFailure('cancelled', 'USB 描述符已停止交付。');
    }
    final descriptor = _receipt['fd'];
    final lease = _receipt['usbLeaseId'];
    if (descriptor is! int ||
        descriptor < 0 ||
        lease is! String ||
        lease.isEmpty) {
      throw const RequestFailure('invalid_argument', 'USB 描述符与平台租约必须同时有效交付。');
    }
    return descriptor;
  }

  String? get serial {
    final value = _receipt['serial'];
    if (value != null &&
        (value is! String ||
            value.length > 256 ||
            value.contains(RegExp(r'[\x00-\x1f]')))) {
      throw const RequestFailure('invalid_argument', 'USB 候选序列号无效。');
    }
    return value as String?;
  }

  Future<void> close() {
    _retired = true;
    if (_closed) return Future.value();
    if (_closing case final pending?) return pending;
    final operation = () async {
      if (_receipt['usbLeaseId'] case final String lease
          when lease.isNotEmpty) {
        await _owner._release(lease);
      } else {
        await _owner.cancel(_attemptId);
      }
      _closed = true;
    }();
    return _closing = operation.whenComplete(() => _closing = null);
  }
}
