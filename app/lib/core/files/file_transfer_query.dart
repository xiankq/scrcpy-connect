import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'file_transfer_query.freezed.dart';

@freezed
abstract class FileTransferQueryState<T> with _$FileTransferQueryState<T> {
  const FileTransferQueryState._();
  const factory FileTransferQueryState({
    T? data,
    @Default(true) bool loading,
    Object? error,
  }) = _FileTransferQueryState<T>;

  bool get verified => !loading && error == null && data != null;
}

/// 查询失效时立即撤销核验资格，合并在途刷新，并丢弃失效前开始的回执。
final class FileTransferQuery<T> {
  FileTransferQuery({
    required this._read,
    required this._current,
    required this._update,
    required Stream<Map<String, Object?>> events,
  }) {
    _subscription = events.listen((event) {
      final type = event['type'];
      if (type is String &&
          (type.startsWith('transfers.') ||
              type.startsWith('state.resync') ||
              type.startsWith('device.') ||
              type == 'devices.changed' ||
              type == 'connections.stopped')) {
        unawaited(refresh());
      }
    });
    scheduleMicrotask(() {
      if (!_closed) unawaited(refresh());
    });
  }

  final Future<T> Function() _read;
  final FileTransferQueryState<T> Function() _current;
  final void Function(FileTransferQueryState<T>) _update;
  late final StreamSubscription<Map<String, Object?>> _subscription;
  Future<void>? _pending;
  bool _dirty = false;
  bool _closed = false;

  Future<void> refresh() {
    if (_closed) return Future.value();
    _dirty = true;
    final state = _current();
    if (!state.loading) _update(state.copyWith(loading: true, error: null));
    return _pending ??= Future<void>.microtask(_drain);
  }

  Future<void> _drain() async {
    try {
      while (!_closed && _dirty) {
        _dirty = false;
        try {
          final result = await _read();
          if (_closed) return;
          if (_dirty) continue;
          _update(FileTransferQueryState(data: result, loading: false));
        } catch (error) {
          if (_closed) return;
          if (_dirty) continue;
          _update(_current().copyWith(loading: false, error: error));
        }
      }
    } finally {
      _pending = null;
    }
  }

  void close() {
    _closed = true;
    unawaited(_subscription.cancel());
  }
}
