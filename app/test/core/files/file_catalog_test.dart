import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_catalog.dart';
import 'package:scrcpy_connect/core/files/file_executor.dart';
import 'package:scrcpy_connect/core/files/models/file_directory_facts.dart';
import 'package:scrcpy_connect/core/files/models/file_entry_fact.dart';
import 'package:scrcpy_connect/core/files/models/file_stamp.dart';

void main() {
  test('相册优先读照片目录及子目录，随后仍检查自定义目录', () async {
    final executor = _MediaDirectories();
    final catalog = FileCatalog(executor);
    addTearDown(catalog.close);

    final completed = catalog.events.firstWhere(
      (_) => executor.visited.length == 4,
    );
    final scan = await catalog.startScan('phone');
    await completed;
    final result = await catalog.readScan(scan.target);
    expect(executor.visited, [
      '/sdcard',
      '/sdcard/DCIM',
      '/sdcard/DCIM/Camera',
      '/sdcard/Archive',
    ]);
    expect(
      result.items.map((item) => item.name),
      containsAll(['camera.jpg', 'saved.jpg']),
    );
  });
}

class _MediaDirectories implements FileExecutor {
  final visited = <String>[];
  static const directory = FileStamp(mode: 0x4000, size: 0, modifiedSeconds: 0);
  static const image = FileStamp(mode: 0x8000, size: 8, modifiedSeconds: 1);

  @override
  Future<FileStamp> stat(
    String device,
    String path, {
    required bool local,
    bool followStorageAlias = false,
    required FileCancellation cancellation,
  }) async => directory;

  @override
  Future<FileDirectoryFacts> list(
    String device,
    String path, {
    required bool local,
    required int limit,
    required FileCancellation cancellation,
  }) async {
    visited.add(path);
    final children = switch (path) {
      '/sdcard' => {'Archive': directory, 'DCIM': directory},
      '/sdcard/DCIM' => {'Camera': directory},
      '/sdcard/DCIM/Camera' => {'camera.jpg': image},
      '/sdcard/Archive' => {'saved.jpg': image},
      _ => throw StateError('测试目录不存在'),
    };
    return FileDirectoryFacts([
      for (final entry in children.entries)
        FileEntryFact(
          nameBytes: Uint8List.fromList(utf8.encode(entry.key)),
          stamp: entry.value,
        ),
    ], truncated: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
