import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';
import 'package:scrcpy_connect/core/application/application_session_provider.dart';
import 'package:scrcpy_connect/core/application/application_status_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';

import 'file_cancellation.dart';
import 'file_directory.dart';
import 'file_paths.dart';

part 'file_directory_notifier.freezed.dart';
part 'file_directory_notifier.g.dart';

@freezed
abstract class FileDirectoryState with _$FileDirectoryState {
  const FileDirectoryState._();
  const factory FileDirectoryState({
    FileDirectorySnapshot? data,
    @Default(true) bool loading,
    Object? error,
    @Default(0) int revision,
  }) = _FileDirectoryState;

  bool get verified => !loading && error == null && data != null;
}

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
    final session = ref.watch(applicationSessionProvider);
    final source = session.dependencies.directories;
    if (!identical(_source, source)) _lastSuccess = null;
    _source = source;
    ref.watch(
      deviceListProvider.select((state) {
        final device = state.devices
            .where((item) => item.id == target.deviceId)
            .firstOrNull;
        return (device?.connectionId, device?.status);
      }),
    );
    ref.watch(
      applicationStatusProvider.select((state) => state.reconciliationPending),
    );
    final generation = ++_generation;
    _pending = null;
    _dirty = false;
    final cancellation = _cancellation = FileCancellation();
    final subscription = session.events.listen((event) {
      if (!_current(generation)) return;
      final type = event['type'];
      if (type is! String || type == 'session.frame') return;
      final data = event['data'];
      final owner =
          event['deviceId'] ?? (data is Map ? data['deviceId'] : null);
      if (owner != null && owner != target.deviceId) return;
      if (type.startsWith('state.resync') ||
          type == 'devices.changed' ||
          type.startsWith('device.') ||
          type == 'connections.stopped') {
        unawaited(refresh());
      }
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
