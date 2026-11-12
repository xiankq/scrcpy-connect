import 'package:flutter/services.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

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
  String? get usbOwnerLeaseId => ownerLeaseId;

  Future<Map<String, dynamic>> authorize(Map<String, dynamic> params) async {
    if (_disposed) {
      throw const RequestFailure('cancelled', 'USB 授权已停止。');
    }
    final owned = _usbParams(params);
    try {
      final permission = await _request('usb.authorize', owned);
      if (permission == null) {
        throw const RequestFailure('cancelled', '尚未允许 USB 访问。');
      }
      if (permission['ownerLeaseId'] != usbOwnerLeaseId) {
        throw const RequestFailure('usb_owner_mismatch', 'USB 授权回执不属于本次平台权限。');
      }
      // 成功回执可能晚于取消或 dispose；仍交回精确 lease，由 setup 排空后释放。
      return Map<String, dynamic>.from(permission);
    } on PlatformException catch (error) {
      throw RequestFailure(
        error.code,
        error.message ?? 'USB 访问未完成，请重新检查。',
        error.details,
      );
    }
  }

  Map<String, dynamic> _usbParams(Map<String, dynamic> params) {
    final owner = usbOwnerLeaseId;
    if (owner == null ||
        owner.length > 256 ||
        owner.trim().isEmpty ||
        owner.runes.any((code) => code < 32 || code >= 127 && code <= 159)) {
      throw const RequestFailure('usb_owner_unavailable', '尚未完成本机 USB 资源恢复。');
    }
    return {...params, 'ownerLeaseId': owner};
  }

  /// 精确清理不受页面或应用 dispose 阻断，失败保留调用方原 lease 的重试权。
  Future<void> cancel(Map<String, dynamic> params) async =>
      _cleanupUsb('usb.cancel', 'cancelled', params);
  Future<void> release(Map<String, dynamic> params) async =>
      _cleanupUsb('usb.release', 'released', params);

  Future<void> _cleanupUsb(
    String command,
    String confirmation,
    Map<String, dynamic> params,
  ) async {
    final owned = _usbParams(params);
    final response = await _request(command, owned);
    if (response == null ||
        response[confirmation] != true ||
        response['ownerLeaseId'] != usbOwnerLeaseId) {
      throw const RequestFailure(
        'usb_cleanup_unconfirmed',
        'USB 平台尚未确认原资源已回收，请保留原权限与标识重试。',
      );
    }
  }
}
