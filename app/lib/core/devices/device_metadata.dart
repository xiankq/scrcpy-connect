import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:scrcpy_connect/core/devices/device_record.dart';

/// 已校验的迁移文件；散列规范化的完整 JSON，空白与对象键顺序不改变导入身份。
final class DeviceMetadata {
  DeviceMetadata._(this.document, this.devices, this.fingerprint);
  final Map<String, Object?> document;
  final List<DeviceRecord> devices;
  final String fingerprint;
  factory DeviceMetadata.parse(Object? input) {
    final document = recordObject(input);
    if (document['format'] != 'scrcpy-connect-metadata' ||
        document['version'] is! int ||
        document['version'] != 1) {
      throw const DeviceRecordsFailure('invalid_data', '设备记录格式或版本不受支持。');
    }
    final entries = document['devices'];
    if (entries is! List || entries.length > 256) {
      throw const DeviceRecordsFailure('invalid_data', '设备列表无效或过长。');
    }
    final frozen = _canonical(document) as Map<String, Object?>;
    final bytes = utf8.encode(jsonEncode(frozen));
    if (bytes.length > 1024 * 1024) {
      throw const DeviceRecordsFailure('invalid_data', '设备记录文件超过 1 MB。');
    }
    return DeviceMetadata._(
      frozen,
      List.unmodifiable([
        for (final entry in frozen['devices']! as List)
          _record(recordObject(entry)),
      ]),
      sha256.convert(bytes).toString(),
    );
  }
}

// 导入的身份事实只约束下一次真实核验，不授予连接许可或恢复自动连接意图。
DeviceRecord _record(Map<String, Object?> entry) => DeviceRecord.fromJson({
  'id': '00000000-0000-4000-8000-000000000000',
  'name': entry['name'],
  'address': entry['address'],
  'port': entry['port'],
  'transport': entry['transport'],
  for (final field in ['guid', 'serial', 'model', 'androidVersion', 'apiLevel'])
    field: entry[field],
  'status': 'unauthorized',
  'reason': '此记录来自恢复，请在被控手机重新核验授权。',
});
Object? _canonical(Object? value) {
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw const DeviceRecordsFailure('invalid_data', '设备记录字段名称无效。');
    }
    final keys = value.keys.cast<String>().toList()..sort();
    return Map<String, Object?>.unmodifiable({
      for (final key in keys) key: _canonical(value[key]),
    });
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_canonical));
  if (value == null ||
      value is String ||
      value is bool ||
      value is num && value.isFinite) {
    return value;
  }
  throw const DeviceRecordsFailure('invalid_data', '设备记录内容无效。');
}
