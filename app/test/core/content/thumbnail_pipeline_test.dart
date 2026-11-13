import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:adb/adb.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/content/content_cache.dart';
import 'package:scrcpy_connect/core/content/content_preview.dart';
import 'package:scrcpy_connect/core/content/thumbnail_job_service.dart';
import 'package:scrcpy_connect/core/content/thumbnail_jobs.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_executor.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('实际任务接口交付不可变源身份及可解码 JPEG，不暴露协议 Map', () async {
    final fixture = await _Fixture.open();
    final sourceReply = _source();
    fixture.respond = (call) async => call.command == 'media.stat'
        ? {'sourceStamp': sourceReply}
        : _thumbnail();
    final ThumbnailJobs jobs = fixture.jobs;
    final source = await jobs.readSource(_job());
    final image = await jobs.render(_job());
    sourceReply['inode'] = 'replacement';
    expect(source.inode, '23');
    expect(image.source, source);
    expect(image.source.modifiedNanos, isNull);
    expect(image.jpeg, base64Decode(_jpeg));
    final bytes = base64Decode(_jpeg);
    final replacement = ThumbnailImage(
      source: ThumbnailSource(
        device: '12',
        inode: '23',
        mode: 0x8000,
        size: 4096,
        modifiedSeconds: 100,
        changedSeconds: 101,
      ),
      jpeg: bytes,
      maxSize: 256,
    );
    bytes[0] = 0;
    expect(replacement.source, source);
    expect(replacement.jpeg, image.jpeg);
    expect(replacement.digest, image.digest);
    expect(() => image.jpeg[0] = 0, throwsUnsupportedError);
    expect(
      () => image.jpeg.buffer.asUint8List()[0] = 0,
      throwsUnsupportedError,
    );
    final codec = await ui.instantiateImageCodec(image.jpeg);
    final frame = await codec.getNextFrame();
    expect((frame.image.width, frame.image.height), (8, 6));
    frame.image.dispose();
    codec.dispose();
    expect(fixture.calls.map((call) => call.command), [
      'media.stat',
      'media.thumbnail',
    ]);
    expect(
      fixture.calls.every(
        (call) => identical(call.connection, fixture.connection),
      ),
      isTrue,
    );
  });

  for (final entry in <String, Object?>{
    'sha256': 'wrong-digest',
    'jpegBytes': 0,
    'width': 9,
    'data': 'invalid-base64%',
  }.entries) {
    test('实际任务拒绝错误 ${entry.key} 回执，已退出任务不虚构额外取消', () async {
      final fixture = await _Fixture.open();
      fixture.respond = (_) async => {..._thumbnail(), entry.key: entry.value};
      await expectLater(
        fixture.jobs.render(_job()),
        throwsA(_failure('invalid_thumbnail')),
      );
      await fixture.jobs.close();
      expect(fixture.calls.map((call) => call.command), ['media.thumbnail']);
    });
  }

  test('实际源读取拒绝无效精度，不把未知纳秒精度转换成零', () async {
    final fixture = await _Fixture.open();
    fixture.respond = (_) async => {
      'sourceStamp': {..._source(), 'modifiedNanos': 1000000000},
    };
    await expectLater(
      fixture.jobs.readSource(_job()),
      throwsA(_failure('invalid_data')),
    );
    fixture.respond = (_) async => {
      'sourceStamp': {..._source(), 'modifiedNanos': 0},
    };
    final precise = await fixture.jobs.readSource(_job());
    expect(precise.modifiedNanos, 0);
    expect(precise, isNot(ThumbnailSource.fromJson(_source())));
  });

  test('取消失败保留原任务；换连接后重试仍排空原连接，迟到成功不再交付', () async {
    final fixture = await _Fixture.open();
    final original = fixture.connection;
    final execution = Completer<Map<String, Object?>>();
    final started = Completer<void>();
    final retryStarted = Completer<void>();
    var attempts = 0;
    fixture.respond = (call) {
      if (call.command == 'media.thumbnail') {
        started.complete();
        return execution.future;
      }
      if (++attempts == 1) throw const RequestFailure('io_error', '取消回执丢失。');
      retryStarted.complete();
      return Future.value({'reaped': true});
    };
    final job = _job();
    final result = fixture.jobs.render(job);
    final failed = expectLater(
      result,
      throwsA(_failure('media_cleanup_unknown')),
    );
    await started.future;
    await expectLater(
      fixture.jobs.cancel('device', job.operationId),
      throwsA(_failure('media_cleanup_unknown')),
    );
    await failed;
    fixture.connection = _connection('replacement');
    final retry = fixture.jobs.cancel('device', job.operationId);
    await retryStarted.future;
    execution.complete(_thumbnail());
    await retry;
    expect(fixture.calls.map((call) => call.command), [
      'media.thumbnail',
      'media.thumbnail.cancel',
      'media.thumbnail.cancel',
    ]);
    expect(
      fixture.calls.every((call) => identical(call.connection, original)),
      isTrue,
    );
    fixture.respond = (_) async => _thumbnail();
    final next = await fixture.jobs.render(_job());
    expect(next.width, 8);
    expect(fixture.calls.last.connection, same(fixture.connection));
    await fixture.jobs.close();
    expect(attempts, 2);
  });

  test('真实预览和缓存复用同一源版本；命中不重解码，读租约保护产物', () async {
    final fixture = await _Fixture.open();
    final first = await fixture.thumbnail();
    expect(first.cacheHit, isFalse);
    expect(await File(first.path).readAsBytes(), base64Decode(_jpeg));
    expect(fixture.calls.map((call) => call.command), [
      'media.stat',
      'media.thumbnail',
      'media.stat',
    ]);
    await fixture.content.releaseLease(first.leaseId!);
    await fixture.content.close();
    await fixture.jobs.close();
    // 重新打开实际缓存和任务所有者，验证旧 metadata.json 的键与版本仍可复用。
    await fixture.reopen();
    fixture.calls.clear();
    final cached = await fixture.thumbnail();
    expect(cached.cacheHit, isTrue);
    expect(cached.path, first.path);
    expect(fixture.calls.map((call) => call.command), ['media.stat']);
    expect(await fixture.cache.clear(), 0);
    expect(await File(cached.path).exists(), isTrue);
    await fixture.content.releaseLease(cached.leaseId!);
    expect(await fixture.cache.clear(), greaterThan(0));
    expect(await File(cached.path).exists(), isFalse);
  });

  test('生成后源身份变化不发布缓存，真实缓存写租约仍能释放', () async {
    final fixture = await _Fixture.open();
    var stats = 0;
    fixture.respond = (call) async => call.command == 'media.stat'
        ? {
            'sourceStamp': {..._source(), if (++stats == 2) 'changedNanos': 1},
          }
        : _thumbnail();
    await expectLater(fixture.thumbnail(), throwsA(_failure('source_changed')));
    expect(await fixture.jpegs(), isEmpty);
    fixture.respond = fixture.defaultReply;
    final fresh = await fixture.thumbnail();
    await fixture.content.releaseLease(fresh.leaseId!);
    expect(await fixture.cache.clear(), greaterThan(0));
  });

  test('页面取消后原任务迟到成功不能写缓存，下一次读取仍可用', () async {
    final fixture = await _Fixture.open();
    final execution = Completer<Map<String, Object?>>();
    final started = Completer<void>();
    final cancelled = Completer<void>();
    fixture.respond = (call) {
      if (call.command == 'media.thumbnail') {
        started.complete();
        return execution.future;
      }
      if (call.command == 'media.thumbnail.cancel') {
        cancelled.complete();
        return Future.value({'reaped': true});
      }
      return fixture.defaultReply(call);
    };
    final operationId = const Uuid().v4();
    final result = fixture.content.thumbnail(
      deviceId: 'device',
      path: '/sdcard/photo.jpg',
      operationId: operationId,
    );
    final rejected = expectLater(result, throwsA(_failure('cancelled')));
    await started.future;
    await fixture.content.cancelThumbnail(
      deviceId: 'device',
      operationId: operationId,
    );
    await cancelled.future;
    execution.complete(_thumbnail());
    await rejected;
    expect(await fixture.jpegs(), isEmpty);
    fixture.respond = fixture.defaultReply;
    final fresh = await fixture.thumbnail();
    await fixture.content.releaseLease(fresh.leaseId!);
    expect(await fixture.cache.clear(), greaterThan(0));
  });
}

final class _Fixture {
  _Fixture(this.root);
  final Directory root;
  DeviceConnection connection = _connection('original');
  final calls = <_Call>[];
  late Future<Map<String, Object?>> Function(_Call) respond = defaultReply;
  late ContentCache cache;
  late ThumbnailJobService jobs;
  late ContentPreview content;

  static Future<_Fixture> open() async {
    final temporary = await Directory.systemTemp.createTemp(
      'thumbnail-pipeline-',
    );
    final fixture = _Fixture(Directory(await temporary.resolveSymbolicLinks()));
    await fixture.reopen();
    addTearDown(() async {
      await fixture.content.close();
      await fixture.jobs.close();
      await fixture.root.delete(recursive: true);
    });
    return fixture;
  }

  Future<void> reopen() async {
    cache = await ContentCache.open(
      root: root,
      freeBytes: (_) async => 8 * 1024 * 1024 * 1024,
    );
    jobs = ThumbnailJobService(
      requireConnection: (_) => connection,
      request:
          (
            device,
            command,
            params, {
            required allowStart,
            expectedConnection,
            cancellation,
          }) {
            final call = _Call(
              command,
              Map.unmodifiable(params),
              expectedConnection!,
            );
            calls.add(call);
            expect(device, 'device');
            if (command == 'media.thumbnail.cancel') {
              expect(allowStart, isFalse);
            } else {
              expect(params['path'], '/sdcard/photo.jpg');
              expect(params['kind'], 'image');
              expect(params['maxSize'], 256);
            }
            return respond(call);
          },
      cleanupTimeout: const Duration(milliseconds: 200),
      operationTimeout: const Duration(seconds: 3),
    );
    content = ContentPreview(
      cache: cache,
      executor: _UnusedExecutor(),
      jobs: jobs,
    );
  }

  Future<Map<String, Object?>> defaultReply(_Call call) async =>
      switch (call.command) {
        'media.stat' => {'sourceStamp': _source()},
        'media.thumbnail' => _thumbnail(),
        'media.thumbnail.cancel' => {'reaped': true},
        _ => throw StateError('unexpected ${call.command}'),
      };

  Future<CachedContent> thumbnail() => content.thumbnail(
    deviceId: 'device',
    path: '/sdcard/photo.jpg',
    operationId: const Uuid().v4(),
  );

  Future<List<File>> jpegs() async => [
    await for (final entry in root.list(recursive: true))
      if (entry is File && entry.path.endsWith('.jpg')) entry,
  ];
}

final class _Call {
  const _Call(this.command, this.params, this.connection);
  final String command;
  final Map<String, Object?> params;
  final DeviceConnection connection;
}

ThumbnailJob _job() => ThumbnailJob(
  deviceId: 'device',
  operationId: const Uuid().v4(),
  ownerOperationId: const Uuid().v4(),
  path: '/sdcard/photo.jpg',
  kind: ThumbnailKind.image,
  maxSize: 256,
);

DeviceConnection _connection(String id) => DeviceConnection(
  client: _UnusedClient(),
  device: AdbDevice(id: id, serial: 'phone', state: 'device'),
);

final class _UnusedClient implements AdbClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('缩略图任务只借用精确连接身份。');
}

final class _UnusedExecutor implements FileExecutor {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('缩略图不能回退为下载原文件。');
}

Matcher _failure(String code) =>
    isA<RequestFailure>().having((failure) => failure.code, 'code', code);

Map<String, Object?> _source() => {
  'device': '12',
  'inode': '23',
  'mode': 0x8000,
  'size': 4096,
  'modifiedSeconds': 100,
  'changedSeconds': 101,
  'modifiedNanos': null,
  'changedNanos': null,
};

Map<String, Object?> _thumbnail() => {
  'sourceStamp': _source(),
  'thumbnail': true,
  'mime': 'image/jpeg',
  'data': _jpeg,
  'sha256': sha256.convert(base64Decode(_jpeg)).toString(),
  'jpegBytes': base64Decode(_jpeg).length,
  'width': 8,
  'height': 6,
};

// 固定的 8 × 6 RGB JPEG，实际解码而非只模拟尺寸头。
const _jpeg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAGAAgDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAABQb/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCTAUgB/9k=';
