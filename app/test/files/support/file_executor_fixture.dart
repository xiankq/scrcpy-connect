import 'package:scrcpy_connect/models/file_failure.dart';
import 'package:scrcpy_connect/models/file_cancellation.dart';
import 'package:scrcpy_connect/models/file_stamp.dart';
import 'package:scrcpy_connect/models/file_entry_fact.dart';
import 'package:scrcpy_connect/models/file_directory_facts.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:scrcpy_connect/services/file_executor.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> until(bool Function() ready) async {
  final limit = DateTime.now().add(const Duration(seconds: 3));
  while (!ready()) {
    if (DateTime.now().isAfter(limit)) {
      throw StateError('timed out waiting for task');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

const regular = FileStamp(mode: 0x8000, size: 4, modifiedSeconds: 3);
const directory = FileStamp(mode: 0x4000, size: 0, modifiedSeconds: 3);
FileEntryFact entry(String name, FileStamp stamp) => FileEntryFact(
  nameBytes: Uint8List.fromList(utf8.encode(name)),
  stamp: stamp,
);

class FixtureExecutor implements FileExecutor {
  final stamps = <String, FileStamp>{'/sdcard': directory};
  final children = <String, List<FileEntryFact>>{};
  final contents = <String, List<int>>{};
  final calls = <String>[];
  Completer<void>? copyStarted;
  bool blockCopy = false, unknownCommit = false, blockList = false;
  final denied = <String>{};
  Future<void> Function(String, String)? beforeCommit;
  @override
  Future<FileStamp> stat(
    String device,
    String path, {
    required bool local,
    bool followStorageAlias = false,
    required FileCancellation cancellation,
  }) async {
    cancellation.check();
    calls.add('stat:$path');
    final stamp = stamps[path];
    if (stamp == null) throw const FileFailure('not_found', 'absent');
    return stamp;
  }

  @override
  Future<FileDirectoryFacts> list(
    String device,
    String path, {
    required bool local,
    required int limit,
    required FileCancellation cancellation,
  }) async {
    cancellation.check();
    calls.add('list:$path');
    if (blockList) {
      await cancellation.whenCancelled;
      cancellation.check();
    }
    if (denied.contains(path)) {
      throw const FileFailure('permission_denied', 'denied');
    }
    final list = children[path] ?? [];
    return FileDirectoryFacts(
      list.take(limit).toList(),
      truncated: list.length > limit,
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
    calls.add('copy:$temporary');
    if (copyStarted != null && !copyStarted!.isCompleted) {
      copyStarted!.complete();
    }
    if (blockCopy) {
      await cancellation.whenCancelled;
      cancellation.check();
    }
    require(stamps[source] == expected, 'source stamp changed');
    contents[temporary] = [1, 2, 3, 4];
    stamps[temporary] = regular;
    onProgress(4);
    return 4;
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
    calls.add('$action:$path');
    if (action == 'releasePart') return 'released';
    if (action == 'mkdir') {
      if (stamps.containsKey(path)) {
        throw const FileFailure('conflict', 'exists');
      }
      stamps[path] = directory;
      return 'directoryCreated';
    }
    if (action == 'commit') {
      await beforeCommit?.call(path, destination);
      if (!replace && stamps.containsKey(destination)) {
        throw const FileFailure('conflict', 'exists');
      }
      if (unknownCommit) {
        throw const FileFailure('disconnected', 'lost receipt');
      }
      contents[destination] = contents.remove(path)!;
      stamps[destination] = stamps.remove(path)!;
      return 'atomicNoReplace';
    }
    throw StateError('unexpected mutation $action');
  }
}

Future<void> rejects(Future<Object?> Function() action, String code) async {
  try {
    await action();
  } on FileFailure catch (e) {
    require(e.code == code, 'expected $code, got ${e.code}');
    return;
  }
  throw StateError('expected $code');
}
