import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_changes_provider.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_directory_notifier.dart';

const _target = (deviceId: 'device', path: '/sdcard');

void main() {
  late _Directories directories;
  late StreamController<FileChange> changes;
  late ProviderContainer container;
  var readiness = const DeviceReadiness(
    connectionId: 'first',
    status: .connected,
  );
  final readinessSource = Provider((ref) => readiness);

  setUp(() {
    directories = _Directories();
    changes = StreamController<FileChange>.broadcast(sync: true);
    readiness = const DeviceReadiness(
      connectionId: 'first',
      status: .connected,
    );
    container = ProviderContainer(
      overrides: [
        fileDirectoriesProvider.overrideWithValue(directories),
        fileChangesProvider.overrideWithValue(changes.stream),
        deviceReadinessProvider('device')
            .overrideWith((ref) => ref.watch(readinessSource)),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await changes.close();
  });

  test('只注入目录能力即可共享查询，释放最后订阅时撤销原请求', () async {
    final first = container.listen(fileDirectoryProvider(_target), (_, _) {});
    final second = container.listen(fileDirectoryProvider(_target), (_, _) {});
    await _flush(container);
    expect(directories.calls, hasLength(1));
    first.close();
    await _flush(container);
    expect(directories.calls.single.cancellation.isCancelled, isFalse);
    second.close();
    await _flush(container);
    expect(directories.calls.single.cancellation.isCancelled, isTrue);
    directories.complete(0);
  });

  test('连接代次改变时取消旧读取，旧回执不能恢复目录操作资格', () async {
    container.listen(fileDirectoryProvider(_target), (_, _) {});
    await _flush(container);
    readiness = const DeviceReadiness(
      connectionId: 'second',
      status: .connected,
    );
    container.invalidate(readinessSource);
    await _flush(container);
    expect(directories.calls, hasLength(2));
    expect(directories.calls.first.cancellation.isCancelled, isTrue);
    directories.complete(0);
    await _flush(container);
    expect(container.read(fileDirectoryProvider(_target)).verified, isFalse);
    directories.complete(1);
    await _flush(container);
    expect(container.read(fileDirectoryProvider(_target)).verified, isTrue);
  });

  test('目录变化只刷新匹配范围，刷新期间旧快照保留但不可操作', () async {
    container.listen(fileDirectoryProvider(_target), (_, _) {});
    await _flush(container);
    directories.complete(0);
    await _flush(container);
    changes.add(
      const FileChange(
        FileChangeKind.directory,
        deviceId: 'other',
        path: '/sdcard',
      ),
    );
    changes.add(
      const FileChange(
        FileChangeKind.directory,
        deviceId: 'device',
        path: '/other',
      ),
    );
    await _flush(container);
    expect(directories.calls, hasLength(1));
    changes.add(
      const FileChange(
        FileChangeKind.directory,
        deviceId: 'device',
        path: '/sdcard',
      ),
    );
    final pending = container.read(fileDirectoryProvider(_target));
    expect(pending.data, isNotNull);
    expect(pending.verified, isFalse);
    await _flush(container);
    directories.complete(1);
    await _flush(container);
    expect(container.read(fileDirectoryProvider(_target)).verified, isTrue);
  });

  test('恢复切换和错误归属都不能让旧快照重新成为已核验结果', () async {
    container.listen(fileDirectoryProvider(_target), (_, _) {});
    await _flush(container);
    directories.complete(0);
    await _flush(container);
    readiness = const DeviceReadiness(
      connectionId: 'first',
      status: .connected,
      recovering: true,
    );
    container.invalidate(readinessSource);
    await _flush(container);
    expect(container.read(fileDirectoryProvider(_target)).verified, isFalse);
    directories.calls[1].result.complete(
      const FileDirectorySnapshot(deviceId: 'other', path: '/sdcard'),
    );
    await _flush(container);
    final failed = container.read(fileDirectoryProvider(_target));
    expect(failed.verified, isFalse);
    expect(failed.data?.deviceId, 'device');
    expect(failed.error, isNotNull);
  });

  test('连接事件在设备列表更新前立即撤销目录资格', () async {
    container.listen(fileDirectoryProvider(_target), (_, _) {});
    await _flush(container);
    directories.complete(0);
    await _flush(container);
    changes.add(
      const FileChange(FileChangeKind.connection, deviceId: 'device'),
    );
    expect(container.read(fileDirectoryProvider(_target)).verified, isFalse);
    await _flush(container);
    changes.add(const FileChange(FileChangeKind.recovery));
    directories.complete(1);
    await _flush(container);
    expect(container.read(fileDirectoryProvider(_target)).verified, isFalse);
    directories.complete(2);
    await _flush(container);
    expect(container.read(fileDirectoryProvider(_target)).verified, isTrue);
  });
}

typedef _Call = ({
  FileDirectoryTarget target,
  FileCancellation cancellation,
  Completer<FileDirectorySnapshot> result,
});

class _Directories implements FileDirectories {
  final calls = <_Call>[];
  void complete(int index) {
    final call = calls[index];
    call.result.complete(
      FileDirectorySnapshot(
        deviceId: call.target.deviceId,
        path: call.target.path,
      ),
    );
  }

  @override
  Future<FileDirectorySnapshot> readDirectory(
    FileDirectoryTarget target, {
    FileCatalogFilter filter = .all,
    FileDirectorySort sort = .name,
    bool descending = false,
    int offset = 0,
    int limit = 10000,
    FileCancellation? cancellation,
  }) {
    final result = Completer<FileDirectorySnapshot>();
    calls.add((target: target, cancellation: cancellation!, result: result));
    return result.future;
  }
}

Future<void> _flush(ProviderContainer container) async {
  // 首次读取在 build 结束后排入微任务；等待本轮微任务交付后再排空 provider。
  await Future<void>.delayed(Duration.zero);
  await container.pump();
}
