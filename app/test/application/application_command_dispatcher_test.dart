import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../media/cache/support/media_file_fixture.dart';

import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/files/documents/delivery_journal.dart';
import 'package:scrcpy_connect/media/cache/app_media_cache.dart';
import 'package:scrcpy_connect/application/application_command_dispatcher.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/files/transfers/transfer_coordinator.dart';
import 'package:scrcpy_connect/files/catalog/file_catalog.dart';
import 'package:scrcpy_connect/files/mutations/file_mutation_coordinator.dart';
import 'package:scrcpy_connect/files/execution/file_executor.dart';

import '../files/support/file_executor_fixture.dart';

import 'package:scrcpy_connect/preferences/preference_commands.dart';
import 'package:scrcpy_connect/preferences/preference_store.dart';

const _device = '7b2a4273-cd2e-4aca-b86e-1e6d81170c81';

void main() {
  late Directory directory;
  late PreferenceStore preferences;
  late _FileOwners owners;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('command-owner-');
    owners = await _FileOwners.open(
      Directory(p.join(directory.path, 'files')),
      FixtureExecutor(),
    );
    preferences = await PreferenceCommands.prepare(directory);
    await preferences.update({
      'deviceQuality': {
        _device: {'maxFps': 30},
      },
      'deviceSettings': {
        _device: {'stayAwake': true},
      },
    });
  });
  tearDown(() async {
    await owners.close();
    await directory.delete(recursive: true);
  });

  test('生产分发器在应用执行缓存及保存日志命令，不调用原生业务 owner', () async {
    final gate = MediaCacheGate();
    late final AppMediaCache cache;
    final journal = await DeliveryJournal.open(
      directory,
      cacheGate: gate,
      validateSource: (path) => cache.validateDeliveryLocked(path),
    );
    cache = await AppMediaCache.open(
      root: directory,
      gate: gate,
      protectedPaths: () => journal.protectedPaths,
    );
    final files = await _FileOwners.open(
      Directory(p.join(directory.path, 'media-files')),
      MediaFileFixture(),
      cache: cache,
    );
    final commands = ApplicationCommandDispatcher(
      executor: files.executor,
      catalog: files.catalog,
      mutations: files.mutations,
      transfers: files.transfers,
      preferences: preferences,
      cache: cache,
      deliveries: journal,
      execute: (_, _) => throw StateError('本地命令不能落到原生'),
      onSettingsChanged: (_) {},
      applyBackgroundPolicy: (_) async {},
    );
    try {
      expect(
        (await commands.invoke('media.cache.configure', {
          'budgetBytes': 8192,
        }))['budgetBytes'],
        8192,
      );
      final preview = await commands.invoke('media.preview', {
        'deviceId': _device,
        'path': '/sdcard/image.png',
      });
      expect(
        await File(preview['localPath'] as String).readAsBytes(),
        List<int>.generate(10, (i) => i),
      );
      await commands.invoke('media.cache.release', {
        'leaseId': preview['cacheLeaseId'],
      });
      expect(
        (await commands.invoke('media.cache.clear', {}))['deletedBytes'],
        greaterThan(0),
      );
      final source = File(p.join(directory.path, 'media', 'preview.bin'));
      await source.parent.create(recursive: true);
      await source.writeAsBytes([1, 2, 3]);
      final identity = <String, dynamic>{
        'sourceId': 'preview',
        'localPath': source.path,
        'kind': 'file',
      };
      await commands.invoke('delivery.begin', {
        ...identity,
        'operationId': 'save',
        'name': 'preview.bin',
      });
      expect(
        (await commands.invoke('media.cache.clear', {}))['deletedBytes'],
        0,
      );
      await commands.invoke('delivery.finish', {
        ...identity,
        'operationId': 'save',
        'result': {'status': 'saved'},
      });
      expect(
        (await commands.invoke('media.cache.clear', {}))['deletedBytes'],
        3,
      );
      expect(
        ((await commands.invoke('delivery.get', identity))['record']
            as Map)['status'],
        'saved',
      );
      expect(
        (await (await AppMediaCache.open(root: directory))
            .status())['budgetBytes'],
        8192,
      );
      expect(
        ((await (await DeliveryJournal.open(directory))
                .command('delivery.get', identity))['record']
            as Map)['status'],
        'saved',
      );
    } finally {
      await commands.closeMediaArtifacts();
      await files.close();
    }
  });

  test('未提供分享所有者时只返回本地空投影，写命令不进入执行器', () async {
    final calls = <String>[];
    final commands = ApplicationCommandDispatcher(
      executor: owners.executor,
      catalog: owners.catalog,
      mutations: owners.mutations,
      transfers: owners.transfers,
      preferences: preferences,
      execute: (command, params) async {
        calls.add(command);
        throw StateError('分享命令不能进入设备执行器');
      },
      onSettingsChanged: (_) {},
      applyBackgroundPolicy: (_) async {},
    );
    expect(await commands.invoke('sharing.pending', {}), {
      'shares': <Object?>[],
    });
    await expectLater(
      commands.invoke('sharing.import', {}),
      throwsA(
        isA<ApplicationCommandException>().having(
          (error) => error.code,
          'code',
          'platform_unavailable',
        ),
      ),
    );
    expect(calls, isEmpty);
  });

  test('执行器接收结构化参数，真实领域错误与恢复详情原样保留', () async {
    const failure = ApplicationCommandException(
      'app_launch_unknown',
      '请核验原窗口',
      {'sessionId': 'old', 'launchOutcome': 'unknown'},
    );
    final calls = <(String, Map<String, dynamic>)>[];
    final commands = ApplicationCommandDispatcher(
      executor: owners.executor,
      catalog: owners.catalog,
      mutations: owners.mutations,
      transfers: owners.transfers,
      preferences: preferences,
      execute: (command, params) async {
        calls.add((command, Map.of(params)));
        throw failure;
      },
      onSettingsChanged: (_) {},
      applyBackgroundPolicy: (_) async {},
    );
    await expectLater(
      commands.invoke('session.start', {'deviceId': _device}),
      throwsA(same(failure)),
    );
    expect(calls.single.$1, 'session.start');
    expect(calls.single.$2['deviceId'], _device);
    await expectLater(
      commands.invoke('devices.connect', {'deviceId': 1}),
      throwsA(
        isA<ApplicationCommandException>().having(
          (error) => error.code,
          'code',
          'invalid_argument',
        ),
      ),
    );
    expect(calls, hasLength(1));
  });

  test('遗忘确认后才清理持久偏好，不同步第二份执行配置', () async {
    final receipt = Completer<Map<String, dynamic>>();
    final issued = Completer<void>();
    final calls = <String>[];
    final files = owners;
    final executor = files.executor as FixtureExecutor;
    executor.blockList = true;
    executor.blockCopy = true;
    executor.copyStarted = Completer<void>();
    executor.stamps['/source'] = regular;
    final search = files.catalog.startSearch(
      _device,
      '/sdcard',
      query: 'pending',
    );
    final transfer = await files.transfers.startTransfer(_device, true, [
      {'source': '/source', 'destination': '/sdcard/new'},
    ]);
    await executor.copyStarted!.future;
    await until(() => executor.calls.contains('list:/sdcard'));
    final commands = ApplicationCommandDispatcher(
      executor: files.executor,
      catalog: files.catalog,
      mutations: files.mutations,
      transfers: files.transfers,
      preferences: preferences,
      execute: (command, params) async {
        calls.add(command);
        expect(params, {'deviceId': _device});
        if (command == 'devices.forget') {
          issued.complete();
          return receipt.future;
        }
        fail('遗忘后不得再向原生同步偏好镜像');
      },
      onSettingsChanged: (_) {},
      applyBackgroundPolicy: (_) async {},
    );
    final operation = commands.invoke('devices.forget', {'deviceId': _device});
    await issued.future;
    expect(preferences.current.values['deviceQuality'], contains(_device));
    expect(
      files.catalog.scan(_device, search['searchId'] as String)['status'],
      'cancelled',
    );
    expect(
      files.transfers.transfer(transfer['transferId'] as String)['status'],
      'cancelled',
    );
    receipt.complete({
      'deviceId': _device,
      'disconnected': true,
      'forgotten': true,
    });
    expect((await operation)['forgotten'], isTrue);
    expect(calls, ['devices.forget']);
    final reopened = await PreferenceCommands.prepare(directory);
    expect(reopened.current.values['deviceQuality'], isNot(contains(_device)));
    expect(reopened.current.values['deviceSettings'], isNot(contains(_device)));
  });

  test('遗忘未确认成功时保留持久偏好', () async {
    final calls = <String>[];
    final commands = ApplicationCommandDispatcher(
      executor: owners.executor,
      catalog: owners.catalog,
      mutations: owners.mutations,
      transfers: owners.transfers,
      preferences: preferences,
      execute: (command, params) async {
        calls.add(command);
        throw const ApplicationCommandException('cleanup_unknown', '连接回收尚未确认。');
      },
      onSettingsChanged: (_) {},
      applyBackgroundPolicy: (_) async {},
    );
    await expectLater(
      commands.invoke('devices.forget', {'deviceId': _device}),
      throwsA(
        isA<ApplicationCommandException>().having(
          (error) => error.code,
          'code',
          'cleanup_unknown',
        ),
      ),
    );
    expect(calls, ['devices.forget']);
    final reopened = await PreferenceCommands.prepare(directory);
    expect(reopened.current.values['deviceQuality'], contains(_device));
    expect(reopened.current.values['deviceSettings'], contains(_device));
  });
}

/// 组合真实文件所有者；测试只替换执行器，不替换业务接口。
final class _FileOwners {
  _FileOwners(this.executor, this.catalog, this.mutations, this.transfers);
  final FileExecutor executor;
  final FileCatalog catalog;
  final FileMutationCoordinator mutations;
  final TransferCoordinator transfers;

  static Future<_FileOwners> open(
    Directory root,
    FileExecutor executor, {
    FileCacheLeases? cache,
  }) async {
    await root.create(recursive: true);
    return _FileOwners(
      executor,
      FileCatalog(executor),
      FileMutationCoordinator(executor),
      await TransferCoordinator.open(
        executor: executor,
        dataDirectory: root,
        cache: cache,
      ),
    );
  }

  Future<void> close() async {
    await Future.wait([catalog.close(), mutations.close(), transfers.close()]);
  }
}
