import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/platform/application_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.scrcpyconnect/platform');

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
