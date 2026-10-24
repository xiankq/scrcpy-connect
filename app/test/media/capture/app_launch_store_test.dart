import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/media/capture/app_launch_store.dart';

const _first = '00000000-0000-4000-8000-000000000001';
const _second = '00000000-0000-4000-8000-000000000002';
const _third = '00000000-0000-4000-8000-000000000003';

Matcher _code(String value) => isA<ApplicationCommandException>().having(
  (error) => error.code,
  'code',
  value,
);

Future<AppLaunchPermit> _begin(
  AppLaunchStore store,
  String operation, {
  String? session,
  String device = 'phone',
  String package = 'dev.example.app',
}) => store.begin(
  operationId: operation,
  sessionId: session ?? operation,
  deviceId: device,
  packageName: package,
);

Map<String, Object?> _record(String operation, String status) => {
  'operationId': operation,
  'sessionId': operation,
  'deviceId': 'phone',
  'packageName': 'dev.example.app',
  'status': status,
  'updatedAt': 1,
};

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('app-launch-store-');
    file = File.fromUri(directory.uri.resolve('app-opens.json'));
  });
  tearDown(() => directory.delete(recursive: true));

  test('持久化先于准入，同一设备应用的并发意图只交付一次', () async {
    final store = await AppLaunchStore.open(directory: directory);
    final first = _begin(store, _first);
    final duplicate = _begin(store, _second);
    await expectLater(duplicate, throwsA(_code('app_launch_unknown')));
    final permit = await first;
    final saved = jsonDecode(await file.readAsString()) as Map;
    expect((saved['records'] as Map)[_first]['status'], 'pending');
    expect(permit.claim(), isTrue);
    expect(permit.claim(), isFalse);
    // 产品设备身份是防重边界，不能以应用包名推断另一台手机的任务。
    expect(
      await _begin(store, _third, device: 'other'),
      isA<AppLaunchPermit>(),
    );
  });

  test('v1 记录在打开、呈现和关闭各阶段始终使用 Unix 秒', () async {
    var time = DateTime.fromMillisecondsSinceEpoch(123456789);
    final store = await AppLaunchStore.open(
      directory: directory,
      now: () => time,
    );
    Future<int> savedTime() async =>
        ((jsonDecode(await file.readAsString()) as Map)['records']
                as Map)[_first]['updatedAt']
            as int;
    await _begin(store, _first);
    expect(await savedTime(), 123456);
    time = DateTime.fromMillisecondsSinceEpoch(123458123);
    await store.finish(_first);
    expect(await savedTime(), 123458);
    time = DateTime.fromMillisecondsSinceEpoch(123460999);
    await store.close(_first);
    expect(await savedTime(), 123460);
  });

  test('重开将 pending 和 observed 都恢复为未知，不恢复旧准入', () async {
    final store = await AppLaunchStore.open(directory: directory);
    final pending = await _begin(store, _first);
    final observed = await _begin(store, _second, device: 'other');
    expect(observed.claim(), isTrue);
    await store.finish(_second);
    final reopened = await AppLaunchStore.open(directory: directory);
    expect(pending.claim(), isFalse);
    final records = await reopened.unresolved();
    expect(
      records.map((record) => record.status),
      everyElement(AppLaunchStatus.unknown),
    );
    expect(
      records.map((record) => record.failureCode),
      everyElement('interrupted'),
    );
    await expectLater(
      _begin(reopened, _third),
      throwsA(_code('app_launch_unknown')),
    );
    await expectLater(
      store.close(_first),
      throwsA(_code('app_open_owner_replaced')),
    );
    final saved = jsonDecode(await file.readAsString()) as Map;
    expect((saved['records'] as Map)[_second]['status'], 'unknown');
  });

  test('兼容原版 v1 缺省 failureCode 与单段包名，不丢失未知记录', () async {
    final record = _record(_first, 'unknown')..['packageName'] = 'android';
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'records': {_first: record},
      }),
    );
    final store = await AppLaunchStore.open(directory: directory);
    final recovered = (await store.unresolved()).single;
    expect(recovered.packageName, 'android');
    expect(recovered.failureCode, isNull);
    expect(recovered.projection['recordOnly'], isTrue);
  });

  test('明确关闭使排队准入失效，迟到呈现不能重新打开记录', () async {
    final store = await AppLaunchStore.open(directory: directory);
    final permit = await _begin(store, _first);
    await expectLater(
      store.close(_first, deviceId: 'other'),
      throwsA(_code('invalid_argument')),
    );
    expect(permit.cancelled, isFalse);
    expect(await store.close(_first, deviceId: 'phone'), isTrue);
    expect(permit.claim(), isFalse);
    await expectLater(store.finish(_first), throwsA(_code('cancelled')));
    expect(await store.close(_first), isTrue);
    expect(await store.unresolved(), isEmpty);
    final reopened = await AppLaunchStore.open(directory: directory);
    expect(await reopened.unresolved(), isEmpty);
    await _begin(reopened, _second);
  });

  test('副作用失败保留未知证据，迟到成功不覆盖它', () async {
    final store = await AppLaunchStore.open(directory: directory);
    final permit = await _begin(store, _first);
    expect(permit.claim(), isTrue);
    await store.finish(_first, failureCode: 'control_write_unknown');
    expect(permit.cancelled, isTrue);
    await expectLater(store.finish(_first), throwsA(_code('cancelled')));
    final record = (await store.unresolved()).single;
    expect(record.failureCode, 'control_write_unknown');
    await expectLater(
      _begin(store, _second),
      throwsA(_code('app_launch_unknown')),
    );
  });

  test('主屏独立打开成功后关闭本次记录，保持关联会话身份', () async {
    final store = await AppLaunchStore.open(directory: directory);
    await _begin(store, _first, session: _second);
    final projection = (await store.unresolved()).single.projection;
    expect(projection['launchOperationId'], _first);
    expect(projection['linkedSessionId'], _second);
    await store.finish(_first);
    final reopened = await AppLaunchStore.open(directory: directory);
    expect(await reopened.unresolved(), isEmpty);
    await _begin(reopened, _third);
  });

  for (final invalid in [
    {'version': 2, 'records': <String, Object?>{}},
    {
      'version': 1.0,
      'records': {_first: _record(_first, 'pending')},
    },
    {
      'version': 1,
      'records': {
        _first: {..._record(_first, 'unknown'), 'unrecognized': null},
      },
    },
    {
      'version': 1,
      'records': {
        _first: {..._record(_first, 'unknown'), 'sessionId': 'bad'},
      },
    },
    {
      'version': 1,
      'records': {
        _first: {..._record(_first, 'unknown'), 'failureCode': '故障' * 50},
      },
    },
  ]) {
    test('无效记录原样保留，不覆盖既有副作用证据：$invalid', () async {
      final bytes = utf8.encode(jsonEncode(invalid));
      await file.writeAsBytes(bytes);
      await expectLater(
        AppLaunchStore.open(directory: directory),
        throwsA(_code('app_open_storage_invalid')),
      );
      expect(await file.readAsBytes(), bytes);
    });
  }

  test('容量回收只淘汰已关闭项，不丢弃未知副作用', () async {
    String id(int index) =>
        '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';
    final records = <String, Object?>{
      for (var index = 100; index < 1124; index++)
        id(index): _record(id(index), index == 100 ? 'closed' : 'unknown'),
    };
    await file.writeAsString(jsonEncode({'version': 1, 'records': records}));
    final store = await AppLaunchStore.open(directory: directory);
    await _begin(store, _first, device: 'another');
    expect(await store.unresolved(), hasLength(1024));
    final saved = jsonDecode(await file.readAsString()) as Map;
    expect((saved['records'] as Map).containsKey(id(100)), isFalse);
    await expectLater(
      _begin(store, _second, device: 'third'),
      throwsA(_code('app_open_capacity')),
    );
    expect(await store.unresolved(), hasLength(1024));
  });

  test('超过读取上限的旧记录保持原字节，不尝试修复或覆盖', () async {
    final bytes = List.filled(2 * 1024 * 1024 + 1, 32);
    await file.writeAsBytes(bytes);
    await expectLater(
      AppLaunchStore.open(directory: directory),
      throwsA(_code('app_open_storage_invalid')),
    );
    expect(await file.readAsBytes(), bytes);
  });

  test('真实 rename 已完成但回执丢失，封存实例并从磁盘恢复未知', () async {
    final store = await AppLaunchStore.open(directory: directory);
    final faults = _LostCommit(file.path);
    await IOOverrides.runWithIOOverrides(() async {
      await expectLater(
        _begin(store, _first),
        throwsA(_code('app_open_storage_unknown')),
      );
    }, faults);
    expect(faults.committed, isTrue);
    await expectLater(
      store.unresolved(),
      throwsA(_code('app_open_storage_unknown')),
    );
    await expectLater(
      _begin(store, _second),
      throwsA(_code('app_open_storage_unknown')),
    );
    final reopened = await AppLaunchStore.open(directory: directory);
    expect((await reopened.unresolved()).single.operationId, _first);
    await expectLater(
      _begin(reopened, _second),
      throwsA(_code('app_launch_unknown')),
    );
    expect(
      await directory
          .list()
          .where((entry) => entry.path.endsWith('.tmp'))
          .isEmpty,
      isTrue,
    );
  });
}

/// 文件创建、写入和原子替换真实执行，仅丢弃系统返回的替换回执。
final class _LostCommit extends IOOverrides {
  _LostCommit(this.destination);
  final String destination;
  bool committed = false;
  @override
  File createFile(String path) => _LostCommitFile(super.createFile(path), this);
}

final class _LostCommitFile implements File {
  _LostCommitFile(this.file, this.faults);
  final File file;
  final _LostCommit faults;
  @override
  String get path => file.path;
  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) =>
      file.create(recursive: recursive, exclusive: exclusive);
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      file.open(mode: mode);
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);
  @override
  Future<File> rename(String newPath) async {
    final result = await file.rename(newPath);
    if (newPath == faults.destination && !faults.committed) {
      faults.committed = true;
      throw const FileSystemException('替换已完成但回执丢失');
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
