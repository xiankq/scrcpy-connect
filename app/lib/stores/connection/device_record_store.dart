import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:scrcpy_connect/models/device_record.dart';
export 'package:scrcpy_connect/models/device_record.dart'
    show DeviceRecord, DeviceTransport, DeviceRecordsFailure;

const _maximumBytes = 8 * 1024 * 1024;
const _maximumDevices = 256;
final _queues = <String, Future<void>>{};
final _random = Random.secure();
typedef DeviceIdFactory = String Function();
typedef DeviceRecordsCommit = Future<void> Function(
  File temporary,
  File destination,
);

final class DeviceRecordsSnapshot {
  DeviceRecordsSnapshot({
    required Iterable<DeviceRecord> devices,
    required this.identityFingerprint,
    required Map<String, String> deviceIdentityFingerprints,
    Map<String, Object?> legacySettings = const {},
  }) : devices = List.unmodifiable(devices),
       deviceIdentityFingerprints = Map.unmodifiable(
         deviceIdentityFingerprints,
       ),
       legacySettings = _freeze(legacySettings) as Map<String, Object?>;
  final List<DeviceRecord> devices;
  final String identityFingerprint;
  final Map<String, String> deviceIdentityFingerprints;

  /// 旧版偏好迁移的输入；设备操作保留它，不解释或写入新的产品偏好。
  final Map<String, Object?> legacySettings;
  DeviceRecord? find(String id) =>
      devices.where((device) => device.id == id).firstOrNull;
  Map<String, Object?> toJson() => {
    'version': 2,
    'identityFingerprint': identityFingerprint,
    'deviceIdentityFingerprints': deviceIdentityFingerprints,
    'devices': devices.map((record) => record.toJson()).toList(),
    if (legacySettings.isNotEmpty) 'settings': legacySettings,
  };
}

final class DeviceRecordsImport {
  DeviceRecordsImport(Iterable<DeviceRecord> devices)
    : devices = List.unmodifiable(devices);
  final List<DeviceRecord> devices;
  int get restored => devices.length;
  bool get authorizationRestored => false;
  Map<String, Object?> toJson() => {
    'restored': restored,
    'authorizationRestored': false,
  };
}

/// 本 isolate 的设备记录所有者；其他 isolate 向它发请求，不同时写入同一文件。
/// 同目录实例共用队列与建议锁，每次提交读取最新磁盘值；仅在原子替换成功后发布内存快照。
final class DeviceRecordStore {
  DeviceRecordStore._(this.directory, this._idFactory, this._commitFile);
  final Directory directory;
  final DeviceIdFactory _idFactory;
  final DeviceRecordsCommit _commitFile;
  late DeviceRecordsSnapshot _current;
  DeviceRecordsSnapshot get current => _current;
  File get file => File.fromUri(directory.uri.resolve('devices.json'));

  static Future<DeviceRecordStore> open({
    required Directory directory,
    String? identityFingerprint,
    DeviceIdFactory? idFactory,
    DeviceRecordsCommit? commitFile,
  }) async {
    if (identityFingerprint != null) _fingerprint(identityFingerprint);
    await directory.create(recursive: true);
    final owner = DeviceRecordStore._(
      Directory(await directory.resolveSymbolicLinks()),
      idFactory ?? _newId,
      commitFile ??
          (temporary, destination) async {
            await temporary.rename(destination.path);
          },
    );
    await owner._exclusive(() async {
      final saved = await owner._read();
      final original =
          saved?.snapshot ??
          DeviceRecordsSnapshot(
            devices: const [],
            identityFingerprint: identityFingerprint ?? '',
            deviceIdentityFingerprints: const {},
          );
      final fingerprint = identityFingerprint ?? original.identityFingerprint;
      final next = _reconcileIdentities(
        original,
        fingerprint,
        original.deviceIdentityFingerprints,
      );
      // 读取损坏或新格式会在此前失败，绝不覆盖原文件。
      if (saved == null ||
          saved.version != 2 ||
          fingerprint != original.identityFingerprint) {
        await owner._write(next);
      }
      owner._current = next;
    });
    return owner;
  }

  Future<DeviceRecordsSnapshot> reload() => _exclusive(() async {
    final saved = await _requiredRead();
    return _current = saved;
  });

  /// 应用已确认冷启动没有存活连接后调用；普通打开和热重附着不重置执行状态。
  Future<void> markConnectionsOffline() async {
    await _change(
      (saved) => _snapshot(
        saved,
        devices: saved.devices.map(
          (device) => device.status == 'unauthorized'
              ? device
              : device.copyWith(status: 'offline'),
        ),
      ),
    );
  }

  Future<DeviceRecord> add({
    required String address,
    required int port,
    DeviceTransport transport = DeviceTransport.tcp,
    String name = 'Android 设备',
    String? guid,
    String? serial,
    String? identityFingerprint,
  }) async {
    if (identityFingerprint != null) _fingerprint(identityFingerprint);
    DeviceRecord? added;
    await _change((saved) {
      final record = DeviceRecord(
        id: _allocateId(saved.devices.map((d) => d.id).toSet()),
        name: name,
        address: address,
        port: port,
        transport: transport,
        guid: guid,
        serial: serial,
      );
      added = record;
      return _snapshot(
        saved,
        devices: [...saved.devices, record],
        fingerprints: {
          ...saved.deviceIdentityFingerprints,
          record.id: ?identityFingerprint,
        },
      );
    });
    return added!;
  }

  /// 更新函数在队列内作用于最新记录，避免两个并发修改覆盖彼此字段。
  Future<DeviceRecord> update(
    String id,
    DeviceRecord Function(DeviceRecord current) change,
  ) async {
    DeviceRecord? updated;
    await _change((saved) {
      final original = _requireDevice(saved, id);
      final next = DeviceRecord.fromJson(change(original).toJson());
      if (next.id != id) {
        throw const DeviceRecordsFailure('invalid_device_id', '更新不能改变设备标识。');
      }
      updated = next;
      return _snapshot(
        saved,
        devices: saved.devices.map((record) => record.id == id ? next : record),
      );
    });
    return updated!;
  }

  Future<DeviceRecord> rename(String id, String name) =>
      update(id, (record) => record.copyWith(name: name));
  Future<DeviceRecord> setAutoReconnect(String id, bool enabled) =>
      update(id, (record) => record.copyWith(autoReconnect: enabled));
  Future<DeviceRecord> setObservationWanted(String id, bool wanted) =>
      update(id, (record) => record.copyWith(observationWanted: wanted));

  Future<void> remove(String id) async {
    await _change((saved) {
      _requireDevice(saved, id);
      final fingerprints = {...saved.deviceIdentityFingerprints}..remove(id);
      return _snapshot(
        saved,
        devices: saved.devices.where((record) => record.id != id),
        fingerprints: fingerprints,
      );
    });
  }

  /// 只保存 ADB 已给出的公开指纹，不接受或生成密钥材料。
  Future<void> bindIdentity(String id, String? fingerprint) async {
    if (fingerprint != null) _fingerprint(fingerprint);
    await _change((saved) {
      _requireDevice(saved, id);
      final fingerprints = {...saved.deviceIdentityFingerprints};
      if (fingerprint == null) {
        fingerprints.remove(id);
      } else {
        fingerprints[id] = fingerprint;
      }
      return _reconcileIdentities(
        saved,
        saved.identityFingerprint,
        fingerprints,
      );
    });
  }

  Future<void> setIdentityFingerprints({
    required String global,
    Map<String, String>? devices,
  }) async {
    _fingerprint(global);
    final fingerprints = devices == null
        ? null
        : Map<String, String>.of(devices);
    for (final value in fingerprints?.values ?? const <String>[]) {
      _fingerprint(value);
    }
    await _change(
      (saved) => _reconcileIdentities(
        saved,
        global,
        fingerprints ?? saved.deviceIdentityFingerprints,
      ),
    );
  }

  /// 导出不含记录 ID、重连意图、私钥或指纹绑定；settings 由 App 偏好所有者提供。
  Map<String, Object?> exportMetadata({
    Map<String, Object?> settings = const {},
  }) => {
    'metadata': {
      'format': 'scrcpy-connect-metadata',
      'version': 1,
      'devices': current.devices
          .map(
            (record) => {
              'name': record.name,
              'address': record.address,
              'port': record.port,
              'transport': record.transport.name,
              'guid': record.guid,
              'serial': record.serial,
              'model': record.model,
              'androidVersion': record.androidVersion,
              'apiLevel': record.apiLevel,
            },
          )
          .toList(),
      'settings': _copyJson(settings),
    },
  };

  /// 完整验证全部条目后，一次提交追加新记录；不合并端点、不修改原有信任或重复发送授权动作。
  Future<DeviceRecordsImport> importMetadata(Object? metadata) async {
    final document = recordObject(metadata);
    if (document['format'] != 'scrcpy-connect-metadata' ||
        document['version'] is! int ||
        document['version'] != 1) {
      throw const DeviceRecordsFailure('invalid_data', '设备记录格式或版本不受支持。');
    }
    final entries = document['devices'];
    if (entries is! List || entries.length > _maximumDevices) {
      throw const DeviceRecordsFailure('invalid_data', '设备列表无效或过长。');
    }
    // 临时标识仅用于完整校验，不消耗调用方的 ID 工厂，也不进入提交。
    final validated = <DeviceRecord>[
      for (final entry in entries)
        _importRecord(
          recordObject(entry),
          '00000000-0000-4000-8000-000000000000',
        ),
    ];
    final imported = <DeviceRecord>[];
    await _change((saved) {
      final ids = saved.devices.map((d) => d.id).toSet();
      for (final entry in validated) {
        final id = _allocateId(ids);
        ids.add(id);
        imported.add(DeviceRecord.fromJson({...entry.toJson(), 'id': id}));
      }
      return _snapshot(saved, devices: [...saved.devices, ...imported]);
    });
    return DeviceRecordsImport(imported);
  }

  String _allocateId(Set<String> existing) {
    final id = _idFactory();
    if (!validDeviceId(id) || existing.contains(id)) {
      throw const DeviceRecordsFailure(
        'invalid_device_id',
        '设备标识工厂返回了无效或重复标识。',
      );
    }
    return id;
  }

  Future<DeviceRecordsSnapshot> _change(
    DeviceRecordsSnapshot Function(DeviceRecordsSnapshot saved) change,
  ) => _exclusive(() async {
    final saved = await _requiredRead();
    final next = change(saved);
    _validateSnapshot(next);
    await _write(next);
    return _current = next;
  });
  Future<DeviceRecordsSnapshot> _requiredRead() async =>
      (await _read())?.snapshot ??
      (throw const DeviceRecordsFailure(
        'records_missing',
        '设备记录文件已消失，请核对本机存储。',
      ));
  Future<({DeviceRecordsSnapshot snapshot, int version})?> _read() async {
    try {
      if (await file.length() > _maximumBytes) {
        throw const DeviceRecordsFailure('records_too_large', '设备记录超过容量。');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > _maximumBytes) {
        throw const DeviceRecordsFailure('records_too_large', '设备记录超过容量。');
      }
      final document = recordObject(jsonDecode(utf8.decode(bytes)));
      final version = document['version'];
      if (version is int && version > 2) {
        throw const DeviceRecordsFailure('storage_version', '设备记录版本较新，请更新应用。');
      }
      if (version is! int || version != 1 && version != 2) {
        throw const DeviceRecordsFailure('records_corrupt', '设备记录版本无效，原文件已保留。');
      }
      final devices = document['devices'];
      if (devices is! List) {
        throw const DeviceRecordsFailure('records_corrupt', '设备列表损坏，原文件已保留。');
      }
      final fingerprint = document['identityFingerprint'];
      if (fingerprint is! String) {
        throw const DeviceRecordsFailure('records_corrupt', '设备身份元数据损坏。');
      }
      if (fingerprint.isNotEmpty) _fingerprint(fingerprint);
      final fingerprints = recordObject(
        document['deviceIdentityFingerprints'] ?? <String, Object?>{},
      ).map((key, value) => MapEntry(key, _fingerprint(value)));
      final settings = document['settings'] == null
          ? <String, Object?>{}
          : recordObject(document['settings']);
      final snapshot = DeviceRecordsSnapshot(
        devices: devices.map(DeviceRecord.fromJson),
        identityFingerprint: fingerprint,
        deviceIdentityFingerprints: fingerprints,
        legacySettings: settings,
      );
      _validateSnapshot(snapshot);
      return (snapshot: snapshot, version: version);
    } on PathNotFoundException {
      return null;
    } on FormatException {
      throw const DeviceRecordsFailure('records_corrupt', '设备记录损坏，原文件已保留。');
    }
  }

  Future<void> _write(DeviceRecordsSnapshot snapshot) async {
    _validateSnapshot(snapshot);
    final bytes = utf8.encode(jsonEncode(snapshot.toJson()));
    if (bytes.length > _maximumBytes) {
      throw const DeviceRecordsFailure('records_too_large', '设备记录超过容量。');
    }
    final temporary = File.fromUri(
      directory.uri.resolve('.devices-$pid-${_random.nextInt(0x7fffffff)}.tmp'),
    );
    try {
      final output = await temporary.open(mode: FileMode.writeOnly);
      try {
        await output.writeFrom(bytes);
        await output.flush();
      } finally {
        await output.close();
      }
      try {
        await _commitFile(temporary, file);
      } on FileSystemException {
        // 替换完成但回执丢失时核对字节；不能把已提交文件误报成未提交并保留旧内存。
        if (!await _matches(file, bytes)) rethrow;
      }
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        /* 清理失败不能改写提交结果。 */
      }
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final key = directory.path;
    final previous = _queues[key] ?? Future<void>.value();
    final result = previous.then((_) async {
      final lock = await File.fromUri(directory.uri.resolve('.devices.lock'))
          .open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.blockingExclusive);
        return await action();
      } finally {
        await lock.close();
      }
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_queues[key], tail)) _queues.remove(key);
      }),
    );
    return result;
  }
}

DeviceRecord _importRecord(Map<String, Object?> entry, String id) =>
    DeviceRecord(
      id: id,
      name: validateDeviceName(entry['name']),
      address: entry['address'] is String ? entry['address'] as String : '',
      port: recordInteger(entry['port'], 'port', 65535),
      transport:
          DeviceTransport.values
              .where((v) => v.name == entry['transport'])
              .firstOrNull ??
          (throw const DeviceRecordsFailure(
            'invalid_transport',
            '设备记录的连接方式无效。',
          )),
      status: 'unauthorized',
      reason: '此记录来自恢复，请在被控手机重新核验授权。',
    );
DeviceRecord _requireDevice(DeviceRecordsSnapshot snapshot, String id) =>
    snapshot.find(id) ??
    (throw const DeviceRecordsFailure('not_found', '这台设备的本机记录已不存在。'));
DeviceRecordsSnapshot _snapshot(
  DeviceRecordsSnapshot saved, {
  Iterable<DeviceRecord>? devices,
  String? identityFingerprint,
  Map<String, String>? fingerprints,
}) => DeviceRecordsSnapshot(
  devices: devices ?? saved.devices,
  identityFingerprint: identityFingerprint ?? saved.identityFingerprint,
  deviceIdentityFingerprints: fingerprints ?? saved.deviceIdentityFingerprints,
  legacySettings: saved.legacySettings,
);
DeviceRecordsSnapshot _reconcileIdentities(
  DeviceRecordsSnapshot saved,
  String global,
  Map<String, String> fingerprints,
) => _snapshot(
  saved,
  identityFingerprint: global,
  fingerprints: fingerprints,
  devices: saved.devices.map((device) {
    final old =
        saved.deviceIdentityFingerprints[device.id] ??
        saved.identityFingerprint;
    final next = fingerprints[device.id] ?? global;
    return old == next
        ? device
        : device.copyWith(
            status: 'unauthorized',
            autoReconnect: false,
            reason: '本机授权身份已改变，需要重新授权。',
          );
  }),
);
void _validateSnapshot(DeviceRecordsSnapshot snapshot) {
  if (snapshot.identityFingerprint.isNotEmpty) {
    _fingerprint(snapshot.identityFingerprint);
  }
  for (final fingerprint in snapshot.deviceIdentityFingerprints.values) {
    _fingerprint(fingerprint);
  }
  if (snapshot.devices.length > _maximumDevices) {
    throw const DeviceRecordsFailure('records_too_large', '设备记录数量超过容量。');
  }
  final ids = snapshot.devices.map((d) => d.id).toSet();
  if (ids.length != snapshot.devices.length ||
      snapshot.deviceIdentityFingerprints.keys.any(
        (key) => !ids.contains(key),
      )) {
    throw const DeviceRecordsFailure('records_corrupt', '设备标识重复或身份绑定指向未知记录。');
  }
  for (final device in snapshot.devices) {
    DeviceRecord.fromJson(device.toJson());
  }
}

String _fingerprint(Object? value) {
  if (value is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
    throw const DeviceRecordsFailure(
      'invalid_identity_fingerprint',
      '授权身份指纹无效。',
    );
  }
  return value;
}

String _newId() {
  final bytes = List.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Future<bool> _matches(File file, List<int> expected) async {
  try {
    final actual = await file.readAsBytes();
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
  } on FileSystemException {
    return false;
  }
}

Object? _copyJson(Object? value) => jsonDecode(jsonEncode(value));
Object? _freeze(Object? value) => switch (value) {
  Map() => Map<String, Object?>.unmodifiable(
    value.map((key, child) => MapEntry(key as String, _freeze(child))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
