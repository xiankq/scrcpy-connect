import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_directory_notifier.dart';
import 'package:scrcpy_connect/core/files/file_mutations.dart';
import 'package:scrcpy_connect/core/files/file_paths.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';

import 'models/file_action_state.dart';

part 'file_actions_notifier.g.dart';

/// 单个文件页面的操作编排；离页撤销回执交付，不取消已登记的核心操作。
@riverpod
class FileActionsNotifier extends _$FileActionsNotifier {
  int _generation = 0;
  late FileMutations _mutations;
  late FileTransfers _transfers;
  late FileDirectories _directories;
  late DeviceReadiness _readiness;

  @override
  FileActionState build(FileDirectoryTarget target, {required Object scope}) {
    final generation = ++_generation;
    _mutations = ref.watch(fileMutationsProvider);
    _transfers = ref.watch(fileTransfersProvider);
    _directories = ref.watch(fileDirectoriesProvider);
    _readiness = ref.watch(deviceReadinessProvider(target.deviceId));
    ref.onDispose(() {
      if (_generation == generation) _generation++;
    });
    return const FileActionState();
  }

  bool _current(int generation) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(deviceReadinessProvider(target.deviceId)) == _readiness &&
      identical(ref.read(fileMutationsProvider), _mutations) &&
      identical(ref.read(fileTransfersProvider), _transfers) &&
      identical(ref.read(fileDirectoriesProvider), _directories);

  Future<bool> createDirectory(String name) => _run(
    () => _mutations.createDirectory(
      target.deviceId,
      p.posix.join(target.path, FilePaths.name(name)),
    ),
  );

  Future<bool> rename(FileMutationSelection source, String name) => _run(
    () => _mutations.rename(
      target.deviceId,
      source,
      destination: p.posix.join(
        p.posix.dirname(source.path),
        FilePaths.name(name),
      ),
    ),
  );

  Future<bool> delete(List<FileMutationSelection> sources) =>
      _run(() => _mutations.delete(target.deviceId, sources));

  Future<bool> send(List<FileTransferSelection> items) => _run(() async {
    await _transfers.startTransfer(
      FileTransferPlan(
        deviceId: target.deviceId,
        direction: .push,
        items: items,
      ),
    );
  }, refreshDirectory: false);

  Future<bool> _run(
    Future<void> Function() action, {
    bool refreshDirectory = true,
  }) async {
    if (!ref.mounted || state.busy) return false;
    final generation = _generation;
    if (!ref.read(deviceReadinessProvider(target.deviceId)).ready ||
        !ref.read(fileDirectoryProvider(target)).verified) {
      state = const FileActionState(error: '设备已断开或目录尚未重新核验，请重连后再试。');
      return false;
    }
    state = const FileActionState(busy: true);
    try {
      if (!_current(generation)) return false;
      await action();
      if (!_current(generation)) return false;
      if (refreshDirectory) {
        unawaited(ref.read(fileDirectoryProvider(target).notifier).refresh());
      }
      return true;
    } catch (error) {
      if (_current(generation)) state = FileActionState(error: '$error');
      return false;
    } finally {
      if (_current(generation) && state.busy) state = const FileActionState();
    }
  }
}
