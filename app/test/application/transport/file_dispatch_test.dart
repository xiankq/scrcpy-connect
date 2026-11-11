import 'package:scrcpy_connect/models/file_failure.dart';
import 'package:scrcpy_connect/models/file_cancellation.dart';
import 'package:scrcpy_connect/models/file_stamp.dart';
import 'package:scrcpy_connect/services/file_executor.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/application_command_dispatcher.dart';
import 'package:scrcpy_connect/services/app_settings.dart';
import 'package:scrcpy_connect/services/settings_storage.dart';
import 'package:scrcpy_connect/services/device_record_storage.dart';
import 'package:scrcpy_connect/models/preference_schema.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/file_catalog.dart';
import 'package:scrcpy_connect/services/file_mutation_service.dart';
import 'package:scrcpy_connect/services/file_transfer_service.dart';

import '../../files/support/file_executor_fixture.dart';

const _selected = FileStamp(
  mode: 0x8000,
  size: 4,
  modifiedSeconds: 1,
  identity: '1-2-3-4',
);

void main() {
  late Directory root;
  late _Executor executor;
  late FileCatalog catalog;
  late FileMutationService mutations;
  late FileTransferService transfers;
  late ApplicationCommandDispatcher commands;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('file-commands-');
    executor = _Executor();
    catalog = FileCatalog(executor);
    mutations = FileMutationService(executor);
    transfers = await FileTransferService.open(
      executor: executor,
      dataDirectory: root,
    );
    commands = ApplicationCommandDispatcher(
      execute: (command, params) async => throw StateError(command.wire),
      preferences: AppSettings(
        preferences: await SettingsStorage.open(
          directory: root,
          schema: PreferenceSchema(defaults: preferenceDefaults),
        ),
        records: await DeviceRecordStorage.open(directory: root),
        onDevicesImported: (_) {},
        onChanged: (_) {},
      ),
      catalog: catalog,
      mutations: mutations,
      transfers: transfers,
    );
  });
  tearDown(() async {
    await Future.wait([catalog.close(), mutations.close(), transfers.close()]);
    await root.delete(recursive: true);
  });

  test('目录及修改协议映射到各自所有者，旧文件名字段只用于构造目标路径', () async {
    executor.children['/sdcard'] = [
      entry('photo.jpg', regular),
      entry('note.txt', regular),
    ];
    final listing = await commands.invoke('files.list', {
      'deviceId': 'device',
      'path': '/sdcard',
      'filter': 'images',
    });
    expect(
      (listing['entries'] as List).single,
      containsPair('name', 'photo.jpg'),
    );
    expect(
      await commands.invoke('files.mkdir', {
        'deviceId': 'device',
        'path': '/sdcard/new',
      }),
      {'ok': true},
    );
    expect(
      await commands.invoke('files.rename', {
        'deviceId': 'device',
        'path': '/sdcard/old',
        'name': 'renamed',
        'expectedStamp': _selected.toJson(),
      }),
      {'ok': true},
    );
    expect(
      await commands.invoke('files.delete', {
        'deviceId': 'other',
        'paths': ['/sdcard/a', '/sdcard/b'],
        'expectedStamps': {
          '/sdcard/a': _selected.toJson(),
          '/sdcard/b': _selected.toJson(),
        },
      }),
      {'ok': true},
    );
    expect(executor.mutations, [
      ('device', 'mkdir', '/sdcard/new', ''),
      ('device', 'rename', '/sdcard/old', '/sdcard/renamed'),
      ('other', 'delete', '/sdcard/a', ''),
      ('other', 'delete', '/sdcard/b', ''),
    ]);
    await expectLater(
      commands.invoke('files.list', {'deviceId': 1}),
      throwsA(
        isA<RequestFailure>().having(
          (error) => error.code,
          'code',
          'invalid_argument',
        ),
      ),
    );
  });

  test('推送接受旧单项path与conflict字段，传输历史仍由持久所有者提供', () async {
    executor.stamps['/source'] = regular;
    executor.stamps['/sdcard/existing'] = regular;
    executor.contents['/sdcard/existing'] = [9];
    final started = await commands.invoke('files.push', {
      'deviceId': 'device',
      'path': '/source',
      'destination': '/sdcard/existing',
      'conflict': 'keepBoth',
    });
    final id = started['transferId'] as String;
    await until(() => transfers.transfer(id)['status'] == 'completed');
    final projection = await commands.invoke('transfers.get', {
      'transferId': id,
    });
    expect(projection['status'], 'completed');
    expect(executor.contents['/sdcard/existing'], [9]);
    expect(executor.contents['/sdcard/existing (1)'], [1, 2, 3, 4]);
    expect(
      (await commands.invoke('transfers.list', {}))['transfers'],
      hasLength(1),
    );
  });

  test('关闭目录所有者不撤销共享执行器上的修改和传输，组合停止等待各自真实收尾', () async {
    executor.blockList = true;
    executor.blockCopy = true;
    executor.blockMutation = true;
    executor.copyStarted = Completer<void>();
    executor.stamps['/source'] = regular;
    catalog.startSearch('device', '/sdcard', query: 'pending');
    final changing = mutations.delete(
      'device',
      ['/sdcard/old'],
      expected: {'/sdcard/old': _selected},
    );
    final changeCancelled = expectLater(
      changing,
      throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    final started = await transfers.startTransfer('device', true, [
      {'source': '/source', 'destination': '/sdcard/new'},
    ]);
    await executor.copyStarted!.future;
    await executor.mutationStarted.future;
    await catalog.close();
    expect(executor.mutationCancellation!.isCancelled, isFalse);
    expect(
      transfers.transfer(started['transferId'] as String)['status'],
      'running',
    );
    await Future.wait([
      mutations.cancelDevice('device'),
      transfers.cancelDevice('device'),
    ]);
    await changeCancelled;
    expect(executor.closedBatches, 1);
    expect(
      transfers.transfer(started['transferId'] as String)['status'],
      'cancelled',
    );
    expect(executor.calls.where((call) => call.startsWith('commit:')), isEmpty);
  });
}

final class _Executor extends FixtureExecutor implements FileMutationExecutor {
  final mutations = <(String, String, String, String)>[];
  final mutationStarted = Completer<void>();
  FileCancellation? mutationCancellation;
  bool blockMutation = false;
  int closedBatches = 0;

  @override
  Future<FileMutationBatch> beginMutation(
    String device, {
    required FileCancellation cancellation,
  }) async {
    mutationCancellation = cancellation;
    return _Batch(this, device, cancellation);
  }
}

final class _Batch implements FileMutationBatch {
  _Batch(this.executor, this.device, this.cancellation);
  final _Executor executor;
  final String device;
  final FileCancellation cancellation;
  bool closed = false;

  @override
  Future<String> mutate(
    String action,
    String path, {
    String destination = '',
    FileStamp? expected,
  }) async {
    cancellation.check();
    executor.mutations.add((device, action, path, destination));
    if (!executor.mutationStarted.isCompleted) {
      executor.mutationStarted.complete();
    }
    if (executor.blockMutation) {
      await cancellation.whenCancelled;
      cancellation.check();
    }
    return 'applied';
  }

  @override
  Future<void> close() async {
    if (!closed) executor.closedBatches++;
    closed = true;
  }
}
