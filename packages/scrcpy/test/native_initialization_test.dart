import 'dart:io';
import 'dart:isolate';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';

void main() {
  test('同步加载失败后允许重新选择有效的默认动态库', () async {
    final recovered = await Isolate.run(() async {
      final root = await Directory.systemTemp.createTemp('scrcpy-load-');
      try {
        Object? failure;
        try {
          await createNativeScrcpyAdbApi(
            libraryPath: File.fromUri(root.uri.resolve('missing.so')).path,
          );
        } catch (error) {
          failure = error;
        }
        if (failure == null) throw StateError('不存在的库文件未被拒绝');
        final api = await createNativeScrcpyAdbApi();
        return api is NativeAdbServerApi && api is NativeAdbConnectionApi;
      } finally {
        await root.delete(recursive: true);
      }
    });
    expect(recovered, isTrue);
  });

  test('并发初始化及初始化完成后均拒绝另一条显式库路径', () async {
    final root = await Directory.systemTemp.createTemp('scrcpy-library-');
    addTearDown(() => root.delete(recursive: true));
    final other = File.fromUri(root.uri.resolve('other.so')).path;
    final mismatch = throwsA(
      isA<ScrcpyException>().having(
        (error) => error.code,
        'code',
        'native_library_mismatch',
      ),
    );
    final first = createNativeScrcpyAdbApi();
    await Future.wait([
      first,
      expectLater(createNativeScrcpyAdbApi(libraryPath: other), mismatch),
    ]);
    final api = await first;
    await expectLater(listNativeScrcpyServers(libraryPath: other), mismatch);
    expect(identical(await createNativeScrcpyAdbApi(), api), isTrue);
    expect(await listNativeScrcpyServers(), isEmpty);
  });
}
