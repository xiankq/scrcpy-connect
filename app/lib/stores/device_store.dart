import 'package:scrcpy_connect/models/device_records_snapshot.dart';
import 'package:scrcpy_connect/models/device_import_receipt.dart';
import 'package:scrcpy_connect/models/device_records_import.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:uuid/uuid.dart';
import 'package:scrcpy_connect/models/device_record.dart';
import 'package:scrcpy_connect/models/device_metadata.dart';

export 'package:scrcpy_connect/models/device_record.dart'
    show DeviceRecord, DeviceTransport, DeviceRecordsFailure;

const _maximumBytes = 8 * 1024 * 1024;
const _maximumDevices = 256;
const _maximumImports = 1024;
final _queues = <String, Future<void>>{};
final _random = Random.secure();
typedef DeviceIdFactory = String Function();
typedef DeviceRecordsCommit = Future<void> Function(
  File temporary,
  File destination,
);

/// 本 isolate 的设备记录所有者；其他 isolate 向它发请求，不同时写入同一文件。
/// 同目录实例共用队列与建议锁，每次提交读取最新磁盘值；仅在原子替换成功后发布内存快照。
final class DeviceStore {
  DeviceStore._(this.directory, this._idFactory, this._commitFile);
  final Directory directory;
  final DeviceIdFactory _idFactory;
  final DeviceRecordsCommit _commitFile;
  late DeviceRecordsSnapshot _current;
  DeviceRecordsSnapshot get current => _current;
  File get file => File.fromUri(directory.uri.resolve('devices.json'));

  static Future<DeviceStore> open({
    required Directory directory,
    String? identityFingerprint,
    DeviceIdFactory? idFactory,
    DeviceRecordsCommit? commitFile,
  }) async {
    if (identityFingerprint != null) _fingerprint(identityFingerprint);
    await directory.create(recursive: true);
    final owner = DeviceStore._(
      Directory(await directory.resolveSymbolicLinks()),
      idFactory ?? const Uuid().v4,
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
          saved.version != 3 ||
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

  /// 只读取同一记录账本；预览不分配 ID，也不保存任何导入意图。
  Future<Map<String, Object?>> previewMetadata(Object? input) async {
    final metadata = DeviceMetadata.parse(input);
    return _exclusive(() async {
      final saved = await _requiredRead();
      _current = saved;
      final receipt = saved.imports[metadata.fingerprint];
      if (receipt == null) _checkImportCapacity(saved, metadata.devices.length);
      return {
        'fingerprint': metadata.fingerprint,
        'newRecords': receipt == null ? metadata.devices.length : 0,
        'alreadyImported': receipt != null,
        if (receipt != null)
          'receipt': DeviceRecordsImport(
            metadata.fingerprint,
            receipt,
            alreadyImported: true,
          ).toJson(),
      };
    });
  }

  /// 设备与文件回执原子写入同一快照。任何重试先核对账本，不再分配 ID。
  Future<DeviceRecordsImport> importMetadata(
    Object? input, {
    String? expectedFingerprint,
    bool importGlobalPreferences = false,
  }) async {
    final metadata = DeviceMetadata.parse(input);
    if (expectedFingerprint != null &&
        expectedFingerprint != metadata.fingerprint) {
      throw const DeviceRecordsFailure(
        'invalid_import_preview',
        '文件已变化，请重新预览后导入。',
      );
    }
    return _exclusive(() async {
      final saved = await _requiredRead();
      final previous = saved.imports[metadata.fingerprint];
      if (previous != null) {
        _current = saved;
        return DeviceRecordsImport(
          metadata.fingerprint,
          previous,
          alreadyImported: true,
        );
      }
      _checkImportCapacity(saved, metadata.devices.length);
      final ids = saved.devices.map((d) => d.id).toSet();
      final imported = <DeviceRecord>[];
      for (final entry in metadata.devices) {
        final id = _allocateId(ids);
        ids.add(id);
        imported.add(DeviceRecord.fromJson({...entry.toJson(), 'id': id}));
      }
      final receipt = DeviceImportReceipt(
        deviceIds: imported.map((d) => d.id),
        importedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        importGlobalPreferences: importGlobalPreferences,
      );
      final next = _snapshot(
        saved,
        devices: [...saved.devices, ...imported],
        imports: {...saved.imports, metadata.fingerprint: receipt},
      );
      await _write(next);
      _current = next;
      return DeviceRecordsImport(metadata.fingerprint, receipt);
    });
  }

  void _checkImportCapacity(DeviceRecordsSnapshot saved, int count) {
    if (saved.devices.length + count > _maximumDevices) {
      throw const DeviceRecordsFailure(
        'records_too_large',
        '新增记录后会超过设备容量，请先整理本机记录。',
      );
    }
    // 回执不能静默淘汰，否则再次选择旧文件会追加相同记录。
    if (saved.imports.length >= _maximumImports) {
      throw const DeviceRecordsFailure(
        'import_history_full',
        '导入记录已达到本机容量，无法安全追加新文件。',
      );
    }
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
      if (version is int && version > 3) {
        throw const DeviceRecordsFailure('storage_version', '设备记录版本较新，请更新应用。');
      }
      if (version is! int || version != 1 && version != 2 && version != 3) {
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
      if (version == 3 && document['imports'] is! Map) {
        throw const DeviceRecordsFailure('records_corrupt', '导入账本缺失，原文件已保留。');
      }
      final settings = document['settings'] == null
          ? <String, Object?>{}
          : recordObject(document['settings']);
      final snapshot = DeviceRecordsSnapshot(
        devices: devices.map(DeviceRecord.fromJson),
        identityFingerprint: fingerprint,
        deviceIdentityFingerprints: fingerprints,
        legacySettings: settings,
        imports: recordObject(document['imports'] ?? <String, Object?>{}).map(
          (key, value) => MapEntry(key, DeviceImportReceipt.fromJson(value)),
        ),
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

DeviceRecord _requireDevice(DeviceRecordsSnapshot snapshot, String id) =>
    snapshot.find(id) ??
    (throw const DeviceRecordsFailure('not_found', '这台设备的本机记录已不存在。'));
DeviceRecordsSnapshot _snapshot(
  DeviceRecordsSnapshot saved, {
  Iterable<DeviceRecord>? devices,
  String? identityFingerprint,
  Map<String, String>? fingerprints,
  Map<String, DeviceImportReceipt>? imports,
}) => DeviceRecordsSnapshot(
  devices: devices ?? saved.devices,
  identityFingerprint: identityFingerprint ?? saved.identityFingerprint,
  deviceIdentityFingerprints: fingerprints ?? saved.deviceIdentityFingerprints,
  legacySettings: saved.legacySettings,
  imports: imports ?? saved.imports,
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
  if (snapshot.imports.length > _maximumImports ||
      snapshot.imports.keys.any(
        (key) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(key),
      )) {
    throw const DeviceRecordsFailure('records_corrupt', '导入账本无效，原文件已保留。');
  }
  for (final receipt in snapshot.imports.values) {
    DeviceImportReceipt.fromJson(receipt.toJson());
  }
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
