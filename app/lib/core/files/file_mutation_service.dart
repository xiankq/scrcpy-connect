import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_stamp.dart';
import 'package:scrcpy_connect/core/files/file_executor.dart';
import 'package:scrcpy_connect/core/files/file_mutations.dart';

import 'dart:async';

import 'package:scrcpy_connect/core/files/file_paths.dart';

/// 一次用户变更固定一条设备连接，持有在途及迟到批次直至真正释放。
final class FileMutationService implements FileMutations {
  FileMutationService(this._executor);

  final FileExecutor _executor;
  final _operations = <_MutationWork>{};
  final _deviceStops = <String, Future<void>>{};
  bool _closed = false;
  Future<void>? _closing;

  @override
  Future<void> createDirectory(String device, String path) =>
      _run(device, .mkdir, [(path: path, expected: null)]);

  @override
  Future<void> rename(
    String device,
    FileMutationSelection source, {
    required String destination,
  }) => _run(device, .rename, [source], destination: destination);

  @override
  Future<void> delete(String device, List<FileMutationSelection> sources) =>
      _run(device, .delete, sources);

  Future<void> _run(
    String device,
    _MutationAction action,
    List<({String path, FileStamp? expected})> sources, {
    String destination = '',
  }) async {
    if (action != .mkdir &&
        sources.any(
          (source) => source.expected?.identity?.isNotEmpty != true,
        )) {
      throw const FileFailure('source_changed', '缺少所选文件的身份，请重新选择。');
    }
    if (_closed) throw const FileFailure('closed', '文件变更已关闭。');
    if (_deviceStops.containsKey(device) ||
        _operations.any(
          (job) => job.device == device && job.cancellation.isCancelled,
        )) {
      throw const FileFailure('mutation_cleanup_unconfirmed', '此设备的旧变更尚未确认释放。');
    }
    final execution = _executor;
    if (execution is! FileMutationExecutor) {
      throw const FileFailure('unsupported', '执行器不能固定文件变更所属的连接。');
    }
    if (sources.isEmpty || sources.length > 1000) {
      throw const FileFailure('invalid_argument', '文件选择必须为1至1000项。');
    }
    final selected = [
      for (final (:path, :expected) in sources)
        (path: FilePaths.remote(path), expected: expected),
    ];
    final target = action == .rename ? FilePaths.remote(destination) : '';
    final job = _MutationWork(device);
    _operations.add(job);
    try {
      job.opening = (execution as FileMutationExecutor).beginMutation(
        device,
        cancellation: job.cancellation,
      );
      final batch = job.batch = await job.opening!;
      job.cancellation.check();
      for (final (:path, :expected) in selected) {
        job.cancellation.check();
        await batch.mutate(
          action.name,
          path,
          destination: target,
          expected: expected,
        );
      }
      job.cancellation.check();
    } finally {
      try {
        await job.batch?.close();
        _operations.remove(job);
      } catch (error) {
        job.cancellation.cancel();
        throw FileFailure(
          'mutation_cleanup_unconfirmed',
          '文件变更结果不能重放，资源尚未确认释放：$error',
        );
      } finally {
        job.finished.complete();
      }
    }
  }

  /// 同步封住本设备准入，确认原批次关闭后才解除屏障。
  Future<void> cancelDevice(String device) {
    if (_deviceStops[device] case final pending?) return pending;
    final done = Completer<void>();
    _deviceStops[device] = done.future;
    final selected = _operations.where((job) => job.device == device).toList();
    for (final job in selected) {
      job.cancellation.cancel();
    }
    unawaited(
      Future.wait(selected.map(_closeOperation)).then<void>(
        (_) {
          _deviceStops.remove(device);
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          _deviceStops.remove(device);
          done.completeError(error, stack);
        },
      ),
    );
    return done.future;
  }

  Future<void> _closeOperation(_MutationWork job) async {
    job.cancellation.cancel();
    final opening = job.opening;
    if (opening != null) {
      try {
        job.batch ??= await opening;
      } catch (_) {
        // 创建失败没有交付执行句柄；原错误仍由请求返回。
      }
    }
    try {
      await job.batch?.close();
    } catch (error) {
      throw FileFailure(
        'mutation_cleanup_unconfirmed',
        '文件变更仍在清理，请重试停止：$error',
      );
    }
    await job.finished.future;
    _operations.remove(job);
  }

  Future<void> close() {
    _closed = true;
    return _closing ??= (() async {
      final selected = _operations.toList();
      for (final job in selected) {
        job.cancellation.cancel();
      }
      await Future.wait(selected.map(_closeOperation));
    })().whenComplete(() => _closing = null);
  }
}

enum _MutationAction { mkdir, rename, delete }

final class _MutationWork {
  _MutationWork(this.device);
  final String device;
  final cancellation = FileCancellation();
  final finished = Completer<void>();
  Future<FileMutationBatch>? opening;
  FileMutationBatch? batch;
}
