import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_query.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/models/device_battery.dart';
import 'package:scrcpy_connect/core/devices/models/device_record.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 设备详情的只读业务查询。缓存只供离线展示，不证明连接或动态事实。
/// 一个请求始终绑定同一交付连接及其物理 connectionId，不随重连改查新目标。
final class DeviceDetailsReader implements DeviceInspection {
  DeviceDetailsReader({
    required this.records,
    required this.connectionForDevice,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final DeviceRecordStorage records;
  final DeviceConnection? Function(String) connectionForDevice;
  final DateTime Function() _now;

  @override
  Future<DeviceReading<DeviceDetails>> readDetails(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) => _query(
    deviceId,
    connectionId,
    cancellation,
    _data,
    offline: (record) => DeviceDetails(
      system: DeviceSystemInfo(
        model: record.model,
        androidVersion: record.androidVersion,
        apiLevel: record.apiLevel,
      ),
    ),
  );

  @override
  Future<DeviceReading<DeviceNetworkInfo>> readNetwork(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) => _query(
    deviceId,
    connectionId,
    cancellation,
    (scope, record, stop) async => DeviceNetworkInfo(
      addresses: _networkAddresses(await _read(scope, 'ip -o addr show', stop)),
      transport: record.transport,
      address: record.address,
      port: record.port,
    ),
  );

  @override
  Future<DeviceReading<DeviceScreenState>> readScreenState(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) => _query(
    deviceId,
    connectionId,
    cancellation,
    (scope, _, stop) async => _screenState(
      await _read(scope, 'dumpsys power; dumpsys window policy', stop),
    ),
  );

  @override
  Future<DeviceReading<String>> readForegroundApp(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) => _query(
    deviceId,
    connectionId,
    cancellation,
    (scope, _, stop) async => _foregroundPackage(
      await _read(scope, 'dumpsys activity activities', stop),
    ),
  );

  Future<DeviceReading<T>> _query<T>(
    String id,
    String? expected,
    AdbCancellation? cancellation,
    Future<T> Function(_FactScope, DeviceRecord, AdbCancellation?) read, {
    T Function(DeviceRecord)? offline,
  }) async {
    if (!validDeviceId(id)) {
      throw const RequestFailure('invalid_device_id', '设备记录标识无效。');
    }
    final record = records.current.find(id);
    if (record == null) {
      throw const RequestFailure('device_not_found', '设备记录已不存在。');
    }
    if (expected != null && (expected.isEmpty || expected.contains('\u0000'))) {
      throw const RequestFailure('invalid_connection_id', '设备连接标识无效。');
    }
    if (cancellation?.isCancelled == true) {
      throw const RequestFailure('cancelled', '本次设备数据读取已取消。');
    }
    final connection = connectionForDevice(id);
    if (connection == null) {
      if (expected != null) _stale();
      if (offline != null) {
        return DeviceReading(
          deviceId: id,
          stale: true,
          observedAt: record.lastSeen,
          value: offline(record),
        );
      }
      throw const RequestFailure('disconnected', '这台设备当前没有可用连接。');
    }
    try {
      final facts = await connection.client.services.connectionFacts(
        connection.device,
      );
      _assertCurrent(id, connection, cancellation);
      if (facts.closed || expected != null && expected != facts.connectionId) {
        _stale();
      }
      final connectionId = facts.connectionId;
      if (connectionId == null || connectionId.isEmpty) {
        throw const RequestFailure('query_unavailable', '无法核验当前设备连接。');
      }
      final scope = (id: id, connection: connection, idAtStart: connectionId);
      final result = await read(scope, record, cancellation);
      final latest = await connection.client.services.connectionFacts(
        connection.device,
      );
      _assertCurrent(id, connection, cancellation);
      if (latest.closed || latest.connectionId != scope.idAtStart) _stale();
      return DeviceReading(
        value: result,
        deviceId: id,
        connectionId: scope.idAtStart,
        observedAt: _now().millisecondsSinceEpoch ~/ 1000,
      );
    } on AdbException catch (error, stack) {
      Error.throwWithStackTrace(
        RequestFailure(error.code, error.message),
        stack,
      );
    }
  }

  void _assertCurrent(
    String id,
    DeviceConnection connection,
    AdbCancellation? cancellation,
  ) {
    cancellation?.check();
    if (!identical(connectionForDevice(id), connection) ||
        records.current.find(id) == null) {
      _stale();
    }
  }

  Future<String> _read(
    _FactScope scope,
    String command,
    AdbCancellation? cancellation,
  ) async {
    _assertCurrent(scope.id, scope.connection, cancellation);
    try {
      return await readDeviceText(
        scope.connection,
        command,
        cancellation: cancellation,
      );
    } finally {
      // 失败回执同样可能迟到；撤准入后不能以分组失败掩盖连接已替换。
      _assertCurrent(scope.id, scope.connection, cancellation);
    }
  }

  Future<DeviceDetails> _data(
    _FactScope scope,
    DeviceRecord record,
    AdbCancellation? cancellation,
  ) async {
    final failures = <DeviceDetailSection, DeviceReadFailure>{};
    Future<String> query(DeviceDetailSection key, String command) async {
      try {
        return await _read(scope, command, cancellation);
      } catch (error, stack) {
        final (code, message) = switch (error) {
          RequestFailure(:final code, :final message) => (code, message),
          AdbException(:final code, :final message) => (code, message),
          _ => Error.throwWithStackTrace(error, stack),
        };
        if (const {
          'cancelled',
          'stale_connection',
          'disposed',
        }.contains(code)) {
          rethrow;
        }
        failures[key] = DeviceReadFailure(code: code, message: message);
        return '';
      }
    }

    final properties = _properties(await query(.system, 'getprop'));
    final battery = DeviceBattery.fromDumpsys(
      await query(.battery, 'dumpsys battery'),
    );
    final display = await query(
      .display,
      'wm size; wm density; dumpsys display',
    );
    final power = await query(.power, 'dumpsys power; dumpsys window policy');
    final network = await query(.network, 'ip -o addr show');
    final memory = await query(
      .memory,
      'cat /proc/meminfo; cat /sys/devices/system/cpu/present',
    );
    final storage = await query(.storage, 'df -k /sdcard');
    final size = _dimensions(display);
    final disk = _storage(storage);
    return DeviceDetails(
      failures: failures,
      system: DeviceSystemInfo(
        model: properties['ro.product.model'],
        brand: properties['ro.product.brand'],
        product: properties['ro.product.name'],
        hardware: properties['ro.hardware'],
        androidVersion: properties['ro.build.version.release'],
        apiLevel: _positive(properties['ro.build.version.sdk'] ?? ''),
        securityPatch: properties['ro.build.version.security_patch'],
        build: properties['ro.build.display.id'],
        serial: properties['ro.serialno'],
        abi:
            properties['ro.product.cpu.abilist'] ??
            properties['ro.product.cpu.abi'],
      ),
      battery: battery,
      display: DeviceDisplayInfo(
        width: size?.width,
        height: size?.height,
        densityDpi: _density(display),
        refreshRate: _refreshRate(display),
        screen: _screenState(power),
      ),
      network: DeviceNetworkInfo(
        addresses: _networkAddresses(network),
        transport: record.transport,
        address: record.address,
        port: record.port,
      ),
      memory: (
        totalBytes: _memoryBytes(memory, 'MemTotal:'),
        availableBytes: _memoryBytes(memory, 'MemAvailable:'),
      ),
      storage: (
        totalBytes: disk?.totalBytes,
        availableBytes: disk?.availableBytes,
      ),
      cpuCores: _cpuCount(memory),
    );
  }
}

typedef _FactScope = ({
  String id,
  DeviceConnection connection,
  String idAtStart,
});

Never _stale() =>
    throw const RequestFailure('stale_connection', '连接已替换或关闭，请重新读取设备数据。');

List<String> _lines(String text) => const LineSplitter().convert(text);

List<DeviceNetworkAddress> _networkAddresses(String text) {
  final seen = <(String, String)>{};
  final result = <DeviceNetworkAddress>[];
  for (final line in _lines(text)) {
    final fields = line.trim().split(RegExp(r'\s+'));
    final index = fields.indexWhere(
      (field) => field == 'inet' || field == 'inet6',
    );
    if (index < 2 || index + 1 >= fields.length) continue;
    final interface = fields[1]
        .split('@')
        .first
        .replaceFirst(RegExp(r':$'), '');
    if (!RegExp(r'^[a-zA-Z0-9_.-]{1,64}$').hasMatch(interface)) continue;
    final ip = InternetAddress.tryParse(fields[index + 1].split('/').first);
    if (ip == null ||
        ip.isLoopback ||
        ip.isMulticast ||
        ip.rawAddress.every((b) => b == 0)) {
      continue;
    }
    final address = ip.type == InternetAddressType.IPv6 && ip.isLinkLocal
        ? '${ip.address}%$interface'
        : ip.address;
    if (seen.add((interface, address))) {
      result.add(DeviceNetworkAddress(interface: interface, address: address));
    }
  }
  return result;
}

bool? _boolean(String text, List<String> keys) {
  for (final line in _lines(text)) {
    for (final key in keys) {
      final match = RegExp('${RegExp.escape(key)}(true|false)(?=[\\s,}]|\$)')
          .firstMatch(line);
      if (match != null) return match[1] == 'true';
    }
  }
  return null;
}

DeviceScreenState _screenState(String text) {
  final wakefulness = RegExp(r'\bmWakefulness=(Awake|Dreaming|Asleep|Dozing)\b')
      .firstMatch(text)?[1];
  final on = switch (wakefulness) {
    'Awake' || 'Dreaming' => true,
    'Asleep' || 'Dozing' => false,
    _ => _boolean(text, ['mInteractive=', 'mScreenOnFully=']),
  };
  var locked = _boolean(text, [
    'mKeyguardShowing=',
    'mShowingLockscreen=',
    'isStatusBarKeyguard=',
  ]);
  if (locked == null) {
    var keyguard = false;
    for (final line in _lines(text)) {
      if (line.contains('KeyguardServiceDelegate') ||
          line.contains('KeyguardService:')) {
        keyguard = true;
      } else if (keyguard && line.trimLeft().startsWith('showing=')) {
        locked = _boolean(line.trimLeft(), ['showing=']);
        break;
      } else if (keyguard &&
          line.isNotEmpty &&
          !line.startsWith(RegExp(r'\s'))) {
        keyguard = false;
      }
    }
  }
  return DeviceScreenState(screenOn: on, locked: locked);
}

String _foregroundPackage(String text) {
  final packages = <String>{};
  int? display;
  for (final line in _lines(text)) {
    final header = RegExp(r'^\s*Display #(\d+):?').firstMatch(line);
    if (header != null) display = int.tryParse(header[1]!);
    if (display != null && display != 0) continue;
    if (!line.contains('mResumedActivity') &&
        !line.contains('topResumedActivity')) {
      continue;
    }
    for (final match in RegExp(
      r'(?:^|[\s{=])([a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)+)/[a-zA-Z0-9_.$]+',
    ).allMatches(line)) {
      packages.add(match[1]!);
    }
  }
  if (packages.length != 1) {
    throw const RequestFailure('foreground_unavailable', '无法确定当前手机画面中的应用。');
  }
  return packages.single;
}

Map<String, String> _properties(String text) => {
  for (final line in _lines(text))
    if (RegExp(r'^\[([^\]]+)\]: \[(.*)\]$').firstMatch(line) case final match?)
      if (match[2]!.isNotEmpty && match[2] != 'unknown' && match[2] != 'null')
        match[1]!: match[2]!,
};

({int width, int height})? _dimensions(String text) {
  for (final line in _lines(text).reversed) {
    final match = RegExp(r'^(?:Override|Physical) size:\s*(\d+)x(\d+)\s*$')
        .firstMatch(line.trim());
    if (match == null) continue;
    final w = _positive(match[1]!);
    final h = _positive(match[2]!);
    if (w != null && h != null) return (width: w, height: h);
  }
  return null;
}

int? _positive(String text) {
  final value = int.tryParse(text);
  return value != null && value > 0 && value <= 0xffffffff ? value : null;
}

int? _density(String text) {
  for (final line in _lines(text).reversed) {
    final match = RegExp(r'^(?:Override|Physical) density:\s*(\d+)\s*$')
        .firstMatch(line.trim());
    if (match != null) {
      final value = _positive(match[1]!);
      if (value != null) return value;
    }
  }
  return null;
}

double? _refreshRate(String text) {
  for (final line in _lines(text).reversed) {
    if (!line.contains('DisplayInfo{') ||
        !RegExp(r'\bdisplayId[ =]0,').hasMatch(line)) {
      continue;
    }
    for (final field in ['renderFrameRate ', 'refreshRate ', 'refreshRate=']) {
      final match = RegExp('${RegExp.escape(field)}([^\\s,}]+)')
          .firstMatch(line);
      final value = match == null ? null : double.tryParse(match[1]!);
      if (value != null && value.isFinite && value > 0) return value;
    }
  }
  return null;
}

int? _kib(String text) {
  final value = int.tryParse(text);
  return value != null && value >= 0 && value <= 0x7fffffffffffffff ~/ 1024
      ? value * 1024
      : null;
}

int? _memoryBytes(String text, String key) {
  for (final line in _lines(text)) {
    final match = RegExp('^${RegExp.escape(key)}\\s*(\\d+)\\s+kB\\s*\$')
        .firstMatch(line.trim());
    if (match != null) return _kib(match[1]!);
  }
  return null;
}

({int totalBytes, int availableBytes})? _storage(String text) {
  for (final line in _lines(text).reversed) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 6 ||
        !(parts.last.startsWith('/storage/') ||
            parts.last.startsWith('/mnt/') ||
            parts.last == '/sdcard')) {
      continue;
    }
    final total = _kib(parts[1]);
    final available = _kib(parts[3]);
    if (total != null && available != null && available <= total) {
      return (totalBytes: total, availableBytes: available);
    }
  }
  return null;
}

int? _cpuCount(String text) {
  // Linux cpulist 允许稀疏区间和单核心；去重后计数，限制异常范围的展开量。
  for (final line in _lines(text)) {
    if (!RegExp(r'^\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$').hasMatch(line.trim())) {
      continue;
    }
    final cpus = <int>{};
    for (final range in line.trim().split(',')) {
      final bounds = range.split('-');
      final first = int.tryParse(bounds.first);
      final last = int.tryParse(bounds.last);
      if (first == null || last == null || first > last || last > 65535) {
        return null;
      }
      cpus.addAll(Iterable.generate(last - first + 1, (i) => first + i));
    }
    return cpus.length;
  }
  return null;
}
