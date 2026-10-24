import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/connection/records/device_record_store.dart';

const firstId = '11111111-1111-4111-8111-111111111111';
const secondId = '22222222-2222-4222-8222-222222222222';
const thirdId = '33333333-3333-4333-8333-333333333333';
final firstFingerprint = 'a' * 64;
final secondFingerprint = 'b' * 64;

DeviceRecord device([String id = firstId]) => DeviceRecord(
  id: id,
  name: '测试手机',
  address: '192.0.2.1',
  port: 5555,
  transport: DeviceTransport.tcp,
);
Matcher failure(String code) =>
    isA<DeviceRecordsFailure>().having((e) => e.code, 'code', code);
Map<String, Object?> metadata(List<Object?> devices) => {
  'format': 'scrcpy-connect-metadata',
  'version': 1,
  'devices': devices,
};
Map<String, Object?> exportedDevice() => {
  'name': '恢复设备',
  'address': '192.0.2.1',
  'port': 5555,
  'transport': 'tcp',
  'id': firstId,
  'guid': 'not-trusted',
  'serial': 'not-trusted',
  'privateKeyPem': 'not-a-key',
  'identityFingerprint': secondFingerprint,
};

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('device-records-test-');
    file = File('${directory.path}/devices.json');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  Future<void> legacy({
    int version = 2,
    List<DeviceRecord>? devices,
    Map<String, Object?>? extra,
  }) async {
    await file.writeAsString(
      jsonEncode({
        'version': version,
        'identityFingerprint': firstFingerprint,
        'devices': (devices ?? [device()]).map((d) => d.toJson()).toList(),
        ...?extra,
      }),
      flush: true,
    );
  }

  test('v1 迁移保留设备身份与旧偏好，显式冷启动恢复才清除在线状态', () async {
    await legacy(
      version: 1,
      devices: [device().copyWith(status: 'connected', autoReconnect: true)],
      extra: {
        'settings': {
          'appearance': 'dark',
          'nested': {
            'items': [1, 2],
          },
        },
      },
    );
    final records = await DeviceRecordStore.open(
      directory: directory,
      identityFingerprint: firstFingerprint,
    );
    expect(records.current.devices.single.status, 'connected');
    await records.markConnectionsOffline();
    expect(records.current.devices.single.status, 'offline');
    expect(records.current.devices.single.autoReconnect, isTrue);
    expect(records.current.legacySettings['appearance'], 'dark');
    expect(
      () => (records.current.legacySettings['nested'] as Map)['items'] =
          <Object?>[],
      throwsUnsupportedError,
    );
    final stored = jsonDecode(await file.readAsString()) as Map;
    expect(stored['version'], 2);
    expect(stored['identityFingerprint'], firstFingerprint);
    expect(stored['settings'], {
      'appearance': 'dark',
      'nested': {
        'items': [1, 2],
      },
    });
  });

  test('全局身份变化仅撤销继承该身份的记录，不覆盖专用绑定', () async {
    await legacy(
      devices: [
        device().copyWith(autoReconnect: true),
        device(secondId).copyWith(autoReconnect: true),
      ],
      extra: {
        'deviceIdentityFingerprints': {secondId: firstFingerprint},
      },
    );
    final records = await DeviceRecordStore.open(
      directory: directory,
      identityFingerprint: secondFingerprint,
    );
    expect(records.current.find(firstId)!.status, 'unauthorized');
    expect(records.current.find(firstId)!.autoReconnect, isFalse);
    expect(records.current.find(secondId)!.status, 'offline');
    expect(records.current.find(secondId)!.autoReconnect, isTrue);
    expect(records.current.deviceIdentityFingerprints, {
      secondId: firstFingerprint,
    });
    await records.bindIdentity(secondId, secondFingerprint);
    expect(records.current.find(secondId)!.status, 'unauthorized');
    expect(records.current.find(secondId)!.autoReconnect, isFalse);
  });

  test('新设备 ID 由 App 注入，修改和遗忘同时维护身份元数据', () async {
    final records = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () => firstId,
    );
    final added = await records.add(
      address: '192.0.2.1',
      port: 5555,
      identityFingerprint: firstFingerprint,
    );
    expect(added.id, firstId);
    expect(added.observationWanted, isTrue);
    await records.rename(firstId, ' 新名称 ');
    await records.setAutoReconnect(firstId, true);
    await records.setObservationWanted(firstId, false);
    expect(records.current.find(firstId)!.name, '新名称');
    expect(records.current.find(firstId)!.autoReconnect, isTrue);
    expect(records.current.find(firstId)!.observationWanted, isFalse);
    await records.remove(firstId);
    expect(records.current.devices, isEmpty);
    expect(records.current.deviceIdentityFingerprints, isEmpty);
  });

  test('默认 ID 工厂产生不同的 UUID v4，不依赖原生分配', () async {
    final records = await DeviceRecordStore.open(directory: directory);
    final first = await records.add(address: '192.0.2.1', port: 5555);
    final second = await records.add(address: '192.0.2.2', port: 5555);
    expect(
      first.id,
      matches(
        RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ),
      ),
    );
    expect(second.id, isNot(first.id));
  });

  test('同目录两个实例并发修改读取最新文件，不丢失另一字段或新增设备', () async {
    final first = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () => firstId,
    );
    await first.add(address: '192.0.2.1', port: 5555);
    final second = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () => secondId,
    );
    await Future.wait([
      first.rename(firstId, '并发名称'),
      second.setObservationWanted(firstId, false),
      second.add(address: '192.0.2.2', port: 5555),
    ]);
    await first.reload();
    expect(first.current.devices.length, 2);
    expect(first.current.find(firstId)!.name, '并发名称');
    expect(first.current.find(firstId)!.observationWanted, isFalse);
  });

  test('普通打开第二个实例不将存活连接改为离线或改写记录', () async {
    final first = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () => firstId,
    );
    await first.add(address: '192.0.2.1', port: 5555);
    await first.update(
      firstId,
      (record) => record.copyWith(status: 'connected'),
    );
    final bytes = await file.readAsBytes();
    final second = await DeviceRecordStore.open(directory: directory);
    expect(second.current.find(firstId)!.status, 'connected');
    expect(first.current.find(firstId)!.status, 'connected');
    expect(await file.readAsBytes(), bytes);
  });

  test('并发打开不静默覆盖原实例已提交的连接阶段', () async {
    final first = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () => firstId,
    );
    await first.add(address: '192.0.2.1', port: 5555);
    await Future.wait<Object?>([
      first.update(firstId, (record) => record.copyWith(status: 'connecting')),
      DeviceRecordStore.open(directory: directory),
    ]);
    expect(first.current.find(firstId)!.status, 'connecting');
    await first.reload();
    expect(first.current.find(firstId)!.status, 'connecting');
  });

  test('显式冷启动恢复读取最新记录并保留未授权状态与设备意图', () async {
    await legacy(
      devices: [
        device().copyWith(status: 'connected', autoReconnect: true),
        device(secondId).copyWith(status: 'unauthorized', reason: '需要重新授权'),
      ],
    );
    final first = await DeviceRecordStore.open(directory: directory);
    final second = await DeviceRecordStore.open(directory: directory);
    await second.rename(firstId, '其他所有者刚修改的名称');
    await first.markConnectionsOffline();
    expect(first.current.find(firstId)!.status, 'offline');
    expect(first.current.find(firstId)!.autoReconnect, isTrue);
    expect(first.current.find(firstId)!.name, '其他所有者刚修改的名称');
    expect(first.current.find(secondId)!.status, 'unauthorized');
    expect(first.current.find(secondId)!.reason, '需要重新授权');
    final reopened = await DeviceRecordStore.open(directory: directory);
    expect(reopened.current.find(firstId)!.status, 'offline');
    expect(reopened.current.find(secondId)!.status, 'unauthorized');
  });

  test('替换前真实文件系统失败保留旧内存和旧文件，队列随后仍可提交', () async {
    var fail = false;
    final records = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () => firstId,
      commitFile: (temporary, destination) async {
        if (fail) {
          // 源文件真实不存在，确保失败发生在替换原文件之前。
          await File('${temporary.path}.missing').rename(destination.path);
        }
        await temporary.rename(destination.path);
      },
    );
    await records.add(address: '192.0.2.1', port: 5555);
    final bytes = await file.readAsBytes();
    final snapshot = records.current;
    fail = true;
    await expectLater(
      records.rename(firstId, '不会提交'),
      throwsA(isA<FileSystemException>()),
    );
    expect(identical(records.current, snapshot), isTrue);
    expect(await file.readAsBytes(), bytes);
    expect(
      await directory
          .list()
          .where((entry) => entry.path.endsWith('.tmp'))
          .toList(),
      isEmpty,
    );
    fail = false;
    await records.rename(firstId, '成功提交');
    expect(records.current.devices.single.name, '成功提交');
  });

  test('替换已完成后文件系统回执失败，通过目标核验发布同一提交', () async {
    var lostReceipt = false;
    final records = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () => firstId,
      commitFile: (temporary, destination) async {
        await temporary.rename(destination.path);
        if (lostReceipt) throw const FileSystemException('替换后的回执丢失');
      },
    );
    await records.add(address: '192.0.2.1', port: 5555);
    lostReceipt = true;
    await records.rename(firstId, '已落盘');
    expect(records.current.devices.single.name, '已落盘');
    expect(
      (jsonDecode(await file.readAsString()) as Map)['devices'][0]['name'],
      '已落盘',
    );
  });

  test('阻塞提交完成前不发布新快照，同时串行下一次变更', () async {
    final entered = Completer<void>(), release = Completer<void>();
    var hold = false;
    final records = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () => firstId,
      commitFile: (temporary, destination) async {
        if (hold) {
          entered.complete();
          await release.future;
          hold = false;
        }
        await temporary.rename(destination.path);
      },
    );
    await records.add(address: '192.0.2.1', port: 5555);
    hold = true;
    final rename = records.rename(firstId, '等待落盘');
    await entered.future;
    final change = records.setAutoReconnect(firstId, true);
    expect(records.current.devices.single.name, 'Android 设备');
    expect(
      (jsonDecode(await file.readAsString()) as Map)['devices'][0]['name'],
      'Android 设备',
    );
    release.complete();
    await Future.wait([rename, change]);
    expect(records.current.devices.single.name, '等待落盘');
    expect(records.current.devices.single.autoReconnect, isTrue);
  });

  test('损坏、较新版本、重复 ID 和悬空指纹绑定均拒绝且原字节不变', () async {
    final examples = <String>[
      '{broken',
      jsonEncode({'version': 3}),
      jsonEncode({
        'version': 2,
        'identityFingerprint': firstFingerprint,
        'devices': [device().toJson(), device().toJson()],
      }),
      jsonEncode({
        'version': 2,
        'identityFingerprint': firstFingerprint,
        'devices': [device().toJson()],
        'deviceIdentityFingerprints': {secondId: firstFingerprint},
      }),
    ];
    for (final source in examples) {
      await file.writeAsString(source, flush: true);
      await expectLater(
        DeviceRecordStore.open(directory: directory),
        throwsA(isA<DeviceRecordsFailure>()),
      );
      expect(await file.readAsString(), source);
    }
  });

  test('打开后文件损坏或消失不会用内存快照覆盖它', () async {
    await legacy();
    final records = await DeviceRecordStore.open(directory: directory);
    final current = records.current;
    await file.writeAsString('corrupt', flush: true);
    await expectLater(
      records.rename(firstId, '错误覆盖'),
      throwsA(isA<DeviceRecordsFailure>()),
    );
    expect(await file.readAsString(), 'corrupt');
    expect(identical(records.current, current), isTrue);
    await file.delete();
    await expectLater(
      records.rename(firstId, '错误重建'),
      throwsA(failure('records_missing')),
    );
    expect(await file.exists(), isFalse);
  });

  test('导入同端点创建新未授权记录，不修改原认证记录或恢复密钥', () async {
    await legacy(
      devices: [
        device().copyWith(
          guid: 'trusted-guid',
          serial: 'trusted-serial',
          autoReconnect: true,
        ),
      ],
      extra: {
        'deviceIdentityFingerprints': {firstId: firstFingerprint},
      },
    );
    final records = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () => secondId,
    );
    final original = records.current.devices.single.toJson();
    final result = await records.importMetadata(metadata([exportedDevice()]));
    expect(result.restored, 1);
    expect(result.authorizationRestored, isFalse);
    final restored = records.current.find(secondId)!;
    expect(restored.status, 'unauthorized');
    expect(restored.autoReconnect, isFalse);
    expect(restored.guid, isNull);
    expect(restored.serial, isNull);
    expect(records.current.find(firstId)!.toJson(), original);
    expect(records.current.deviceIdentityFingerprints, {
      firstId: firstFingerprint,
    });
    expect(await file.readAsString(), isNot(contains('not-a-key')));
    final reopened = await DeviceRecordStore.open(directory: directory);
    expect(reopened.current.find(secondId)!.status, 'unauthorized');
  });

  test('导入先完整校验所有条目，后续无效时不分配 ID、不提交部分记录', () async {
    var allocations = 0;
    final records = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () {
        allocations++;
        return secondId;
      },
    );
    final bytes = await file.readAsBytes();
    await expectLater(
      records.importMetadata(
        metadata([
          exportedDevice(),
          {...exportedDevice(), 'port': 0},
        ]),
      ),
      throwsA(isA<DeviceRecordsFailure>()),
    );
    expect(allocations, 0);
    expect(records.current.devices, isEmpty);
    expect(await file.readAsBytes(), bytes);
  });

  test('导入多个新 ID 冲突不提交，格式错误不改变已保存记录', () async {
    final records = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () => secondId,
    );
    final bytes = await file.readAsBytes();
    await expectLater(
      records.importMetadata(metadata([exportedDevice(), exportedDevice()])),
      throwsA(failure('invalid_device_id')),
    );
    await expectLater(
      records.importMetadata({
        'format': 'other',
        'version': 1,
        'devices': <Object?>[],
      }),
      throwsA(failure('invalid_data')),
    );
    expect(await file.readAsBytes(), bytes);
    expect(records.current.devices, isEmpty);
  });

  test('导出兼容 metadata v1，只带公开记录字段和调用方偏好', () async {
    await legacy(
      extra: {
        'deviceIdentityFingerprints': {firstId: firstFingerprint},
      },
    );
    final records = await DeviceRecordStore.open(directory: directory);
    final exported = records.exportMetadata(settings: {'appearance': 'dark'});
    final data = exported['metadata'] as Map;
    expect(data['format'], 'scrcpy-connect-metadata');
    expect(data['version'], 1);
    expect(data['settings'], {'appearance': 'dark'});
    final text = jsonEncode(exported);
    expect(text, isNot(contains(firstId)));
    expect(text, isNot(contains(firstFingerprint)));
    expect(text, isNot(contains('autoReconnect')));
    expect(text, isNot(contains('observationWanted')));
  });

  test('容量、版本类型和重复新 ID 失败不覆盖原文件', () async {
    final records = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () => firstId,
    );
    await records.add(address: '192.0.2.1', port: 5555);
    final bytes = await file.readAsBytes();
    await expectLater(
      records.add(address: '192.0.2.2', port: 5555),
      throwsA(failure('invalid_device_id')),
    );
    await expectLater(
      records.importMetadata(
        metadata(List.generate(257, (_) => exportedDevice())),
      ),
      throwsA(failure('invalid_data')),
    );
    await expectLater(
      records.importMetadata({
        'format': 'scrcpy-connect-metadata',
        'version': 1.0,
        'devices': <Object?>[],
      }),
      throwsA(failure('invalid_data')),
    );
    expect(await file.readAsBytes(), bytes);
    expect(records.current.devices.length, 1);
    final invalid = jsonEncode({
      ...jsonDecode(await file.readAsString()) as Map,
      'version': 2.0,
    });
    await file.writeAsString(invalid, flush: true);
    await expectLater(
      DeviceRecordStore.open(directory: directory),
      throwsA(failure('records_corrupt')),
    );
    expect(await file.readAsString(), invalid);
  });

  test('权威指纹快照不能留下未知设备绑定，验证失败不提交', () async {
    await legacy();
    final records = await DeviceRecordStore.open(directory: directory);
    final bytes = await file.readAsBytes();
    await expectLater(
      records.setIdentityFingerprints(
        global: secondFingerprint,
        devices: {secondId: firstFingerprint},
      ),
      throwsA(failure('records_corrupt')),
    );
    expect(records.current.identityFingerprint, firstFingerprint);
    expect(await file.readAsBytes(), bytes);
    await records.setIdentityFingerprints(global: secondFingerprint);
    expect(records.current.find(firstId)!.status, 'unauthorized');
    expect(records.current.identityFingerprint, secondFingerprint);
  });

  test('排队后调用方修改指纹参数不改变提交内容且重开仍有效', () async {
    await legacy();
    final records = await DeviceRecordStore.open(directory: directory);
    final supplied = {firstId: secondFingerprint};
    final saving = records.setIdentityFingerprints(
      global: firstFingerprint,
      devices: supplied,
    );
    supplied[firstId] = '无效指纹';
    await saving;
    final reopened = await DeviceRecordStore.open(directory: directory);
    expect(reopened.current.deviceIdentityFingerprints, {
      firstId: secondFingerprint,
    });
    expect(reopened.current.find(firstId)!.status, 'unauthorized');
    expect(reopened.current.find(firstId)!.autoReconnect, isFalse);
  });

  test('字段类型、名称控制字符、端口与 IPv6 精确校验', () {
    final source = device().toJson();
    for (final patch in <Map<String, Object?>>[
      {'name': '\u0001非法'},
      {'port': '5555'},
      {'port': 65536},
      {'address': 'host:5555'},
      {'address': 'bad/path'},
      {'autoReconnect': null},
      {'observationWanted': 'true'},
      {'battery': 101},
      {'transport': 'unknown'},
      {'status': 'invented'},
    ]) {
      expect(
        () => DeviceRecord.fromJson({...source, ...patch}),
        throwsA(isA<DeviceRecordsFailure>()),
      );
    }
    expect(
      device().copyWith(address: 'fe80::1%wlan0').address,
      'fe80::1%wlan0',
    );
    expect(
      device().copyWith(reason: '原因').copyWith(reason: null).reason,
      isNull,
    );
  });
}
