import 'dart:io';

import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

import 'models/connection_transport.dart';

export 'models/connection_transport.dart';

ConnectionTransport connectionTransportForRecord(DeviceSnapshot record) =>
    record.transport == DeviceTransport.tcp && record.guid == null
    ? ConnectionTransport.tcp
    : ConnectionTransport.tls;

String? validateAddress(String? input) {
  final text = input?.trim() ?? '';
  if (text.isEmpty) return '请输入手机上显示的地址';
  if (text.contains(RegExp(r'\s|://|/'))) return '地址和端口请分开填写，地址无需带 http://';
  if (text.contains(':')) {
    final unwrapped = text.startsWith('[') && text.endsWith(']')
        ? text.substring(1, text.length - 1)
        : text;
    final zone = unwrapped.split('%');
    if (zone.length > 2 ||
        (zone.length == 2 && zone[1].isEmpty) ||
        InternetAddress.tryParse(zone[0])?.type != InternetAddressType.IPv6) {
      return '地址格式不对，请对照手机上显示的地址';
    }
    return null;
  }
  if (RegExp(r'^\d+(\.\d+){3}$').hasMatch(text) &&
      text.split('.').any((part) => int.parse(part) > 255)) {
    return '地址里的每组数字应在 0 到 255 之间';
  }
  if (text.length > 253 ||
      !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*$').hasMatch(text) ||
      text
          .split('.')
          .any(
            (label) =>
                label.isEmpty ||
                label.startsWith('-') ||
                label.endsWith('-') ||
                label.length > 63,
          )) {
    return '地址格式不对，请对照手机上显示的地址';
  }
  return null;
}

String? validatePort(String? input) {
  final text = input?.trim() ?? '';
  if (text.isEmpty) return '请输入端口号';
  final port = int.tryParse(text);
  return port == null || port < 1 || port > 65535 ? '端口范围 1–65535' : null;
}

String? responseDeviceId(Json? response, [String? fallback]) {
  final nested = response?['device'];
  final id =
      response?['deviceId'] ??
      response?['id'] ??
      (nested is Map<Object?, Object?> ? nested['id'] : null) ??
      fallback;
  return id is String && id.isNotEmpty ? id : null;
}
