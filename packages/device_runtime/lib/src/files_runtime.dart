import 'dart:async';
import 'dart:convert';

import 'package:device_files/device_files.dart';

import 'rust/file_api.dart' as native;

/// Keeps file facts typed and copies large payloads between native file handles.
final class NativeFileExecutor implements RemoteFileExecutor {
  const NativeFileExecutor();
  native.FileExecutionRequest _request(
    String action,
    String device,
    String path, {
    String destination = '',
    bool local = false,
    bool followStorageAlias = false,
    int limit = 1,
    bool push = false,
    bool replace = false,
    FileStamp? expected,
  }) => native.FileExecutionRequest(
    action: action,
    deviceId: device,
    path: path,
    destination: destination,
    local: local,
    followStorageAlias: followStorageAlias,
    limit: limit,
    push: push,
    replace: replace,
    expected: expected == null
        ? null
        : native.FileExecutionStamp(
            mode: expected.mode,
            size: BigInt.from(expected.size),
            modifiedSeconds: expected.modifiedSeconds,
            modifiedNanos: expected.modifiedNanos,
          ),
  );
  FileStamp _stamp(native.FileExecutionStamp stamp) => FileStamp(
    mode: stamp.mode,
    size: stamp.size.toInt(),
    modifiedSeconds: stamp.modifiedSeconds.toInt(),
    modifiedNanos: stamp.modifiedNanos,
  );

  Stream<native.FileExecutionEvent> _execute(
    native.FileExecutionRequest request,
    FileCancellation cancellation,
  ) async* {
    cancellation.check();
    final id = await native.fileExecute(request: request);
    Future<void>? cancelling;
    final stopListening = cancellation.onCancel(() {
      cancelling = Future<void>.sync(() => native.fileCancel(operationId: id));
      unawaited(cancelling!.catchError((Object _) {}));
    });
    try {
      cancellation.check();
      while (true) {
        final event = await native.fileNext(operationId: id);
        cancellation.check();
        if (event == null) {
          throw const FileFailure('result_unknown', '执行结束但未取得完成回执。');
        }
        if (event.kind == 'error') {
          throw FileFailure(
            event.errorCode ?? 'file_execution_failed',
            event.errorMessage ?? '文件执行失败。',
          );
        }
        yield event;
        if (event.kind == 'done') break;
      }
    } finally {
      stopListening();
      if (cancelling != null) {
        await cancelling;
      } else {
        await native.fileCancel(operationId: id);
      }
    }
  }

  @override
  Future<FileStamp> stat(
    String device,
    String path, {
    required bool local,
    bool followStorageAlias = false,
    required FileCancellation cancellation,
  }) async {
    FileStamp? stamp;
    await for (final event in _execute(
      _request(
        'stat',
        device,
        path,
        local: local,
        followStorageAlias: followStorageAlias,
      ),
      cancellation,
    )) {
      if (event.stamp != null) stamp = _stamp(event.stamp!);
    }
    if (stamp == null) throw const FileFailure('invalid_metadata', '未取得文件元数据。');
    return stamp;
  }

  @override
  Future<DirectoryFacts> list(
    String device,
    String path, {
    required bool local,
    required int limit,
    required FileCancellation cancellation,
  }) async {
    final entries = <FileEntryFact>[];
    var truncated = false;
    await for (final event in _execute(
      _request('list', device, path, local: local, limit: limit),
      cancellation,
    )) {
      entries.addAll(
        event.entries.map(
          (e) => FileEntryFact(
            nameBytes: e.name,
            stamp: e.stamp == null ? null : _stamp(e.stamp!),
            error: e.errorCode == null
                ? null
                : FileFailure(e.errorCode!, e.errorMessage ?? ''),
          ),
        ),
      );
      if (entries.length > limit) {
        throw const FileFailure('invalid_metadata', '目录结果超过请求上限。');
      }
      if (event.kind == 'done') truncated = event.truncated;
    }
    return DirectoryFacts(entries, truncated: truncated);
  }

  @override
  Future<int> copy(
    String device,
    String source,
    String temporary, {
    required bool push,
    required FileStamp expected,
    required FileCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    var transferred = 0;
    await for (final event in _execute(
      _request(
        'copy',
        device,
        source,
        destination: temporary,
        push: push,
        expected: expected,
      ),
      cancellation,
    )) {
      if (event.kind == 'progress') {
        transferred = event.transferred.toInt();
        onProgress(transferred);
      }
    }
    return transferred;
  }

  @override
  Future<String> mutate(
    String device,
    String action,
    String path, {
    String destination = '',
    bool local = false,
    bool replace = false,
    required FileCancellation cancellation,
  }) async {
    String? receipt;
    await for (final event in _execute(
      _request(
        action,
        device,
        path,
        destination: destination,
        local: local,
        replace: replace,
      ),
      cancellation,
    )) {
      if (event.saveMode != null) receipt = event.saveMode;
    }
    if (receipt == null) {
      throw const FileFailure('result_unknown', '没有取得文件操作回执，请核对目标。');
    }
    return receipt;
  }
}

final class NativeFileCache implements RemoteFileCache {
  const NativeFileCache();
  @override
  Future<String> reserve(List<FileCacheReservation> reservations) =>
      native.fileCacheReserve(
        items: reservations
            .map(
              (r) => native.FileCacheItem(
                path: r.path,
                bytes: BigInt.from(r.bytes),
              ),
            )
            .toList(),
      );
  @override
  Future<void> release(String lease) => native.fileCacheRelease(leaseId: lease);
}

final class NativeFilePublicationLeases implements FilePublicationLeases {
  const NativeFilePublicationLeases();
  Future<Map<String, Object?>> _call(
    String phase,
    String share,
    Map<String, Object?> control,
  ) async => Map<String, Object?>.from(
    jsonDecode(
      await native.fileSharePublication(
        phase: phase,
        shareId: share,
        controlJson: jsonEncode(control),
      ),
    ) as Map,
  );
  @override
  Future<Map<String, Object?>?> begin(
    String share,
    Map<String, Object?> request,
  ) async {
    final result = await _call('begin', share, request);
    return result['receipt'] == null
        ? null
        : Map<String, Object?>.from(result['receipt']! as Map);
  }

  @override
  Future<void> finish(
    String share,
    Map<String, Object?>? receipt, {
    bool definitelyUnpublished = false,
  }) async {
    await _call(definitelyUnpublished ? 'abort' : 'finish', share, {
      'receipt': receipt,
    });
  }

  @override
  Future<Map<String, Object?>> reconcile(
    Map<String, Object?> durableReferences,
  ) => _call('reconcile', '', durableReferences);
}
