import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/files/adb_file_executor.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';

void main() {
  test('本机文件查询只借用原生文件能力，不解析连接或创建 ADB 客户端', () async {
    final native = _LocalFiles();
    final files = AdbFileExecutor(
      localFiles: native,
      resolveConnection: (_) async => throw StateError('本机查询没有设备连接'),
      fileScopeId: 'scope',
      fileScopeKey: 'owner',
    );
    addTearDown(files.close);
    final stamp = await files.stat(
      '',
      '/文件.txt',
      local: true,
      cancellation: FileCancellation(),
    );
    expect(stamp.identity, 'original-file');
    expect(stamp.size, 42);
    expect(stamp.modifiedResolutionNanos, 1000000000);
    final facts = await files.list(
      '',
      '/目录',
      local: true,
      limit: 3,
      cancellation: FileCancellation(),
    );
    expect(facts.entries.single.nameBytes, [0xff, 0x61]);
    expect(facts.entries.single.stamp?.identity, 'original-file');
    expect(facts.truncated, isTrue);
    expect(native.paths, ['/文件.txt', '/目录']);
    expect(native.limit, 3);
    await files.close();
    await expectLater(
      files.stat('', '/late', local: true, cancellation: FileCancellation()),
      throwsA(isA<FileFailure>()),
    );
    expect(native.paths, hasLength(2));
  });
}

final class _LocalFiles implements NativeAdbLocalFileApi {
  final paths = <String>[];
  int? limit;
  static const stamp = AdbFileExecutionStamp(
    identity: 'original-file',
    mode: 0x81a4,
    size: 42,
    modifiedSeconds: 100,
    modifiedNanos: 0,
    nanosecondPrecision: false,
  );

  @override
  Future<AdbFileExecutionStamp> localFileStat(Uint8List path) async {
    paths.add(utf8.decode(path));
    return stamp;
  }

  @override
  Future<AdbLocalFileFacts> localFileList(Uint8List path, int limit) async {
    paths.add(utf8.decode(path));
    this.limit = limit;
    return AdbLocalFileFacts([
      AdbFileExecutionEntry(name: [0xff, 0x61], stamp: stamp),
    ], truncated: true);
  }
}
