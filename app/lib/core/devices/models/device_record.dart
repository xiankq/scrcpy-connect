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
  }) {
    recordString(id, 'id', 36);
    if (!validDeviceId(id)) {
      throw const DeviceRecordsFailure('invalid_device_id', '设备记录标识无效。');
    }
    final checkedName = validateDeviceName(name);
    final checkedAddress = validateDeviceAddress(
      address,
      allowEmpty: transport != DeviceTransport.tcp,
    );
    recordInteger(port, 'port', 65535);
    if (transport == DeviceTransport.tcp && port == 0) {
      throw const DeviceRecordsFailure('invalid_port', 'TCP 端口必须为 1 到 65535。');
    }
    recordString(status, 'status', 32);
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
      name: checkedName,
      address: checkedAddress,
      port: port,
      transport: transport,
      status: status,
      guid: _nullableText(guid, 'guid', 256),
      serial: _nullableText(serial, 'serial', 256),
      model: _nullableText(model, 'model', 256),
      androidVersion: _nullableText(androidVersion, 'androidVersion', 256),
      apiLevel: _nullableInteger(apiLevel, 'apiLevel', 0xffffffff),
      battery: _nullableInteger(battery, 'battery', 100),
      charging: charging,
      batteryUpdatedAt: _nullableInteger(
        batteryUpdatedAt,
        'batteryUpdatedAt',
        0x7fffffffffffffff,
      ),
      lastSeen: _nullableInteger(lastSeen, 'lastSeen', 0x7fffffffffffffff),
      reason: _nullableText(reason, 'reason', 4096),
      autoReconnect: autoReconnect,
      observationWanted: observationWanted,
    );
  }
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
    final transport = DeviceTransport.values
        .where((v) => v.name == map['transport'])
        .firstOrNull;
    if (transport == null) {
      throw const DeviceRecordsFailure('invalid_transport', '设备记录的连接方式无效。');
    }
    return DeviceRecord(
      id: recordString(map['id'], 'id', 36),
      name: validateDeviceName(map['name']),
      address: validateDeviceAddress(
        map['address'],
        allowEmpty: transport != DeviceTransport.tcp,
      ),
      port: recordInteger(map['port'], 'port', 65535),
      transport: transport,
      status: recordString(map['status'], 'status', 32),
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
  }) => DeviceRecord(
    id: id,
    name: name ?? this.name,
    address: address ?? this.address,
    port: port ?? this.port,
    transport: transport ?? this.transport,
    status: status ?? this.status,
    guid: identical(guid, _absent)
        ? this.guid
        : _nullableText(guid, 'guid', 256),
    serial: identical(serial, _absent)
        ? this.serial
        : _nullableText(serial, 'serial', 256),
    model: identical(model, _absent)
        ? this.model
        : _nullableText(model, 'model', 256),
    androidVersion: identical(androidVersion, _absent)
        ? this.androidVersion
        : _nullableText(androidVersion, 'androidVersion', 256),
    apiLevel: identical(apiLevel, _absent)
        ? this.apiLevel
        : _nullableInteger(apiLevel, 'apiLevel', 0xffffffff),
    battery: identical(battery, _absent)
        ? this.battery
        : _nullableInteger(battery, 'battery', 100),
    charging: identical(charging, _absent)
        ? this.charging
        : _nullableBoolean(charging, 'charging'),
    batteryUpdatedAt: identical(batteryUpdatedAt, _absent)
        ? this.batteryUpdatedAt
        : _nullableInteger(
            batteryUpdatedAt,
            'batteryUpdatedAt',
            0x7fffffffffffffff,
          ),
    lastSeen: identical(lastSeen, _absent)
        ? this.lastSeen
        : _nullableInteger(lastSeen, 'lastSeen', 0x7fffffffffffffff),
    reason: identical(reason, _absent)
        ? this.reason
        : _nullableText(reason, 'reason', 4096),
    autoReconnect: autoReconnect ?? this.autoReconnect,
    observationWanted: observationWanted ?? this.observationWanted,
  );
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

String? _nullableText(Object? value, String key, int limit) =>
    value == null ? null : recordString(value, key, limit);
int? _nullableInteger(Object? value, String key, int limit) =>
    value == null ? null : recordInteger(value, key, limit);
bool? _nullableBoolean(Object? value, String key) {
  if (value == null) return null;
  if (value is! bool) {
    throw DeviceRecordsFailure('invalid_data', '设备记录布尔字段无效：$key。');
  }
  return value;
}
