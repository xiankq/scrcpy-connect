import 'package:scrcpy_connect/services/app_controller.dart';

import 'dart:io';

enum ConnectionTransport { tls, tcp }

ConnectionTransport connectionTransportForRecord(Json record) =>
    record['transport'] == 'tcp' && record['guid'] == null
    ? ConnectionTransport.tcp
    : ConnectionTransport.tls;

String? validateAddress(String? input) {
  final text = input?.trim() ?? '';
  if (text.isEmpty) return '请输入被控手机的地址';
  if (text.contains(RegExp(r'\s|://|/'))) return '只填写 IP 地址或主机名，不含端口和协议';
  if (text.contains(':')) {
    final unwrapped = text.startsWith('[') && text.endsWith(']')
        ? text.substring(1, text.length - 1)
        : text;
    final zone = unwrapped.split('%');
    if (zone.length > 2 ||
        (zone.length == 2 && zone[1].isEmpty) ||
        InternetAddress.tryParse(zone[0])?.type != InternetAddressType.IPv6) {
      return '请输入有效的 IPv6 地址';
    }
    return null;
  }
  if (RegExp(r'^\d+(\.\d+){3}$').hasMatch(text) &&
      text.split('.').any((part) => int.parse(part) > 255)) {
    return 'IPv4 每段应为 0–255';
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
    return '请输入有效的 IP 地址或主机名';
  }
  return null;
}

String? validatePort(String? input) {
  final port = int.tryParse(input?.trim() ?? '');
  return port == null || port < 1 || port > 65535 ? '端口应为 1–65535 的整数' : null;
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
