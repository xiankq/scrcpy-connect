import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';

Uint8List _path(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final factory in <String, Future<LocalFiles> Function()>{
    'adb': () => createNativeLocalFiles(),
    'scrcpy': () => createNativeScrcpyLocalFiles(),
  }.entries) {
    group('${factory.key} 实际动态库的本机文件能力', () {
      late Directory directory;
      late LocalFiles files;
      late LocalFileScope scope;

      setUp(() async {
        directory = await Directory.systemTemp.createTemp('local-files-sdk-');
        files = await factory.value();
        scope = await files.openScope(
          scopeKey: directory.path,
          allowedRoots: [_path(directory.path)],
        );
      });

      tearDown(() async {
        await files.close();
        await directory.delete(recursive: true);
      });

      test('复制、禁止覆盖提交与租约关闭保留真实结果', () async {
        final source = File('${directory.path}/中文原件');
        final part = File('${directory.path}/part');
        final destination = File('${directory.path}/saved');
        final bytes = List.generate(200000, (index) => index % 251);
        await source.writeAsBytes(bytes, flush: true);
        final before = await scope.stat(_path(source.path));
        final copy = await scope.copy(
          source: LocalFileEndpoint.path(_path(source.path)),
          target: LocalFileEndpoint.part(_path(part.path)),
          expectedSource: before.identity,
          maxBytes: bytes.length,
          timeout: const Duration(seconds: 5),
        );
        expect(copy.bytes, bytes.length);
        final published = await scope.commit(
          copy,
          _path(destination.path),
          expectedIdentity: copy.identity,
        );
        await copy.close();
        expect(published.inode, copy.identity.inode);
        expect(await part.exists(), isFalse);
        expect(await destination.readAsBytes(), bytes);
        expect(await source.readAsBytes(), bytes);

        final second = await scope.copy(
          source: LocalFileEndpoint.path(_path(source.path)),
          target: LocalFileEndpoint.part(_path(part.path)),
          maxBytes: bytes.length,
          timeout: const Duration(seconds: 5),
        );
        await expectLater(
          scope.commit(
            second,
            _path(destination.path),
            expectedIdentity: second.identity,
          ),
          throwsA(isA<LocalFileException>()),
        );
        expect(await destination.readAsBytes(), bytes);
        expect(await part.readAsBytes(), bytes);
        await second.close();
        expect(await part.exists(), isFalse);
        expect(await destination.readAsBytes(), bytes);
      });

      test('原 isolate 退出后按资源名称接管，先回收原片段再准入', () async {
        final rootPath = directory.path;
        final implementation = factory.key;
        await File('$rootPath/source').writeAsString('isolate-owned');
        await Isolate.run(() => _leaveCopy(implementation, rootPath));
        expect(await File('$rootPath/part').readAsString(), 'isolate-owned');
        final recovered = await files.openScope(
          scopeKey: '$rootPath/recovery',
          allowedRoots: [_path(rootPath)],
        );
        expect(await File('$rootPath/part').exists(), isFalse);
        final copy = await recovered.copy(
          source: LocalFileEndpoint.path(_path('$rootPath/source')),
          target: LocalFileEndpoint.part(_path('$rootPath/part')),
          maxBytes: 100,
          timeout: const Duration(seconds: 5),
        );
        await recovered.commit(
          copy,
          _path('$rootPath/saved'),
          expectedIdentity: copy.identity,
        );
        await recovered.close();
        expect(await File('$rootPath/saved').readAsString(), 'isolate-owned');
      });
    });
  }

  test('双库反向初始化后，子 isolate 与父 isolate 退出均不关闭存活通道', () async {
    final directory = await Directory.systemTemp.createTemp('local-files-sdk-');
    final rootPath = directory.path;
    try {
      await Isolate.run(() => _probeBothLibraries('$rootPath/outer', true));
      // 外层 isolate 也已退出；主 isolate 的两个动态库仍须正常回传结果。
      await _probeBothLibraries('$rootPath/main', false);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

Future<void> _probeBothLibraries(String rootPath, bool spawnChild) async {
  // 与上方用例相反，确保 FRB 首次登记不依赖特定动态库顺序。
  final scrcpy = await createNativeScrcpyLocalFiles();
  final adb = await createNativeLocalFiles();
  try {
    if (spawnChild) {
      final childPath = '$rootPath/child';
      await Isolate.run(() => _probeBothLibraries(childPath, false));
    }
    for (final entry in {'scrcpy': scrcpy, 'adb': adb}.entries) {
      final directory = await Directory('$rootPath/${entry.key}')
          .create(recursive: true);
      final source = await File('${directory.path}/source')
          .writeAsString('live');
      final scope = await entry.value.openScope(
        scopeKey: directory.path,
        allowedRoots: [_path(directory.path)],
      );
      try {
        final stat = await scope.stat(_path(source.path));
        if (stat.identity.size != BigInt.from(4)) {
          throw StateError('子 isolate 退出后读取结果错误');
        }
      } finally {
        await scope.close();
      }
    }
  } finally {
    await scrcpy.close();
    await adb.close();
  }
}

Future<void> _leaveCopy(String implementation, String rootPath) async {
  final files = implementation == 'adb'
      ? await createNativeLocalFiles()
      : await createNativeScrcpyLocalFiles();
  final scope = await files.openScope(
    scopeKey: '$rootPath/recovery',
    allowedRoots: [_path(rootPath)],
  );
  await scope.copy(
    source: LocalFileEndpoint.path(_path('$rootPath/source')),
    target: LocalFileEndpoint.part(_path('$rootPath/part')),
    maxBytes: 100,
    timeout: const Duration(seconds: 5),
  );
  // 明确不关闭；原 isolate 消失后，由同库新所有者完成精确回收。
}
