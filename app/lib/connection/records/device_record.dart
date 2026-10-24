import 'dart:io';

/// 产品保存的连接方式；地址不是设备身份。
enum DeviceTransport { tcp, wireless, tls, usb }

final class DeviceRecordsFailure implements Exception {
  const DeviceRecordsFailure(
    this.code,
    this.message, [
    this.details = const {},
  ]);
  final String code;
  final String message;
  final Map<String, Object?> details;
  @override
  String toString() => '$code: $message';
}

const _absent = Object();

/// 产品设备记录，不包含 Client、原生句柄或私钥材料。
final class DeviceRecord {
  factory DeviceRecord({
    required String id,
    required String name,
    required String address,
    required int port,
    required DeviceTransport transport,
    String status = 'offline',
    String? guid,
    String? serial,
    String? model,
    String? androidVersion,
    int? apiLevel,
    int? battery,
    bool? charging,
    int? batteryUpdatedAt,
    int? lastSeen,
    String? reason,
    bool autoReconnect = false,
    bool observationWanted = true,
  }) => DeviceRecord.fromJson({
    'id': id,
    'name': name,
    'address': address,
    'port': port,
    'transport': transport.name,
    'status': status,
    'guid': guid,
    'serial': serial,
    'model': model,
    'androidVersion': androidVersion,
    'apiLevel': apiLevel,
    'battery': battery,
    'charging': charging,
    'batteryUpdatedAt': batteryUpdatedAt,
    'lastSeen': lastSeen,
    'reason': reason,
    'autoReconnect': autoReconnect,
    'observationWanted': observationWanted,
  });
  const DeviceRecord._({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.transport,
    required this.status,
    required this.guid,
    required this.serial,
    required this.model,
    required this.androidVersion,
    required this.apiLevel,
    required this.battery,
    required this.charging,
    required this.batteryUpdatedAt,
    required this.lastSeen,
    required this.reason,
    required this.autoReconnect,
    required this.observationWanted,
  });
  factory DeviceRecord.fromJson(Object? value) {
    final map = recordObject(value);
    final id = recordString(map['id'], 'id', 36);
    if (!validDeviceId(id)) {
      throw const DeviceRecordsFailure('invalid_device_id', '设备记录标识无效。');
    }
    final name = validateDeviceName(map['name']);
    final transport = DeviceTransport.values
        .where((v) => v.name == map['transport'])
        .firstOrNull;
    if (transport == null) {
      throw const DeviceRecordsFailure('invalid_transport', '设备记录的连接方式无效。');
    }
    final address = validateDeviceAddress(
      map['address'],
      allowEmpty: transport != DeviceTransport.tcp,
    );
    final port = recordInteger(map['port'], 'port', 65535);
    if (transport == DeviceTransport.tcp && port == 0) {
      throw const DeviceRecordsFailure('invalid_port', 'TCP 端口必须为 1 到 65535。');
    }
    final status = recordString(map['status'], 'status', 32);
    if (!const {
      'offline',
      'connecting',
      'connected',
      'unauthorized',
      'authorizing',
    }.contains(status)) {
      throw const DeviceRecordsFailure('invalid_device_state', '设备记录的状态无效。');
    }
    return DeviceRecord._(
      id: id,
      name: name,
      address: address,
      port: port,
      transport: transport,
      status: status,
      guid: _optionalText(map, 'guid', 256),
      serial: _optionalText(map, 'serial', 256),
      model: _optionalText(map, 'model', 256),
      androidVersion: _optionalText(map, 'androidVersion', 256),
      apiLevel: _optionalInteger(map, 'apiLevel', 0xffffffff),
      battery: _optionalInteger(map, 'battery', 100),
      charging: _optionalBoolean(map, 'charging'),
      batteryUpdatedAt: _optionalInteger(
        map,
        'batteryUpdatedAt',
        0x7fffffffffffffff,
      ),
      lastSeen: _optionalInteger(map, 'lastSeen', 0x7fffffffffffffff),
      reason: _optionalText(map, 'reason', 4096),
      autoReconnect: _boolean(map, 'autoReconnect', false),
      observationWanted: _boolean(map, 'observationWanted', true),
    );
  }
  final String id, name, address, status;
  final int port;
  final DeviceTransport transport;
  final String? guid, serial, model, androidVersion, reason;
  final int? apiLevel, battery, batteryUpdatedAt, lastSeen;
  final bool? charging;
  final bool autoReconnect, observationWanted;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'port': port,
    'guid': guid,
    'serial': serial,
    'transport': transport.name,
    'status': status,
    'model': model,
    'androidVersion': androidVersion,
    'apiLevel': apiLevel,
    'battery': battery,
    'charging': charging,
    'batteryUpdatedAt': batteryUpdatedAt,
    'lastSeen': lastSeen,
    'reason': reason,
    'autoReconnect': autoReconnect,
    'observationWanted': observationWanted,
  };

  DeviceRecord copyWith({
    String? name,
    String? address,
    int? port,
    DeviceTransport? transport,
    String? status,
    Object? guid = _absent,
    Object? serial = _absent,
    Object? model = _absent,
    Object? androidVersion = _absent,
    Object? apiLevel = _absent,
    Object? battery = _absent,
    Object? charging = _absent,
    Object? batteryUpdatedAt = _absent,
    Object? lastSeen = _absent,
    Object? reason = _absent,
    bool? autoReconnect,
    bool? observationWanted,
  }) => DeviceRecord.fromJson({
    ...toJson(),
    'name': ?name,
    'address': ?address,
    'port': ?port,
    if (transport != null) 'transport': transport.name,
    'status': ?status,
    if (!identical(guid, _absent)) 'guid': guid,
    if (!identical(serial, _absent)) 'serial': serial,
    if (!identical(model, _absent)) 'model': model,
    if (!identical(androidVersion, _absent)) 'androidVersion': androidVersion,
    if (!identical(apiLevel, _absent)) 'apiLevel': apiLevel,
    if (!identical(battery, _absent)) 'battery': battery,
    if (!identical(charging, _absent)) 'charging': charging,
    if (!identical(batteryUpdatedAt, _absent))
      'batteryUpdatedAt': batteryUpdatedAt,
    if (!identical(lastSeen, _absent)) 'lastSeen': lastSeen,
    if (!identical(reason, _absent)) 'reason': reason,
    'autoReconnect': ?autoReconnect,
    'observationWanted': ?observationWanted,
  });
}

bool validDeviceId(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(value);
bool _control(String value) =>
    value.runes.any((c) => c < 32 || c >= 127 && c <= 159);
String validateDeviceName(Object? value) {
  final name = recordString(value, 'name', 320).trim();
  if (name.isEmpty || name.runes.length > 80 || _control(name)) {
    throw const DeviceRecordsFailure('invalid_name', '设备名称需为 1 到 80 个可见字符。');
  }
  return name;
}

String validateDeviceAddress(Object? value, {bool allowEmpty = false}) {
  if (value is! String ||
      value.length > 253 ||
      _control(value) ||
      RegExp(r'\s|[/\\\[\]]').hasMatch(value)) {
    throw const DeviceRecordsFailure('invalid_address', '设备地址无效；端口须单独填写。');
  }
  if (value.isEmpty && !allowEmpty) {
    throw const DeviceRecordsFailure('invalid_address', '设备地址不能为空。');
  }
  if (value.contains(':')) {
    final zone = value.split('%');
    if (zone.length > 2 ||
        zone.length == 2 && zone[1].isEmpty ||
        InternetAddress.tryParse(zone.first)?.type !=
            InternetAddressType.IPv6) {
      throw const DeviceRecordsFailure('invalid_address', 'IPv6 地址无效。');
    }
  }
  return value;
}

Map<String, Object?> recordObject(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const DeviceRecordsFailure('invalid_data', '设备记录必须是对象。');
  }
  return Map<String, Object?>.from(value);
}

String recordString(Object? value, String key, int limit) {
  if (value is! String ||
      value.isEmpty ||
      value.length > limit ||
      value.contains('\u0000')) {
    throw DeviceRecordsFailure('invalid_data', '设备记录字段无效：$key。');
  }
  return value;
}

int recordInteger(Object? value, String key, int maximum) {
  if (value is! int || value < 0 || value > maximum) {
    throw DeviceRecordsFailure('invalid_data', '设备记录数字字段无效：$key。');
  }
  return value;
}

String? _optionalText(Map<String, Object?> value, String key, int limit) =>
    value[key] == null ? null : recordString(value[key], key, limit);
int? _optionalInteger(Map<String, Object?> value, String key, int limit) =>
    value[key] == null ? null : recordInteger(value[key], key, limit);
bool _boolean(Map<String, Object?> value, String key, bool fallback) {
  if (!value.containsKey(key)) return fallback;
  final result = value[key];
  if (result is! bool) {
    throw DeviceRecordsFailure('invalid_data', '设备记录布尔字段无效：$key。');
  }
  return result;
}

bool? _optionalBoolean(Map<String, Object?> value, String key) =>
    value[key] == null ? null : _boolean(value, key, false);
