import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/files/sharing/share_coordinator.dart';

const _share = '00000000-0000-4000-8000-000000000001';

/// 夹具只借出真实 Linux FD；导入仍走生产 scrcpy 同库能力和应用账本。
final class _Descriptors {
  final _library = DynamicLibrary.process();
  late final _allocate = _library
      .lookupFunction<
        Pointer<Void> Function(IntPtr, IntPtr),
        Pointer<Void> Function(int, int)
      >('calloc');
  late final _free = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  late final _open = _library
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Int32),
        int Function(Pointer<Uint8>, int)
      >('open');
  late final _pipe = _library
      .lookupFunction<
        Int32 Function(Pointer<Int32>),
        int Function(Pointer<Int32>)
      >('pipe');
  late final _write = _library
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('write');
  late final _close = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  final _owned = <int>{};

  int file(String path) {
    final bytes = utf8.encode(path);
    final pointer = _allocate(bytes.length + 1, 1).cast<Uint8>();
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      final fd = _open(pointer, 0x80000);
      if (fd < 0) throw StateError('夹具无法打开来源');
      _owned.add(fd);
      return fd;
    } finally {
      _free(pointer.cast());
    }
  }

  (int, int) pipe() {
    final pointer = _allocate(2, sizeOf<Int32>()).cast<Int32>();
    try {
      if (_pipe(pointer) != 0) throw StateError('夹具无法创建来源管道');
      final pair = (pointer[0], pointer[1]);
      _owned.addAll([pair.$1, pair.$2]);
      return pair;
    } finally {
      _free(pointer.cast());
    }
  }

  void writeByte(int fd, int value) {
    final pointer = _allocate(1, 1).cast<Uint8>();
    try {
      pointer.value = value;
      if (_write(fd, pointer, 1) != 1) throw StateError('夹具管道写入失败');
    } finally {
      _free(pointer.cast());
    }
  }

  void close(int fd) {
    if (_owned.contains(fd)) {
      if (_close(fd) != 0) throw StateError('夹具 FD 关闭失败');
      _owned.remove(fd);
    }
  }

  void dispose() {
    for (final fd in _owned.toList()) {
      close(fd);
    }
  }
}

final class _Platform {
  _Platform(
    this.directory,
    this.descriptors,
    this.fd, {
    this.offset = 0,
    this.length,
  });
  final Directory directory;
  final _Descriptors descriptors;
  final int fd, offset;
  final int? length;
  String? lease;
  bool ready = false;
  int opens = 0, releases = 0, consumes = 0;
  final openRequested = Completer<void>();
  Completer<void>? openGate;

  Future<Map<String, dynamic>> request(
    String command,
    Map<String, dynamic> params,
  ) async {
    switch (command) {
      case 'sharing.platform.environment':
        return {
          'cacheDirectory': directory.path,
          'ownerLeaseId': lease,
          'ownerReady': ready,
        };
      case 'sharing.platform.claim':
        expect(
          params['expectedOwnerLeaseId'] == lease ||
              params['ownerLeaseId'] == lease,
          isTrue,
        );
        lease = params['ownerLeaseId'] as String;
        ready = true;
        return {'claimed': true, 'ownerLeaseId': lease};
      case 'sharing.platform.open':
        expect(params['ownerLeaseId'], lease);
        opens++;
        if (!openRequested.isCompleted) openRequested.complete();
        await openGate?.future;
        return {
          'fdLeaseId': 'original',
          'fd': fd,
          'offset': offset,
          'declaredLength': length,
          'name': '授权原件.txt',
        };
      case 'sharing.platform.cancel':
        descriptors.close(fd);
        return {'cancelled': true};
      case 'sharing.platform.release':
        descriptors.close(fd);
        releases++;
        return {'released': true};
      case 'sharing.platform.consume':
        consumes++;
        return {'consumed': true};
      default:
        throw StateError('未实现的夹具命令 $command');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Linux 实际动态库的分享导入链', skip: !Platform.isLinux, () {
    late Directory directory;
    late _Descriptors descriptors;
    ShareCoordinator? coordinator;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('share-native-');
      descriptors = _Descriptors();
    });
    tearDown(() async {
      await coordinator?.close();
      coordinator = null;
      descriptors.dispose();
      await directory.delete(recursive: true);
    });

    Future<_Platform> start(int fd, {int offset = 0, int? length}) async {
      final platform = _Platform(
        directory,
        descriptors,
        fd,
        offset: offset,
        length: length,
      );
      coordinator = await ShareCoordinator.open(
        files: createNativeScrcpyLocalFiles,
        platform: platform.request,
        limits: const ShareLimits(timeout: Duration(seconds: 5)),
      );
      return platform;
    }

    test('真实 FD 按授权 offset/length 完整导入，原件不变且重复交付不重开', () async {
      final source = File(p.join(directory.path, 'source'));
      await source.writeAsString('xx授权内容tail', flush: true);
      final platform = await start(
        descriptors.file(source.path),
        offset: 2,
        length: 12,
      );
      final result = await coordinator!.receive({
        'shareId': _share,
        'sourceCount': 1,
      });
      expect(result['status'], 'ready', reason: jsonEncode(result));
      final row = (result['files'] as List).single as Map;
      expect(await File(row['localPath'] as String).readAsString(), '授权内容');
      expect(row['size'], 12);
      expect(await source.readAsString(), 'xx授权内容tail');
      final repeated = await coordinator!.receive({
        'shareId': _share,
        'sourceCount': 1,
      });
      expect(repeated['reusedImport'], isTrue);
      expect(platform.opens, 1);
      expect(platform.releases, 1);
      expect(platform.consumes, 2);
    });

    test('声明范围短读不能发布部分原件，实际片段已清理', () async {
      final source = File(p.join(directory.path, 'short'));
      await source.writeAsString('abc', flush: true);
      final platform = await start(descriptors.file(source.path), length: 10);
      final result = await coordinator!.receive({
        'shareId': _share,
        'sourceCount': 1,
      });
      expect(result['status'], 'error');
      expect(result['files'], isEmpty);
      expect(result['errors'], [contains('sourceChanged')]);
      expect(
        await Directory(p.join(directory.path, 'incoming', _share))
            .list()
            .map((f) => p.basename(f.path))
            .toList(),
        ['.share'],
      );
      expect(platform.releases, 1);
      expect(await source.readAsString(), 'abc');
    });

    test('阻塞管道的取消等待真实 SDK worker 排空，保留失败批次而无来源片段', () async {
      final pipe = descriptors.pipe();
      final platform = await start(pipe.$1);
      final allowOpen = platform.openGate = Completer<void>();
      addTearDown(() {
        if (!allowOpen.isCompleted) allowOpen.complete();
      });
      final operation = coordinator!.receive({
        'shareId': _share,
        'sourceCount': 1,
      });
      var finished = false;
      final result = operation.then((value) {
        finished = true;
        return value;
      });
      // open 只会在 reserve 的账本提交完成后发生；先挡住 FD 交付，再建立文件监听。
      await Future.any<void>([
        platform.openRequested.future,
        result.then<void>((value) {
          throw StateError('真实 FD 打开前导入已结束：${jsonEncode(value)}');
        }),
      ]).timeout(const Duration(seconds: 3));
      final batch = Directory(p.join(directory.path, 'incoming', _share));
      final copied = Completer<File>();
      final partName = RegExp(
        r'^\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.part$',
      );
      Future<void> observe(String path) async {
        if (!partName.hasMatch(p.basename(path))) return;
        try {
          final part = File(path);
          if (await part.length() == 1 && !copied.isCompleted) {
            copied.complete(part);
          }
        } catch (error, stack) {
          if (!copied.isCompleted) copied.completeError(error, stack);
        }
      }

      final changes = batch
          .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
          .listen(
            (event) => unawaited(observe(event.path)),
            onError: (Object error, StackTrace stack) {
              if (!copied.isCompleted) copied.completeError(error, stack);
            },
          );
      try {
        // 一个字节证明真实 worker 已执行 read/write；writer 保持开启，使下一次读取阻塞。
        descriptors.writeByte(pipe.$2, 0x5a);
        allowOpen.complete();
        final part = await copied.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw StateError('实际复制 worker 未把管道字节写入未发布片段'),
        );
        expect(await part.readAsBytes(), [0x5a]);
        expect(platform.opens, 1);
        expect(platform.releases, 0);
        expect(finished, isFalse, reason: '来源尚未 EOF，不能提前发布或报告复制完成');
        await coordinator!.close().timeout(const Duration(seconds: 3));
        final failed = await result;
        expect(failed['status'], 'error');
        expect(failed['files'], isEmpty);
        expect(await part.exists(), isFalse);
        expect(
          await batch.list().map((entry) => p.basename(entry.path)).toList(),
          ['.share'],
        );
        expect(platform.releases, 1);
        expect(platform.consumes, 1);
      } finally {
        if (!allowOpen.isCompleted) allowOpen.complete();
        await changes.cancel();
        descriptors.close(pipe.$2);
      }
    });
  });
}
