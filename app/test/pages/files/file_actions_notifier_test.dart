import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_directory_notifier.dart';
import 'package:scrcpy_connect/core/files/file_mutations.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/pages/files/file_actions_notifier.dart';

const _target = (deviceId: 'device', path: '/sdcard/Download');

void main() {
  late ProviderContainer container;
  late _Mutations mutations;
  late _Transfers transfers;
  late FileActionsNotifier actions;
  late void Function() leave;
  final scope = Object();
  final provider = fileActionsProvider(_target, scope: scope);
  final parent = fileDirectoryProvider((deviceId: 'device', path: '/sdcard'));
  final mutationsSource = Provider((ref) => mutations);
  final directories = _Directories();
  var readiness = const DeviceReadiness(
    connectionId: 'one',
    status: .connected,
  );
  final readinessSource = Provider((ref) => readiness);

  setUp(() {
    mutations = _Mutations();
    transfers = _Transfers();
    readiness = const DeviceReadiness(connectionId: 'one', status: .connected);
    container = ProviderContainer(
      overrides: [
        fileMutationsProvider.overrideWith((ref) => ref.watch(mutationsSource)),
        fileTransfersProvider.overrideWithValue(transfers),
        fileDirectoriesProvider.overrideWithValue(directories),
        fileDirectoryProvider(_target).overrideWith(_Directory.new),
        parent.overrideWith(_Directory.new),
        deviceReadinessProvider('device')
            .overrideWith((ref) => ref.watch(readinessSource)),
      ],
    );
    leave = container.listen(provider, (_, _) {}).close;
    actions = container.read(provider.notifier);
  });
  tearDown(() => container.dispose());

  test('同页只提交一个操作，完成后刷新所属目录并结算忙碌状态', () async {
    final pending = actions.createDirectory('中文');
    expect(container.read(provider).busy, isTrue);
    expect(await actions.createDirectory('duplicate'), isFalse);
    expect(mutations.paths, ['/sdcard/Download/中文']);
    mutations.pending.single.complete();
    expect(await pending, isTrue);
    expect(container.read(provider).busy, isFalse);
    expect(
      (container.read(
        fileDirectoryProvider(_target).notifier,
      ) as _Directory)._refreshes,
      1,
    );
  });

  test('失败保留错误并释放忙碌状态，下次明确操作可以重新提交', () async {
    final pending = actions.createDirectory('first');
    mutations.pending.single.completeError(StateError('failed'));
    expect(await pending, isFalse);
    expect(container.read(provider).error, contains('请刷新列表后查看结果'));
    expect(container.read(provider).busy, isFalse);
    final retried = actions.createDirectory('second');
    expect(container.read(provider).error, isNull);
    mutations.pending.last.complete();
    expect(await retried, isTrue);
  });

  test('子目录操作完成时刷新仍打开的上级目录', () async {
    final subscription = container.listen(parent, (_, _) {});
    addTearDown(subscription.close);

    final pending = actions.createDirectory('new');
    mutations.pending.single.complete();
    expect(await pending, isTrue);
    expect((container.read(parent.notifier) as _Directory)._refreshes, 1);
  });

  test('发送回执只表示已登记，不在传输仍写入时刷新目录', () async {
    final sent = actions.send([
      const FileTransferSelection(
        source: '/local/file',
        destination: '/sdcard/Download/file',
      ),
    ]);
    transfers.pending.complete(
      const FileTransferSubmission(
        batchId: 'batch',
        transferId: 'task',
        itemCount: 1,
        status: .queued,
      ),
    );
    expect(await sent, isTrue);
    expect(container.read(provider).busy, isFalse);
    expect(
      (container.read(
        fileDirectoryProvider(_target).notifier,
      ) as _Directory)._refreshes,
      0,
    );
  });

  test('未核验目录或离线设备拒绝新操作，不调用核心执行能力', () async {
    (container.read(fileDirectoryProvider(_target).notifier) as _Directory)
        .invalidateDirectory();
    expect(await actions.createDirectory('blocked'), isFalse);
    expect(mutations.paths, isEmpty);
    readiness = const DeviceReadiness(connectionId: 'one', status: .offline);
    container.invalidate(readinessSource);
    expect(
      await container.read(provider.notifier).createDirectory('offline'),
      isFalse,
    );
    expect(mutations.paths, isEmpty);
  });

  test('连接换代后旧操作回执不能刷新目录或结束新操作', () async {
    final old = actions.createDirectory('old');
    readiness = const DeviceReadiness(connectionId: 'two', status: .connected);
    container.invalidate(readinessSource);
    final next = container.read(provider.notifier).createDirectory('next');
    mutations.pending.first.complete();
    expect(await old, isFalse);
    expect(container.read(provider).busy, isTrue);
    expect(
      (container.read(
        fileDirectoryProvider(_target).notifier,
      ) as _Directory)._refreshes,
      0,
    );
    mutations.pending.last.complete();
    expect(await next, isTrue);
  });

  test('能力换源后原能力的失败不能覆盖后继操作状态', () async {
    final original = mutations;
    final old = actions.createDirectory('old');
    mutations = _Mutations();
    container.invalidate(mutationsSource);
    final next = container.read(provider.notifier).createDirectory('next');
    original.pending.single.completeError(StateError('old failure'));
    expect(await old, isFalse);
    expect(container.read(provider).busy, isTrue);
    expect(container.read(provider).error, isNull);
    mutations.pending.single.complete();
    expect(await next, isTrue);
    expect(original.paths, ['/sdcard/Download/old']);
    expect(mutations.paths, ['/sdcard/Download/next']);
  });

  test('离页只撤销完成反馈，已登记传输仍由原核心能力结算', () async {
    final sent = actions.send([
      const FileTransferSelection(
        source: '/local/file',
        destination: '/sdcard/Download/file',
      ),
    ]);
    expect(transfers.plans.single.deviceId, 'device');
    leave();
    await container.pump();
    // 结束旧页面后仍由同一传输执行对象交付，不取消或重发。
    transfers.pending.complete(
      const FileTransferSubmission(
        batchId: 'batch',
        transferId: 'task',
        itemCount: 1,
        status: .submitted,
      ),
    );
    expect(await sent, isFalse);
    expect(transfers.plans, hasLength(1));
  });
}

class _Directory extends FileDirectoryNotifier {
  int _refreshes = 0;
  void invalidateDirectory() => state = const FileDirectoryState();
  @override
  FileDirectoryState build(FileDirectoryTarget target) => FileDirectoryState(
    data: FileDirectorySnapshot(deviceId: target.deviceId, path: target.path),
    loading: false,
  );
  @override
  Future<void> refresh() async {
    _refreshes++;
  }
}

class _Mutations implements FileMutations {
  final paths = <String>[];
  final pending = <Completer<void>>[];
  @override
  Future<void> createDirectory(String deviceId, String path) {
    paths.add(path);
    final result = Completer<void>();
    pending.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected mutation');
}

class _Transfers implements FileTransfers {
  final plans = <FileTransferPlan>[];
  final pending = Completer<FileTransferSubmission>();
  @override
  Future<FileTransferSubmission> startTransfer(
    FileTransferPlan plan, {
    String? shareId,
  }) {
    plans.add(plan);
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected transfer');
}

class _Directories implements FileDirectories {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected directory read');
}
