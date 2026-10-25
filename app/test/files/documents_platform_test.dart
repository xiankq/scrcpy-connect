import 'dart:io';
import 'dart:convert';
import 'dart:ffi';

import 'package:adb/adb.dart';
import 'package:scrcpy/scrcpy.dart' show createNativeScrcpyLocalFiles;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/platform/application_platform.dart';
import 'package:scrcpy_connect/files/documents/document_scope_recovery.dart';
import 'package:scrcpy_connect/files/documents/document_sources.dart';
import 'package:scrcpy_connect/files/documents/documents_coordinator.dart';

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
  late final _close = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  final _owned = <int>{};

  int open(String path) {
    final bytes = utf8.encode(path);
    final pointer = _allocate(bytes.length + 1, 1).cast<Uint8>();
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      final fd = _open(pointer, 0x80002);
      if (fd < 0) throw StateError('无法打开真实文档夹具');
      _owned.add(fd);
      return fd;
    } finally {
      _free(pointer.cast());
    }
  }

  void close(int fd) {
    if (_owned.remove(fd) && _close(fd) != 0) {
      throw StateError('无法关闭真实文档夹具');
    }
  }

  void dispose() {
    for (final fd in _owned.toList()) {
      close(fd);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.scrcpyconnect/platform');

  test('real Documents export maps trusted logical cache and screenshots inputs while retaining their identity', () async {
    final parent = await Directory.systemTemp.createTemp(
      'document-export-alias-',
    );
    final files = await createNativeScrcpyLocalFiles();
    final descriptors = _Descriptors();
    DocumentsCoordinator? coordinator;
    try {
      final actual = await Directory(p.join(parent.path, 'actual')).create();
      final logical = Link(p.join(parent.path, 'logical'));
      await logical.create(actual.path);
      final cache = await Directory(p.join(actual.path, 'cache')).create();
      final screenshots = await Directory(p.join(actual.path, 'screenshots'))
          .create();
      final target = await File(p.join(parent.path, 'provider'))
          .writeAsString('');
      final environment = <String, dynamic>{
        'cacheDirectory': p.join(logical.path, 'cache'),
        'screenshotsDirectory': p.join(logical.path, 'screenshots'),
        'ownerLeaseId': 'fixture',
      };
      // 生产平台与协调器分两次核验同一环境。
      final boundary = await DocumentScopeConfiguration.fromEnvironment(
        environment,
      );
      final sources = await DocumentSources.open(
        cacheDirectory: Directory(environment['cacheDirectory'] as String),
      );
      var pickerCount = 0;
      coordinator = DocumentsCoordinator(
        files: () async => files,
        sources: sources,
        platform: (command, params) async {
          switch (command) {
            case 'documents.platform.environment':
              return boundary.environment;
            case 'documents.platform.picker':
              pickerCount++;
              return {
                'status': 'selected',
                'documents': [
                  {'handle': 'target'},
                ],
              };
            case 'documents.platform.metadata':
              return {
                'handle': 'target',
                'id': 'target',
                'authority': 'fixture',
                'name': 'target',
                'directory': false,
                'canWrite': true,
                'size': await target.length(),
              };
            case 'documents.platform.openFd':
              final fd = descriptors.open(target.path);
              return {'fd': fd, 'fdLeaseId': '$fd'};
            case 'documents.platform.releaseFd':
              descriptors.close(int.parse(params['fdLeaseId'] as String));
              return {'released': true};
            case 'documents.platform.release':
              return {'released': true};
            default:
              throw StateError(command);
          }
        },
      );
      for (final root in [cache, screenshots]) {
        final source = await File(p.join(root.path, 'source.txt'))
            .writeAsString('trusted ${root.path}');
        final requested = p.join(
          logical.path,
          p.basename(root.path),
          'source.txt',
        );
        await target.writeAsString('');
        final saved = await coordinator.request('documents.export', {
          'localPath': requested,
          'name': 'source.txt',
          'kind': 'file',
        });
        expect(saved['status'], 'saved', reason: jsonEncode(saved));
        expect(saved['localPath'], requested);
        expect(await target.readAsString(), await source.readAsString());
      }
      expect(pickerCount, 2);
      final imported = await coordinator.request('documents.importFiles');
      expect(imported['status'], 'imported', reason: jsonEncode(imported));
      final importedPath = imported['localPath'] as String;
      expect(
        await File(
          ((imported['items'] as List).single as Map)['localPath'] as String,
        ).readAsString(),
        await target.readAsString(),
      );
      await coordinator.request('documents.cancel', {
        'managedSourceId': imported['managedSourceId'],
      });
      expect(await Directory(importedPath).exists(), isFalse);
      final inside = Link(p.join(cache.path, 'inside'));
      await inside.create(parent.path);
      for (final path in [
        p.join(logical.path, 'cache', 'inside', 'provider'),
        '${logical.path}/cache/../screenshots/source.txt',
        parent.path,
      ]) {
        final denied = await coordinator.request('documents.export', {
          'localPath': path,
          'name': 'escaped',
          'kind': 'file',
        });
        expect(denied['status'], 'failed');
      }
      expect(pickerCount, 3);
    } finally {
      await coordinator?.dispose();
      descriptors.dispose();
      await files.close();
      await parent.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);

  test('real LocalFiles reaches managed sources through the canonical trusted cache root and recovery keeps its key', () async {
    final parent = await Directory.systemTemp.createTemp('document-alias-');
    final files = await createNativeScrcpyLocalFiles();
    LocalFileScope? scope;
    DocumentSources? sources;
    String? managedId;
    try {
      final first = await Directory(p.join(parent.path, 'first')).create();
      final second = await Directory(p.join(parent.path, 'second')).create();
      final alias = Link(p.join(parent.path, 'cache'));
      await alias.create(first.path);
      final original = <String, dynamic>{
        'cacheDirectory': alias.path,
        'ownerLeaseId': 'old-owner',
      };
      final boundary = await DocumentScopeConfiguration.fromEnvironment(
        original,
      );
      sources = await DocumentSources.open(
        cacheDirectory: Directory(alias.path),
      );
      final source = await sources.reserve();
      managedId = source.id;
      scope = await boundary.open(files);
      Uint8List path(String value) => Uint8List.fromList(utf8.encode(value));
      await scope.mkdir(path(source.path));
      final folder = await scope.stat(path(source.path));
      expect(folder.identity.kind, LocalFileKind.directory);
      expect(boundary.key, p.join(alias.path, 'documents'));
      final filtered = await DocumentScopeConfiguration.fromEnvironment(
        boundary.environment,
      );
      expect(filtered.key, boundary.key);

      // 重定向外部别名不能更换已经打开的实际根，也不能授予其父目录。
      await alias.delete();
      await alias.create(second.path);
      final nested = p.join(source.path, 'held');
      await scope.mkdir(path(nested));
      expect(await Directory(nested).exists(), isTrue);
      expect(
        await Directory(p.join(second.path, 'documents')).exists(),
        isFalse,
      );
      await expectLater(
        scope.mkdir(path(p.join(parent.path, 'escaped'))),
        throwsA(isA<LocalFileException>()),
      );
      final inside = Link(p.join(source.path, 'inside'));
      await inside.create(second.path);
      await expectLater(
        scope.mkdir(path(p.join(inside.path, 'escaped'))),
        throwsA(isA<LocalFileException>()),
      );
      await inside.delete();

      final recoveredCommands = <String>[];
      final recovery = DocumentScopeRecovery(
        files: () async => files,
        platform: (command, params) async {
          recoveredCommands.add(command);
          if (command == 'documents.platform.environment') return original;
          if (command == 'documents.platform.claim') {
            return {'claimed': true, 'ownerLeaseId': params['ownerLeaseId']};
          }
          throw StateError(command);
        },
      );
      await recovery.recover();
      await expectLater(
        scope.stat(path(source.path)),
        throwsA(isA<LocalFileException>()),
      );
      final successor = await DocumentScopeConfiguration.fromEnvironment(
        original,
      );
      expect(successor.key, boundary.key);
      final next = await successor.open(files);
      try {
        await next.mkdir(path(p.join(second.path, 'new-owner')));
        await expectLater(
          next.stat(path(source.path)),
          throwsA(isA<LocalFileException>()),
        );
      } finally {
        await next.close();
      }
      expect(recoveredCommands.last, 'documents.platform.claim');
    } finally {
      await scope?.close();
      await files.close();
      if (managedId != null) {
        await sources!.complete(managedId, 'folder');
        await sources.release(managedId);
      }
      await parent.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);

  if (!Platform.isAndroid) {
    test('非 Android 启动恢复不打开 SDK 或访问文档平台 channel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw StateError('不应访问平台文档。'),
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await ApplicationPlatform.recoverDocuments(
        localFiles: () async => throw StateError('不应创建本机 scope。'),
      );
    });
  }

  test('只授予实际存在的可选截图库，不创建目录或跟随符号链接', () async {
    final root = await Directory.systemTemp.createTemp('documents-roots-');
    addTearDown(() => root.delete(recursive: true));
    final cache = await Directory(p.join(root.path, 'cache')).create();
    final screenshots = Directory(p.join(root.path, 'screenshots'));
    final environment = <String, dynamic>{
      'cacheDirectory': cache.path,
      'screenshotsDirectory': screenshots.path,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => environment);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final platform = ApplicationPlatform(
      applicationRequest: (_, _) async => throw StateError('不应调用旧文档命令。'),
      localFiles: () async => throw StateError('不应打开文件 scope。'),
      emit: (_) {},
      isDisposed: () => false,
    );
    final missing = await platform.request(
      'documents.platform.environment',
      {},
    );
    expect(missing['cacheDirectory'], cache.path);
    expect(missing.containsKey('screenshotsDirectory'), isFalse);
    expect(await screenshots.exists(), isFalse);

    await screenshots.create();
    final present = await platform.request(
      'documents.platform.environment',
      {},
    );
    expect(present['screenshotsDirectory'], screenshots.path);
    await screenshots.delete();
    await Link(screenshots.path).create(cache.path);
    final linked = await platform.request('documents.platform.environment', {});
    expect(linked.containsKey('screenshotsDirectory'), isFalse);
    expect(await Link(screenshots.path).target(), cache.path);
  });
}
