import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart' as adb;
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/services/files/adb_file_executor.dart';
import 'package:scrcpy_connect/services/files/file_executor.dart';
import 'package:scrcpy_connect/stores/files/file_mutation_coordinator.dart';

const _selected = FileStamp(
  mode: 0x8000,
  size: 4,
  modifiedSeconds: 1,
  identity: '1-2-3-4',
);
const _expected = {
  '/sdcard/first': _selected,
  '/sdcard/second': _selected,
  '/sdcard/never': _selected,
};

void main() {
  test('首项关闭期间连接替换，剩余删除仍绑定最初的精确连接', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    fixture.api.closeGate = Completer<void>();
    final deleting = fixture.owner.delete('device', [
      '/sdcard/first',
      '/sdcard/second',
    ], expected: _expected);
    await fixture.api.firstClosing.future;
    fixture.current = fixture.replacement;
    fixture.api.closeGate!.complete();
    await deleting;
    expect(fixture.resolutions, 1);
    expect(
      fixture.api.requests.map((entry) => entry.$2.expected?.identity),
      everyElement(_selected.identity),
    );
    expect(fixture.api.requests.map((request) => request.$1), [
      'original',
      'original',
    ]);
    expect(
      fixture.api.requests.map((request) => utf8.decode(request.$2.path)),
      ['/sdcard/first', '/sdcard/second'],
    );
  });

  test('停止等待迟到句柄及实际关闭，拒绝同设备新变更而不停止另一设备', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    fixture.api.creationGate = Completer<void>();
    fixture.api.closeGate = Completer<void>();
    final deleting = fixture.owner.delete('device', [
      '/sdcard/first',
      '/sdcard/never',
    ], expected: _expected);
    final cancelled = expectLater(deleting, throwsA(_failure('cancelled')));
    await fixture.api.firstCreated.future;
    var stopped = false;
    final stopping = fixture.owner.cancelDevice('device').then((_) {
      stopped = true;
    });
    await expectLater(
      fixture.owner.createDirectory('device', '/late'),
      throwsA(_failure('mutation_cleanup_unconfirmed')),
    );
    await fixture.owner.createDirectory('other', '/sdcard/allowed');
    expect(stopped, isFalse);
    fixture.api.creationGate!.complete();
    await fixture.api.firstClosing.future;
    expect(stopped, isFalse);
    fixture.api.closeGate!.complete();
    await stopping;
    await cancelled;
    expect(fixture.api.closed, contains('worker-1'));
    expect(
      fixture.api.requests.map((request) => utf8.decode(request.$2.path)),
      ['/sdcard/first', '/sdcard/allowed'],
    );
  });

  for (final closeAll in [false, true]) {
    test('${closeAll ? '整体关闭' : '设备停止'}唤醒已阻塞的读取并等待资源关闭，不发送后续删除', () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      fixture.api.readGate = Completer<void>();
      fixture.api.closeGate = Completer<void>();
      final deleting = fixture.owner.delete('device', [
        '/sdcard/first',
        '/sdcard/never',
      ], expected: _expected);
      final cancelled = expectLater(deleting, throwsA(_failure('cancelled')));
      await fixture.api.firstReading.future;
      var stopped = false;
      final stopping =
          (closeAll
                  ? fixture.owner.close()
                  : fixture.owner.cancelDevice('device'))
              .then((_) {
                stopped = true;
              });
      await fixture.api.firstClosing.future;
      expect(stopped, isFalse);
      fixture.api.closeGate!.complete();
      await stopping;
      await cancelled;
      expect(fixture.api.closed, ['worker-1']);
      expect(fixture.api.requests, hasLength(1));
    });
  }

  test('关闭首败保留原句柄，整体关闭可重试且不重新执行未知变更', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    fixture.api.rejectClose = true;
    await expectLater(
      fixture.owner.rename(
        'device',
        '/sdcard/first',
        destination: '/sdcard/changed',
        expected: _selected,
      ),
      throwsA(_failure('mutation_cleanup_unconfirmed')),
    );
    await expectLater(
      fixture.owner.cancelDevice('device'),
      throwsA(_failure('mutation_cleanup_unconfirmed')),
    );
    await expectLater(
      fixture.owner.createDirectory('device', '/blocked'),
      throwsA(_failure('mutation_cleanup_unconfirmed')),
    );
    await expectLater(
      fixture.owner.close(),
      throwsA(_failure('mutation_cleanup_unconfirmed')),
    );
    await expectLater(
      fixture.owner.createDirectory('device', '/late'),
      throwsA(_failure('closed')),
    );
    expect(fixture.api.closed, isEmpty);
    fixture.api.rejectClose = false;
    await fixture.owner.close();
    expect(fixture.api.closed, ['worker-1']);
    expect(fixture.api.requests, hasLength(1));
    expect(fixture.api.cancelAttempts, everyElement('worker-1'));
  });

  test('变更缺少终态保留未知回执，停止只回收句柄而不重放操作', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    fixture.api.missingReceipt = true;
    await expectLater(
      fixture.owner.delete('device', [
        '/sdcard/first',
        '/sdcard/never',
      ], expected: _expected),
      throwsA(_failure('result_unknown')),
    );
    await fixture.owner.cancelDevice('device');
    expect(fixture.api.requests, hasLength(1));
    expect(fixture.api.closed, ['worker-1']);
  });
}

Matcher _failure(String code) =>
    isA<FileFailure>().having((failure) => failure.code, 'code', code);

final class _Fixture {
  _Fixture(this.root, this.api, this.client);
  final Directory root;
  final _Api api;
  final adb.NativeAdbClient client;
  late final original = DeviceConnection(
    client: client,
    device: const adb.AdbDevice(
      id: 'original',
      serial: 'serial',
      state: 'device',
    ),
  );
  late final replacement = DeviceConnection(
    client: client,
    device: const adb.AdbDevice(
      id: 'replacement',
      serial: 'serial',
      state: 'device',
    ),
  );
  late DeviceConnection current = original;
  late final other = DeviceConnection(
    client: client,
    device: const adb.AdbDevice(id: 'other', serial: 'other', state: 'device'),
  );
  late final FileMutationCoordinator owner;
  int resolutions = 0;

  static Future<_Fixture> open() async {
    final root = await Directory.systemTemp.createTemp('file-mutation-');
    final api = _Api();
    final fixture = _Fixture(root, api, adb.NativeAdbClient(api, ''));
    fixture.owner = FileMutationCoordinator(
      AdbFileExecutor(
        localFiles: fixture.client.services,
        resolveConnection: (device) async {
          fixture.resolutions++;
          return device == 'other' ? fixture.other : fixture.current;
        },
        fileScopeId: 'file-scope',
        fileScopeKey: 'file-execution-fixture',
      ),
    );
    return fixture;
  }

  Future<void> close() async {
    api.rejectClose = false;
    for (final gate in [api.creationGate, api.closeGate, api.readGate]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    await owner.close();
    await client.services.close();
    await root.delete(recursive: true);
  }
}

final class _Api implements adb.NativeAdbApi, adb.NativeAdbFileApi {
  final requests = <(String, adb.AdbFileExecutionRequest)>[];
  final workers = <String, _Worker>{};
  final cancelAttempts = <String>[];
  final closed = <String>[];
  final firstCreated = Completer<void>();
  final firstReading = Completer<void>();
  final firstClosing = Completer<void>();
  Completer<void>? creationGate, readGate, closeGate;
  bool rejectClose = false, missingReceipt = false;

  @override
  Future<String> fileExecute(
    String connectionId,
    adb.AdbFileExecutionRequest request,
    int timeoutMs,
  ) async {
    requests.add((connectionId, request));
    final id = 'worker-${requests.length}';
    workers[id] = _Worker();
    if (id == 'worker-1') {
      firstCreated.complete();
      await creationGate?.future;
    }
    return id;
  }

  @override
  Future<adb.AdbFileExecutionEvent?> fileNext(String operationId) async {
    final worker = workers[operationId]!;
    if (operationId == 'worker-1') {
      if (!firstReading.isCompleted) firstReading.complete();
      if (readGate != null) {
        await Future.any([readGate!.future, worker.cancelled.future]);
      }
    }
    if (worker.cancelled.isCompleted) throw const adb.AdbException('cancelled');
    if (missingReceipt) return null;
    return adb.AdbFileExecutionEvent(kind: 'done', saveMode: 'applied');
  }

  @override
  Future<void> fileCancel(String operationId) async {
    cancelAttempts.add(operationId);
    if (rejectClose) throw const adb.AdbException('cleanup_failed');
    if (operationId == 'worker-1') {
      if (!firstClosing.isCompleted) firstClosing.complete();
      await closeGate?.future;
    }
    final worker = workers[operationId]!;
    if (!worker.cancelled.isCompleted) worker.cancelled.complete();
    if (!closed.contains(operationId)) closed.add(operationId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Worker {
  final cancelled = Completer<void>();
}
