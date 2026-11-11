import 'package:scrcpy_connect/models/device_connection.dart';
import 'package:scrcpy_connect/models/file_failure.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart' as adb;
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/adb_file_executor.dart';
import 'package:scrcpy_connect/stores/media_cache_store.dart';
import 'package:scrcpy_connect/services/media_preview_service.dart';

void main() {
  test('预览完成回执后反复关闭失败保留原part及预算，重试只收回原连接', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    await expectLater(
      fixture.owner.invoke('media.preview', {
        'deviceId': 'device',
        'path': '/sdcard/preview.png',
      }),
      throwsA(_cleanup),
    );
    final temporary = fixture.api.temporary!;
    expect(await File(temporary).readAsBytes(), [1, 2, 3]);
    expect((await fixture.cache.status())['reservedBytes'], greaterThan(0));
    expect((await fixture.cache.clear())['deletedBytes'], 0);
    fixture.current = fixture.replacement;
    await expectLater(
      fixture.owner.cancelDevice('device'),
      throwsA(isA<FileFailure>()),
    );
    expect(await File(temporary).exists(), isTrue);
    expect(fixture.api.releaseCalls, 0);
    expect(fixture.api.copyCalls, 1);
    await expectLater(
      fixture.owner.invoke('media.preview', {
        'deviceId': 'device',
        'path': '/sdcard/another.png',
      }),
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'disposed')),
    );
    fixture.api.rejectClose = false;
    await fixture.owner.cancelDevice('device');
    expect(await File(temporary).exists(), isFalse);
    expect(fixture.api.releaseCalls, 1);
    expect(fixture.api.copyCalls, 1);
    expect(fixture.api.connections.toSet(), {'original'});
    expect((await fixture.cache.status())['reservedBytes'], 0);
    expect(fixture.replacementApi.connections, isEmpty);
  });

  test('精确part释放已回执但其worker关闭失败，保留同一worker与预算后重试', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    fixture.api.rejectClose = false;
    fixture.api.changeAfterCopy = true;
    fixture.api.rejectReleaseClose = true;
    await expectLater(
      fixture.owner.invoke('media.preview', {
        'deviceId': 'device',
        'path': '/sdcard/preview.png',
      }),
      throwsA(_cleanup),
    );
    expect(fixture.api.releaseCalls, 1);
    expect((await fixture.cache.status())['reservedBytes'], greaterThan(0));
    fixture.api.rejectReleaseClose = false;
    await fixture.owner.close();
    expect(fixture.api.releaseCalls, 1);
    expect(fixture.api.closedReleases.toSet(), hasLength(1));
    expect((await fixture.cache.status())['reservedBytes'], 0);
    expect(fixture.api.copyCalls, 1);
  });

  test('迟到copy创建必须交接精确会话，取消首败保留写入保护供再次close', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    final gate = fixture.api.creationGate = Completer<void>();
    final preview = expectLater(
      fixture.owner.invoke('media.preview', {
        'deviceId': 'device',
        'path': '/sdcard/preview.png',
      }),
      throwsA(_cleanup),
    );
    await fixture.api.copyStarted.future;
    var finished = false;
    final stopping = expectLater(
      fixture.owner.cancelDevice('device'),
      throwsA(isA<FileFailure>()),
    ).then((_) => finished = true);
    expect(finished, isFalse);
    expect((await fixture.cache.clear())['deletedBytes'], 0);
    expect(await File(fixture.api.temporary!).exists(), isTrue);
    gate.complete();
    await preview;
    await stopping;
    expect(fixture.api.closedCopies, isNotEmpty);
    expect((await fixture.cache.status())['reservedBytes'], greaterThan(0));
    fixture.api.rejectClose = false;
    await fixture.owner.close();
    expect(await File(fixture.api.temporary!).exists(), isFalse);
    expect((await fixture.cache.status())['reservedBytes'], 0);
    expect(fixture.api.copyCalls, 1);
  });

  test('阻塞读取的copy取消失败即时报告，仍保留实际worker与writer直到重试排空', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    fixture.api.blockRead = true;
    final preview = expectLater(
      fixture.owner.invoke('media.preview', {
        'deviceId': 'device',
        'path': '/sdcard/preview.png',
      }),
      throwsA(
        anyOf(
          _cleanup,
          isA<FileFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      ),
    );
    await fixture.api.readStarted.future;
    // cancelDevice 必须报告真实关闭失败，不能先等待仍被卡住的事件读取。
    await expectLater(
      fixture.owner.cancelDevice('device'),
      throwsA(isA<FileFailure>()),
    );
    expect(fixture.api.pendingRead!.isCompleted, isFalse);
    expect((await fixture.cache.clear())['deletedBytes'], 0);
    expect((await fixture.cache.status())['reservedBytes'], greaterThan(0));
    fixture.api.rejectClose = false;
    await fixture.owner.close();
    await preview;
    expect(fixture.api.pendingRead!.isCompleted, isTrue);
    expect(await File(fixture.api.temporary!).exists(), isFalse);
    expect((await fixture.cache.status())['reservedBytes'], 0);
    expect(fixture.api.copyCalls, 1);
  });
}

final _cleanup = isA<RequestFailure>().having(
  (e) => e.code,
  'code',
  'media_cleanup_unconfirmed',
);

final class _Fixture {
  _Fixture(this.root, this.cache, this.api, this.replacementApi);
  final Directory root;
  final MediaCacheStore cache;
  final _Api api, replacementApi;
  late final DeviceConnection replacement;
  late DeviceConnection current;
  late final MediaPreviewService owner;
  static Future<_Fixture> open() async {
    final root = await Directory.systemTemp.createTemp('preview-cleanup-');
    final cache = await MediaCacheStore.open(root: root);
    final api = _Api(), other = _Api();
    final fixture = _Fixture(root, cache, api, other);
    final client = adb.NativeAdbClient(api, '/unused/key');
    fixture.current = DeviceConnection(
      client: client,
      device: adb.AdbDevice(
        id: 'original',
        serial: 'serial',
        state: 'device',
        nativeOwner: api,
      ),
    );
    fixture.replacement = DeviceConnection(
      client: adb.NativeAdbClient(other, '/unused/key'),
      device: adb.AdbDevice(
        id: 'replacement',
        serial: 'serial',
        state: 'device',
        nativeOwner: other,
      ),
    );
    fixture.owner = MediaPreviewService(
      cache: cache,
      executor: AdbFileExecutor(
        localFiles: client.services,
        resolveConnection: (_) async => fixture.current,
        fileScopeId: 'scope',
        fileScopeKey: 'file-execution-fixture',
      ),
      request: (_, _) => throw StateError('预览不走伴生RPC'),
    );
    return fixture;
  }

  Future<void> dispose() async {
    api.rejectClose = false;
    api.rejectReleaseClose = false;
    if (api.creationGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    await owner.close();
    await root.delete(recursive: true);
  }
}

/// 走公开 NativeAdbClient→AdbServices→AdbFileSession，只有设备端文件事件使用夹具。
final class _Api implements adb.NativeAdbApi, adb.NativeAdbFileApi {
  final requests = <String, adb.AdbFileExecutionRequest>{};
  final queues = <String, List<adb.AdbFileExecutionEvent>>{};
  final connections = <String>[],
      closedCopies = <String>[],
      closedReleases = <String>[];
  final copyStarted = Completer<void>(), readStarted = Completer<void>();
  Completer<void>? creationGate;
  Completer<adb.AdbFileExecutionEvent?>? pendingRead;
  bool rejectClose = true,
      blockRead = false,
      handedPart = false,
      rejectReleaseClose = false,
      changeAfterCopy = false;
  int copyCalls = 0, releaseCalls = 0;
  String? temporary;
  static const stamp = adb.AdbFileExecutionStamp(
    mode: 0x81a4,
    size: 3,
    modifiedSeconds: 12,
    modifiedNanos: 0,
    nanosecondPrecision: false,
  );

  @override
  Future<String> fileExecute(
    String connectionId,
    adb.AdbFileExecutionRequest request,
    int timeoutMs,
  ) async {
    connections.add(connectionId);
    final id = 'worker-${requests.length}';
    requests[id] = request;
    switch (request.kind) {
      case adb.AdbFileExecutionKind.stat:
        queues[id] = [
          adb.AdbFileExecutionEvent(
            kind: 'stat',
            stamp: changeAfterCopy && copyCalls > 0
                ? const adb.AdbFileExecutionStamp(
                    mode: 0x81a4,
                    size: 3,
                    modifiedSeconds: 13,
                    modifiedNanos: 0,
                    nanosecondPrecision: false,
                  )
                : stamp,
          ),
          adb.AdbFileExecutionEvent(kind: 'done'),
        ];
      case adb.AdbFileExecutionKind.copy:
        copyCalls++;
        temporary = utf8.decode(request.destination);
        await File(temporary!).writeAsBytes([1, 2, 3], flush: true);
        queues[id] = [
          adb.AdbFileExecutionEvent(
            kind: 'done',
            transferred: 3,
            partId: 'held-part',
          ),
        ];
        copyStarted.complete();
        await creationGate?.future;
      case adb.AdbFileExecutionKind.releasePart:
        releaseCalls++;
        expect(request.partId, 'held-part');
        final file = File(temporary!);
        if (await file.exists()) await file.delete();
        queues[id] = [
          adb.AdbFileExecutionEvent(kind: 'done', saveMode: 'released'),
        ];
      default:
        throw StateError('测试不应执行 ${request.kind}');
    }
    return id;
  }

  @override
  Future<adb.AdbFileExecutionEvent?> fileNext(String id) async {
    if (requests[id]!.kind == adb.AdbFileExecutionKind.copy && blockRead) {
      if (!readStarted.isCompleted) readStarted.complete();
      return (pendingRead ??= Completer<adb.AdbFileExecutionEvent?>()).future;
    }
    final queue = queues[id]!;
    if (queue.isEmpty) return null;
    final event = queue.removeAt(0);
    if (event.partId != null) handedPart = true;
    return event;
  }

  @override
  Future<void> fileCancel(String id) async {
    if (requests[id]!.kind == adb.AdbFileExecutionKind.releasePart) {
      closedReleases.add(id);
      if (rejectReleaseClose) {
        throw const adb.AdbException(
          'adb_cleanup_unconfirmed',
          'part释放worker仍未退出',
        );
      }
    }
    if (requests[id]!.kind != adb.AdbFileExecutionKind.copy) return;
    closedCopies.add(id);
    if (rejectClose) {
      throw const adb.AdbException('adb_cleanup_unconfirmed', 'worker仍未退出');
    }
    if (pendingRead case final read? when !read.isCompleted) {
      // 真实 close 先唤醒 next，再接管未交付 part；不能把 worker 留在读取背后。
      handedPart = true;
      read.complete(
        adb.AdbFileExecutionEvent(
          kind: 'done',
          transferred: 3,
          partId: 'held-part',
        ),
      );
    }
    if (!handedPart) {
      final file = File(temporary!);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> initializeFileHelpers(List<adb.AdbFileHelper> helpers) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
