import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/stores/connection/identity_manager.dart';
import 'package:scrcpy_connect/stores/connection/device_record_store.dart';

void main() {
  late Directory root;
  late DeviceRecordStore records;
  late _Identities sdk;
  late IdentityManager owner;
  late List<(Set<String>, bool)> retired;
  Future<void> Function()? cleanup;
  var nextId = 0;
  Future<IdentityManager> open() => IdentityManager.open(
    directory: root,
    records: records,
    identities: sdk,
    invalidate: (ids, {required global}) {
      retired.add((ids, global));
      return cleanup?.call() ?? Future<void>.value();
    },
  );
  Future<String> add({String? fingerprint}) async => (await records.add(
    address: 'localhost',
    port: 5555,
    identityFingerprint: fingerprint,
  )).id;
  final interop = isA<ApplicationCommandException>();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('identity-manager-');
    nextId = 0;
    records = await DeviceRecordStore.open(
      directory: root,
      idFactory: () =>
          '00000000-0000-4000-8000-${(++nextId).toString().padLeft(12, '0')}',
    );
    sdk = _Identities();
    retired = [];
    cleanup = null;
    owner = await open();
    retired.clear();
  });
  tearDown(() async => root.delete(recursive: true));

  for (final customOnly in [false, true]) {
    test('全局文件改变且无继承记录时仍退休未绑定尝试，失败跨重开保留：customOnly=$customOnly', () async {
      String? custom;
      if (customOnly) {
        custom = await add();
        await owner.command('identity.device.import', {
          'deviceId': custom,
          'privateKeyPem': 'key-b',
        });
        await records.update(
          custom,
          (record) => record.copyWith(status: 'connected'),
        );
      }
      retired.clear();
      await File(p.join(root.path, 'host_identity.pem'))
          .writeAsString('key-c', flush: true);
      cleanup = () async =>
          throw StateError('global setup cleanup not confirmed');
      await expectLater(open(), throwsStateError);
      expect(retired.single.$1, isEmpty);
      expect(retired.single.$2, isTrue);
      expect(
        records.current.identityFingerprint,
        sdk.info('key-c').fingerprint,
      );
      if (custom != null) {
        expect(records.current.find(custom)!.status, 'connected');
      }
      cleanup = null;
      retired.clear();
      owner = await open();
      expect(retired.single.$1, isEmpty);
      expect(retired.single.$2, isTrue);
      expect(
        (await owner.selectForDevice()).fingerprint,
        sdk.info('key-c').fingerprint,
      );
    });
  }

  test('冷启动生成全局身份，热附着只核验且保留连接状态', () async {
    final id = await add();
    await records.update(
      id,
      (record) => record.copyWith(status: 'connected', autoReconnect: true),
    );
    final original = await File(p.join(root.path, 'host_identity.pem'))
        .readAsString();
    final reopened = await open();
    expect(
      await File(p.join(root.path, 'host_identity.pem')).readAsString(),
      original,
    );
    expect(
      (await reopened.command('identity.global.get', {}))['fingerprint'],
      sdk.info('key-a').fingerprint,
    );
    expect(records.current.find(id)!.status, 'connected');
    expect(retired, isEmpty);
  });

  test('无效导入和 UTF8 字节越界不改变磁盘或连接', () async {
    final id = await add();
    final bytes = await File(p.join(root.path, 'host_identity.pem'))
        .readAsBytes();
    await expectLater(
      owner.command('identity.global.import', {'privateKeyPem': 'invalid'}),
      throwsA(interop),
    );
    await expectLater(
      owner.command('identity.global.import', {
        'privateKeyPem': List.filled(12000, '密').join(),
      }),
      throwsA(interop),
    );
    expect(
      await File(p.join(root.path, 'host_identity.pem')).readAsBytes(),
      bytes,
    );
    expect(records.current.find(id)!.status, 'offline');
    expect(retired, isEmpty);
  });

  test('同钥导入仍撤销旧代次，专属设备及专属候选不受全局重置影响', () async {
    final global = await add();
    final custom = await add();
    await owner.command('identity.device.import', {
      'deviceId': custom,
      'privateKeyPem': 'key-b',
    });
    final oldGlobal = await owner.selectForDevice(global);
    final oldCustom = await owner.selectForDevice(custom);
    final candidate = await owner.prepareSetup({
      'identity': {'scope': 'device', 'privateKeyPem': 'key-b'},
    });
    retired.clear();
    await owner.command('identity.global.import', {'privateKeyPem': 'key-a'});
    expect(retired.single.$1, {global});
    expect(retired.single.$2, isTrue);
    await expectLater(owner.validateSelection(oldGlobal), throwsA(interop));
    await owner.validateSelection(oldCustom);
    expect(await File(candidate.selection.path).readAsString(), 'key-b');
    expect(records.current.find(global)!.status, 'unauthorized');
    await candidate.dispose();
  });

  test('重置显式生成新候选再 CAS，候选清理且重开读取新身份', () async {
    await add();
    final old = await owner.selectForDevice();
    await owner.command('identity.global.reset', {});
    final reopened = await open();
    expect(
      (await reopened.selectForDevice()).fingerprint,
      isNot(old.fingerprint),
    );
    expect(
      await Directory(p.join(root.path, 'identities')).list().toList(),
      isEmpty,
    );
    expect(sdk.candidatePrepares, 1);
  });

  test('缺失专属密钥不生成也不回退，显式 useGlobal 后才可选择', () async {
    final id = await add(fingerprint: sdk.info('key-b').fingerprint);
    owner = await open();
    expect(records.current.find(id)!.status, 'unauthorized');
    await expectLater(
      owner.selectForDevice(id),
      throwsA(interop.having((e) => e.code, 'code', 'identity_unavailable')),
    );
    expect(
      await File(p.join(root.path, 'identities', '$id.pem')).exists(),
      isFalse,
    );
    await owner.command('identity.device.useGlobal', {'deviceId': id});
    expect((await owner.selectForDevice(id)).scope, 'global');
  });

  test('旧私钥映射仅迁移已有记录，缺失元数据也按真实身份恢复', () async {
    final id = await add();
    final legacy = File(p.join(root.path, 'device_identities.json'));
    await legacy.writeAsString(jsonEncode({id: 'key-b', 'orphan': 'invalid'}));
    owner = await open();
    expect((await owner.selectForDevice(id)).scope, 'device');
    expect(records.current.find(id)!.status, 'unauthorized');
    expect(await legacy.exists(), isFalse);
    expect(
      await File(p.join(root.path, 'identities', 'orphan.pem')).exists(),
      isFalse,
    );
    await owner.command('identity.device.useGlobal', {'deviceId': id});
    owner = await open();
    expect((await owner.selectForDevice(id)).scope, 'global');
    expect(jsonEncode(records.current.toJson()), isNot(contains('key-b')));
  });

  test('全局 setup 迟到回执失效，专属候选先绑定记录再放行', () async {
    final global = await owner.prepareSetup({});
    final custom = await owner.prepareSetup({
      'identity': {'scope': 'device', 'privateKeyPem': 'key-b'},
    });
    final candidatePath = custom.selection.path;
    await owner.command('identity.global.reset', {});
    final globalId = await add();
    await expectLater(global.bindNew(globalId), throwsA(interop));
    final id = await add();
    await custom.bindNew(id);
    expect(
      (await owner.selectForDevice(id)).fingerprint,
      sdk.info('key-b').fingerprint,
    );
    await custom.dispose();
    expect(await File(candidatePath).exists(), isFalse);
    expect(await File(custom.selection.path).exists(), isTrue);
    await owner.validateSelection(custom.selection, deviceId: id);
    owner = await open();
    expect((await owner.selectForDevice(id)).scope, 'device');
    await expectLater(
      owner.prepareSetup({
        'identity': {'scope': 'global'},
      }, deviceId: id),
      throwsA(interop),
    );
  });

  test('旧身份 JSON 损坏或在后一个有效记录中含无效私钥时不写部分迁移', () async {
    final first = await add();
    final second = await add();
    final legacy = File(p.join(root.path, 'device_identities.json'));
    for (final source in [
      '{broken',
      jsonEncode({first: 'key-b', second: 'invalid'}),
    ]) {
      await legacy.writeAsString(source, flush: true);
      await expectLater(open(), throwsA(anything));
      expect(await legacy.readAsString(), source);
      expect(
        await File(p.join(root.path, 'identities', '$first.pem')).exists(),
        isFalse,
      );
      expect(records.current.deviceIdentityFingerprints, isEmpty);
    }
  });

  test('旧公开指纹落后于旧私钥时按真实材料恢复，新的全局 setup 使用全局代次', () async {
    final id = await add(fingerprint: sdk.info('key-c').fingerprint);
    await File(p.join(root.path, 'device_identities.json'))
        .writeAsString(jsonEncode({id: 'key-b'}));
    owner = await open();
    expect(
      (await owner.selectForDevice(id)).fingerprint,
      sdk.info('key-b').fingerprint,
    );
    expect(records.current.find(id)!.status, 'unauthorized');
    await owner.command('identity.global.reset', {});
    final attempt = await owner.prepareSetup({});
    final newId = await add();
    await attempt.bindNew(newId);
    await owner.validateSelection(attempt.selection, deviceId: newId);
    await attempt.dispose();
  });

  test('并发变更串行等待资源回收，失败不阻塞后续清理且不重放密钥', () async {
    final id = await add();
    final release = Completer<void>();
    cleanup = () => release.future;
    final first = owner.command('identity.global.import', {
      'privateKeyPem': 'key-b',
    });
    while (retired.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final writes = sdk.replacements;
    final second = owner.command('identity.global.import', {
      'privateKeyPem': 'key-c',
    });
    await Future<void>.delayed(Duration.zero);
    expect(sdk.replacements, writes);
    await expectLater(owner.selectForDevice(id), throwsA(interop));
    release.complete();
    await first;
    await second;
    expect(
      (await owner.selectForDevice(id)).fingerprint,
      sdk.info('key-c').fingerprint,
    );
  });

  test('回收失败不伪装成功，重试只清理不重复提交', () async {
    final id = await add();
    cleanup = () async => throw StateError('cleanup failed');
    await expectLater(
      owner.command('identity.global.import', {'privateKeyPem': 'key-b'}),
      throwsStateError,
    );
    final writes = sdk.replacements;
    expect(records.current.find(id)!.status, 'unauthorized');
    await expectLater(owner.selectForDevice(id), throwsA(interop));
    cleanup = null;
    await owner.retryCleanup();
    expect(sdk.replacements, writes);
    expect(
      (await owner.selectForDevice(id)).fingerprint,
      sdk.info('key-b').fingerprint,
    );
  });

  test('未知提交保留阻断，清理成功也不当作已确认；重开先核对磁盘', () async {
    final id = await add();
    sdk.unknownNext = true;
    await expectLater(
      owner.command('identity.global.import', {'privateKeyPem': 'key-b'}),
      throwsA(interop.having((e) => e.code, 'code', 'identity_result_unknown')),
    );
    await owner.retryCleanup();
    await expectLater(owner.selectForDevice(id), throwsA(interop));
    final writes = sdk.replacements;
    await expectLater(
      owner.command('identity.global.import', {'privateKeyPem': 'key-c'}),
      throwsA(interop),
    );
    expect(sdk.replacements, writes);
    owner = await open();
    expect(
      (await owner.selectForDevice(id)).fingerprint,
      sdk.info('key-b').fingerprint,
    );
  });

  test('CAS 冲突不撤销连接或覆盖其他写者，移除后仅清理对应私钥', () async {
    final id = await add();
    sdk.conflictNext = true;
    await expectLater(
      owner.command('identity.global.import', {'privateKeyPem': 'key-b'}),
      throwsA(interop),
    );
    expect(retired, isEmpty);
    await owner.command('identity.device.import', {
      'deviceId': id,
      'privateKeyPem': 'key-b',
    });
    await expectLater(owner.forgetDevice(id), throwsA(interop));
    await records.remove(id);
    await owner.forgetDevice(id);
    expect(
      await File(p.join(root.path, 'identities', '$id.pem')).exists(),
      isFalse,
    );
    expect(await File(p.join(root.path, 'host_identity.pem')).exists(), isTrue);
  });

  test('私钥已发布但元数据提交失败时阻断且明确未知，重开核验恢复', () async {
    final id = await add();
    var reject = false;
    records = await DeviceRecordStore.open(
      directory: root,
      commitFile: (temporary, destination) async {
        if (reject) throw const FileSystemException('injected commit failure');
        await temporary.rename(destination.path);
      },
    );
    owner = await open();
    reject = true;
    await expectLater(
      owner.command('identity.global.import', {'privateKeyPem': 'key-b'}),
      throwsA(interop.having((e) => e.code, 'code', 'identity_result_unknown')),
    );
    expect(
      await File(p.join(root.path, 'host_identity.pem')).readAsString(),
      'key-b',
    );
    expect(retired.single.$1, {id});
    reject = false;
    await owner.retryCleanup();
    await expectLater(owner.selectForDevice(id), throwsA(interop));
    owner = await open();
    expect(
      (await owner.selectForDevice(id)).fingerprint,
      sdk.info('key-b').fingerprint,
    );
    expect(records.current.find(id)!.autoReconnect, isFalse);
  });

  test('身份读取迟到不得把旧材料归入新代次，替换期间也不得准入', () async {
    final id = await add();
    final observed = Completer<void>();
    final releaseRead = Completer<void>();
    sdk.inspectHook = (_) {
      observed.complete();
      return releaseRead.future;
    };
    final lateSelection = owner.selectForDevice(id);
    final rejected = expectLater(lateSelection, throwsA(interop));
    await observed.future;
    await owner.command('identity.global.import', {'privateKeyPem': 'key-a'});
    releaseRead.complete();
    await rejected;

    final releaseWrite = Completer<void>();
    sdk.replacementHold = releaseWrite.future;
    final writes = sdk.replacements;
    final mutation = owner.command('identity.global.import', {
      'privateKeyPem': 'key-b',
    });
    while (sdk.replacements == writes) {
      await Future<void>.delayed(Duration.zero);
    }
    await expectLater(owner.selectForDevice(id), throwsA(interop));
    releaseWrite.complete();
    await mutation;
  });

  test('绑定与候选取消并发时，取消等待提交且不删除已绑定私钥', () async {
    final attempt = await owner.prepareSetup({
      'identity': {'scope': 'device', 'privateKeyPem': 'key-b'},
    });
    final id = await add();
    final candidatePath = attempt.selection.path;
    final release = Completer<void>();
    sdk.replacementHold = release.future;
    final writes = sdk.replacements;
    final binding = attempt.bindNew(id);
    while (sdk.replacements == writes) {
      await Future<void>.delayed(Duration.zero);
    }
    var disposed = false;
    final disposing = attempt.dispose().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    release.complete();
    await binding;
    await disposing;
    expect(await File(candidatePath).exists(), isFalse);
    expect(await File(attempt.selection.path).exists(), isTrue);
    expect((await owner.selectForDevice(id)).scope, 'device');
  });

  test('全局来源转专属时记录提交失败，重开按提交意图绑定且不扫描停用 PEM', () async {
    final id = await add();
    var reject = false;
    records = await DeviceRecordStore.open(
      directory: root,
      commitFile: (temporary, destination) async {
        if (reject) throw const FileSystemException('injected commit failure');
        await temporary.rename(destination.path);
      },
    );
    owner = await open();
    reject = true;
    await expectLater(
      owner.command('identity.device.import', {
        'deviceId': id,
        'privateKeyPem': 'key-b',
      }),
      throwsA(interop.having((e) => e.code, 'code', 'identity_result_unknown')),
    );
    expect(records.current.deviceIdentityFingerprints.containsKey(id), isFalse);
    expect(
      await File(p.join(root.path, 'identities', '$id.pem')).readAsString(),
      'key-b',
    );
    expect(
      await File(p.join(root.path, 'identity_transaction.json')).exists(),
      isTrue,
    );
    final writes = sdk.replacements;
    reject = false;
    retired.clear();
    owner = await open();
    expect(sdk.replacements, writes);
    expect((await owner.selectForDevice(id)).scope, 'device');
    expect(retired.single.$1, {id});
    expect(
      await File(p.join(root.path, 'identity_transaction.json')).exists(),
      isFalse,
    );
    await owner.command('identity.device.useGlobal', {'deviceId': id});
    expect(
      await File(p.join(root.path, 'identities', '$id.pem')).exists(),
      isTrue,
    );
    owner = await open();
    expect((await owner.selectForDevice(id)).scope, 'global');
  });

  test('setup 私钥已发布但绑定失败，取消候选后重开仍恢复已提交专属身份', () async {
    final id = await add();
    var reject = false;
    records = await DeviceRecordStore.open(
      directory: root,
      commitFile: (temporary, destination) async {
        if (reject) throw const FileSystemException('injected commit failure');
        await temporary.rename(destination.path);
      },
    );
    owner = await open();
    final attempt = await owner.prepareSetup({
      'identity': {'scope': 'device', 'privateKeyPem': 'key-b'},
    });
    final candidate = attempt.selection.path;
    reject = true;
    await expectLater(
      attempt.bindNew(id),
      throwsA(interop.having((e) => e.code, 'code', 'identity_result_unknown')),
    );
    await attempt.dispose();
    expect(await File(candidate).exists(), isFalse);
    expect(records.current.deviceIdentityFingerprints.containsKey(id), isFalse);
    final writes = sdk.replacements;
    reject = false;
    owner = await open();
    expect(sdk.replacements, writes);
    expect(
      (await owner.selectForDevice(id)).fingerprint,
      sdk.info('key-b').fingerprint,
    );
    expect(records.current.find(id)!.status, 'unauthorized');
  });

  test('bindNew 与 dispose 同栈调用时，排队候选不发布文件或公开绑定', () async {
    final attempt = await owner.prepareSetup({
      'identity': {'scope': 'device', 'privateKeyPem': 'key-b'},
    });
    final id = await add();
    final writes = sdk.replacements;
    final binding = attempt.bindNew(id);
    final rejected = expectLater(
      binding,
      throwsA(interop.having((e) => e.code, 'code', 'identity_changed')),
    );
    final disposing = attempt.dispose();
    await rejected;
    await disposing;
    expect(sdk.replacements, writes);
    expect(records.current.deviceIdentityFingerprints.containsKey(id), isFalse);
    expect(
      await File(p.join(root.path, 'identities', '$id.pem')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(root.path, 'identity_transaction.json')).exists(),
      isFalse,
    );
  });

  test('目标 inspect 尚未返回时取消，不得在迟到后开始密钥替换', () async {
    final attempt = await owner.prepareSetup({
      'identity': {'scope': 'device', 'privateKeyPem': 'key-b'},
    });
    final id = await add();
    final observed = Completer<void>();
    final release = Completer<void>();
    sdk.inspectHook = (_) {
      observed.complete();
      return release.future;
    };
    final writes = sdk.replacements;
    final binding = attempt.bindNew(id);
    final rejected = expectLater(binding, throwsA(interop));
    await observed.future;
    final disposing = attempt.dispose();
    release.complete();
    await rejected;
    await disposing;
    expect(sdk.replacements, writes);
    expect(records.current.deviceIdentityFingerprints.containsKey(id), isFalse);
  });

  test('元数据已提交但退休失败，重开仍先清理且失败时不返回可准入所有者', () async {
    final id = await add();
    cleanup = () async => throw StateError('cleanup failed');
    await expectLater(
      owner.command('identity.global.import', {'privateKeyPem': 'key-b'}),
      throwsStateError,
    );
    expect(records.current.identityFingerprint, sdk.info('key-b').fingerprint);
    expect(
      await File(p.join(root.path, 'identity_transaction.json')).exists(),
      isTrue,
    );
    retired.clear();
    await expectLater(open(), throwsStateError);
    expect(retired.single.$1, {id});
    expect(
      await File(p.join(root.path, 'identity_transaction.json')).exists(),
      isTrue,
    );
    cleanup = null;
    retired.clear();
    owner = await open();
    expect(retired.single.$1, {id});
    expect(
      (await owner.selectForDevice(id)).fingerprint,
      sdk.info('key-b').fingerprint,
    );
    expect(
      await File(p.join(root.path, 'identity_transaction.json')).exists(),
      isFalse,
    );
  });

  test('迁移已提交但退休失败，重开继续退休而非按相等指纹放行', () async {
    final id = await add();
    await File(p.join(root.path, 'device_identities.json'))
        .writeAsString(jsonEncode({id: 'key-b'}));
    cleanup = () async => throw StateError('cleanup failed');
    await expectLater(open(), throwsStateError);
    expect(
      records.current.deviceIdentityFingerprints[id],
      sdk.info('key-b').fingerprint,
    );
    expect(
      await File(p.join(root.path, 'device_identities.json')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(root.path, 'identity_transaction.json')).exists(),
      isTrue,
    );
    cleanup = null;
    retired.clear();
    owner = await open();
    expect(retired.single.$1, {id});
    expect((await owner.selectForDevice(id)).scope, 'device');
  });

  test('候选已经读出但校验回执迟到时取消，仍不能开始不可逆替换', () async {
    final attempt = await owner.prepareSetup({
      'identity': {'scope': 'device', 'privateKeyPem': 'key-b'},
    });
    final id = await add();
    final observed = Completer<void>();
    final release = Completer<void>();
    sdk.validateHook = () {
      observed.complete();
      return release.future;
    };
    final writes = sdk.replacements;
    final binding = attempt.bindNew(id);
    final rejected = expectLater(binding, throwsA(interop));
    await observed.future;
    final disposing = attempt.dispose();
    release.complete();
    await rejected;
    await disposing;
    expect(sdk.replacements, writes);
    expect(
      await File(p.join(root.path, 'identity_transaction.json')).exists(),
      isFalse,
    );
  });

  test('日志写前意图但密钥未发布时重开不重放，未知第三方材料则保留日志并阻断', () async {
    final id = await add();
    final journal = File(p.join(root.path, 'identity_transaction.json'));
    final transaction = {
      'version': 1,
      'kind': 'key',
      'affected': [id],
      'global': false,
      'deviceId': id,
      'previousFingerprint': null,
      'fingerprint': sdk.info('key-b').fingerprint,
    };
    await journal.writeAsString(jsonEncode(transaction), flush: true);
    final writes = sdk.replacements;
    owner = await open();
    expect(sdk.replacements, writes);
    expect((await owner.selectForDevice(id)).scope, 'global');
    expect(await journal.exists(), isFalse);
    await File(p.join(root.path, 'identities', '$id.pem'))
        .writeAsString('key-c', flush: true);
    final bytes = utf8.encode(jsonEncode(transaction));
    await journal.writeAsBytes(bytes, flush: true);
    await expectLater(
      open(),
      throwsA(interop.having((e) => e.code, 'code', 'identity_result_unknown')),
    );
    expect(await journal.readAsBytes(), bytes);
    expect(records.current.deviceIdentityFingerprints.containsKey(id), isFalse);
    expect(retired.single.$1, {id});
  });

  test('事务损坏或版本较新时保留原字节，不改变密钥与记录', () async {
    final journal = File(p.join(root.path, 'identity_transaction.json'));
    final key = File(p.join(root.path, 'host_identity.pem'));
    final bytes = await key.readAsBytes();
    final saved = await records.file.readAsBytes();
    for (final source in ['{broken', '{"version":2}', '{"version":1.0}']) {
      await journal.writeAsString(source, flush: true);
      await expectLater(open(), throwsA(interop));
      expect(await journal.readAsString(), source);
      expect(await key.readAsBytes(), bytes);
      expect(await records.file.readAsBytes(), saved);
    }
  });

  test('未完成专属事务对应记录已遗忘时，不复建设备且回收其已发布私钥', () async {
    final id = await add();
    var reject = false;
    records = await DeviceRecordStore.open(
      directory: root,
      commitFile: (temporary, destination) async {
        if (reject) throw const FileSystemException('injected commit failure');
        await temporary.rename(destination.path);
      },
    );
    owner = await open();
    reject = true;
    await expectLater(
      owner.command('identity.device.import', {
        'deviceId': id,
        'privateKeyPem': 'key-b',
      }),
      throwsA(interop),
    );
    reject = false;
    await records.remove(id);
    owner = await open();
    expect(records.current.find(id), isNull);
    expect(
      await File(p.join(root.path, 'identities', '$id.pem')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(root.path, 'identity_transaction.json')).exists(),
      isFalse,
    );
    expect(await File(p.join(root.path, 'host_identity.pem')).exists(), isTrue);
  });

  test('意图日志无法发布时不开始 SDK 密钥替换', () async {
    final id = await add();
    final blocker = await Directory(
      p.join(root.path, 'identity_transaction.json'),
    ).create();
    final writes = sdk.replacements;
    await expectLater(
      owner.command('identity.device.import', {
        'deviceId': id,
        'privateKeyPem': 'key-b',
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(sdk.replacements, writes);
    expect((await owner.selectForDevice(id)).scope, 'global');
    expect(
      await File(p.join(root.path, 'identities', '$id.pem')).exists(),
      isFalse,
    );
    await blocker.delete();
  });
}

/// 使用真实文件与原子替换，仅把 RSA 机制替换成可控的 SDK 接缝。
final class _Identities implements AdbIdentities {
  int replacements = 0;
  int candidatePrepares = 0;
  bool unknownNext = false;
  bool conflictNext = false;
  Future<void> Function(String)? inspectHook;
  Future<void> Function()? validateHook;
  Future<void>? replacementHold;
  AdbIdentityInfo info(String pem) => AdbIdentityInfo(
    fingerprint: List.filled(64, switch (pem) {
      'key-a' => 'a',
      'key-b' => 'b',
      'key-c' => 'c',
      _ => throw const FormatException('invalid'),
    }).join(),
    fingerprintAlgorithm: 'sha256',
    fingerprintInput: 'adb-public-key-interop-v1',
    bits: 2048,
    exponent: 65537,
  );
  @override
  Future<AdbIdentityInfo?> inspectIdentity(String path) async {
    final file = File(path);
    final result = await file.exists() ? info(await file.readAsString()) : null;
    final hook = inspectHook;
    inspectHook = null;
    if (hook != null) await hook(path);
    return result;
  }

  @override
  Future<void> prepareIdentity(String path) async {
    if (await inspectIdentity(path) != null) return;
    final candidate = path.contains('.candidate-');
    if (candidate) candidatePrepares++;
    await File(path).writeAsString(candidate ? 'key-c' : 'key-a', flush: true);
  }

  @override
  Future<AdbIdentityInfo> validateIdentity(String pem) async {
    final hook = validateHook;
    validateHook = null;
    if (hook != null) await hook();
    return info(pem);
  }

  @override
  Future<AdbIdentityCommitReceipt> replaceIdentity(
    String path,
    String pem, {
    String? expectedFingerprint,
  }) async {
    replacements++;
    final hold = replacementHold;
    replacementHold = null;
    if (hold != null) await hold;
    final original = await inspectIdentity(path);
    if (conflictNext || original?.fingerprint != expectedFingerprint) {
      conflictNext = false;
      return const AdbIdentityCommitReceipt(
        state: AdbIdentityCommitState.unchanged,
        error: 'conflict',
      );
    }
    final next = info(pem);
    if (original?.fingerprint != next.fingerprint) {
      final temporary = File('$path.tmp');
      await temporary.writeAsString(pem, flush: true);
      await temporary.rename(path);
    }
    if (unknownNext) {
      unknownNext = false;
      return AdbIdentityCommitReceipt(
        state: AdbIdentityCommitState.unknown,
        identity: next,
      );
    }
    return AdbIdentityCommitReceipt(
      state: original?.fingerprint == next.fingerprint
          ? AdbIdentityCommitState.unchanged
          : AdbIdentityCommitState.committed,
      identity: next,
    );
  }
}
