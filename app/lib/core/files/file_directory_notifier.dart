import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_changes_provider.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_paths.dart';
import 'package:scrcpy_connect/core/files/models/file_directory_state.dart';

export 'package:scrcpy_connect/core/files/models/file_directory_state.dart';

part 'file_directory_notifier.g.dart';

/// 同一目录共享读取；失效立即撤销操作资格，在途旧回执不能恢复资格。
@riverpod
class FileDirectoryNotifier extends _$FileDirectoryNotifier {
  Future<void>? _pending;
  bool _dirty = false;
  int _generation = 0;
  FileDirectories? _source;
  FileDirectoryState? _lastSuccess;
  late FileCancellation _cancellation;

  @override
  FileDirectoryState build(FileDirectoryTarget target) {
    final source = ref.watch(fileDirectoriesProvider);
    if (!identical(_source, source)) _lastSuccess = null;
    _source = source;
    ref.watch(deviceReadinessProvider(target.deviceId));
    final generation = ++_generation;
    _pending = null;
    _dirty = false;
    final cancellation = _cancellation = FileCancellation();
    final subscription = ref.watch(fileChangesProvider).listen((event) {
      if (!_current(generation) || event.kind == FileChangeKind.transfer) {
        return;
      }
      if (event.deviceId != null && event.deviceId != target.deviceId) return;
      if (event case FileChange(
        kind: FileChangeKind.directory,
        path: final path?,
      )) {
        final currentPath = FilePaths.remote(target.path);
        // 写入子目录也会改变它在上级列表中的时间戳。
        if (path != currentPath && p.posix.dirname(path) != currentPath) {
          return;
        }
      }
      // 连接事件先撤销目录资格；设备列表的异步刷新尚未完成也不能沿用旧核验。
      unawaited(refresh());
    });
    ref.onDispose(() {
      if (_generation == generation) _generation++;
      cancellation.cancel();
      unawaited(subscription.cancel());
    });
    scheduleMicrotask(() {
      if (_current(generation)) unawaited(refresh());
    });
    return FileDirectoryState(
      data: _lastSuccess?.data,
      revision: _lastSuccess?.revision ?? 0,
    );
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  Future<void> refresh() {
    if (!ref.mounted) return Future.value();
    _dirty = true;
    if (!state.loading) state = state.copyWith(loading: true, error: null);
    final generation = _generation;
    return _pending ??= Future<void>.microtask(() => _drain(generation));
  }

  Future<void> _drain(int generation) async {
    if (!_current(generation)) return;
    final source = _source!, cancellation = _cancellation;
    try {
      while (_current(generation) && _dirty) {
        _dirty = false;
        state = state.copyWith(loading: true, error: null);
        try {
          final result = await source.readDirectory(
            target,
            cancellation: cancellation,
          );
          if (!_current(generation)) return;
          if (_dirty) continue;
          if (result.deviceId != target.deviceId ||
              result.path != FilePaths.remote(target.path)) {
            throw const RequestFailure('invalid_data', '目录结果归属无法核验，请重新检查。');
          }
          final next = FileDirectoryState(
            data: result,
            loading: false,
            revision: state.revision + 1,
          );
          _lastSuccess = next;
          state = next;
        } catch (failure) {
          if (!_current(generation)) return;
          if (_dirty) continue;
          state = state.copyWith(loading: false, error: failure);
        }
      }
    } finally {
      if (_current(generation)) _pending = null;
    }
  }
}
