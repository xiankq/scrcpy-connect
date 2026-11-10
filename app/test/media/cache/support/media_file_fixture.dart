import 'package:scrcpy_connect/models/file_failure.dart';
import 'package:scrcpy_connect/models/file_cancellation.dart';
import 'package:scrcpy_connect/models/file_stamp.dart';
import 'package:scrcpy_connect/models/file_directory_facts.dart';
import 'package:scrcpy_connect/services/file_read_executor.dart';
import 'package:scrcpy_connect/services/file_read_batch.dart';

import 'dart:io';

import 'package:scrcpy_connect/services/file_executor.dart';

final class MediaFileFixture implements FileExecutor, FileReadExecutor {
  @override
  Future<FileReadBatch> beginRead(
    String device, {
    required FileCancellation cancellation,
  }) async => _ReadBatch(this, device, cancellation);

  final bytes = List<int>.generate(10, (i) => i);
  int copies = 0;
  bool changed = false;
  Future<void> Function()? duringCopy, duringCommit;
  @override
  Future<FileStamp> stat(
    String device,
    String path, {
    required bool local,
    bool followStorageAlias = false,
    required FileCancellation cancellation,
  }) async {
    cancellation.check();
    if (local) {
      final value = await FileStat.stat(path);
      if (value.type == FileSystemEntityType.notFound) {
        throw const FileFailure('not_found', '目标不存在');
      }
      return FileStamp(
        mode: value.type == FileSystemEntityType.directory ? 0x4000 : 0x8000,
        size: value.size,
        modifiedSeconds: value.modified.millisecondsSinceEpoch ~/ 1000,
      );
    }
    return FileStamp(
      mode: 0x8000,
      size: bytes.length,
      modifiedSeconds: changed ? 2 : 1,
    );
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
    copies++;
    await File(temporary).writeAsBytes(bytes, flush: true);
    await duringCopy?.call();
    cancellation.check();
    onProgress(bytes.length);
    return bytes.length;
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
    cancellation.check();
    if (action == 'commit') {
      await File(path).rename(destination);
      await duringCommit?.call();
      return 'atomicNoReplace';
    }
    return 'released';
  }

  @override
  Future<FileDirectoryFacts> list(
    String device,
    String path, {
    required bool local,
    required int limit,
    required FileCancellation cancellation,
  }) => throw UnimplementedError();
}

final class _ReadBatch implements FileReadBatch {
  _ReadBatch(this.files, this.device, this.cancellation);
  final MediaFileFixture files;
  final String device;
  final FileCancellation cancellation;
  final parts = <String>{};
  @override
  Future<FileStamp> stat(String path) =>
      files.stat(device, path, local: false, cancellation: cancellation);
  @override
  Future<int> copy(
    String source,
    String temporary, {
    required FileStamp expected,
    required void Function(int) onProgress,
  }) {
    parts.add(temporary);
    return files.copy(
      device,
      source,
      temporary,
      push: false,
      expected: expected,
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> commit(String temporary, String destination) async {
    await files.mutate(
      device,
      'commit',
      temporary,
      destination: destination,
      local: true,
      cancellation: cancellation,
    );
    parts.remove(temporary);
  }

  @override
  Future<void> close() async {
    for (final path in parts.toList()) {
      final file = File(path);
      if (await file.exists()) await file.delete();
      parts.remove(path);
    }
  }
}
