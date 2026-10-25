import 'dart:async';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/companion/companion_protocol.dart';
import 'package:scrcpy_connect/companion/media_job_coordinator.dart';
import 'package:scrcpy_connect/connection/connection_owner.dart';

import 'coordinator_fixture.dart';

const _first = '10000000-0000-0000-0000-000000000001';
const _second = '10000000-0000-0000-0000-000000000002';
const _owner = '20000000-0000-0000-0000-000000000001';

Map<String, Object?> _params(String operation, {String phase = 'thumbnail'}) =>
    {
      'deviceId': 'phone',
      'operationId': operation,
      'ownerOperationId': _owner,
      'path': '/sdcard/Download/photo.jpg',
      'kind': 'image',
      'maxSize': 256,
      'execution': phase,
    };

Matcher _code(String code) => isA<ApplicationCommandException>().having(
  (error) => error.code,
  'code',
  code,
);

void main() {
  test('非法阶段和预取消不创建RPC，取消先到会阻止同ID迟到启动', () async {
    final harness = _Harness();
    final token = AdbCancellation()..cancel();
    expect(
      () => harness.jobs.command(
        'media.thumbnail',
        _params(_first),
        cancellation: token,
      ),
      throwsA(
        isA<AdbException>().having((error) => error.code, 'code', 'cancelled'),
      ),
    );
    expect(
      () => harness.jobs.command(
        'media.thumbnail',
        _params(_first, phase: 'preview'),
      ),
      throwsA(_code('invalid_argument')),
    );
    final cancelled = await harness.jobs.command('media.thumbnail.cancel', {
      'deviceId': 'phone',
      'operationId': _first,
    });
    expect(cancelled['status'], 'cancelledBeforeStart');
    expect(cancelled['reaped'], isTrue);
    expect(
      () => harness.jobs.command('media.thumbnail', _params(_first)),
      throwsA(_code('cancelled')),
    );
    expect(harness.calls, isEmpty);
    await harness.jobs.command('media.stat', _params(_second));
    expect(harness.calls.single.command, 'media.stat');
    await harness.close();
  });

  test('取消确认后仍等待原请求实际收尾，迟到成功不能发布', () async {
    final harness = _Harness();
    final original = Completer<Map<String, Object?>>();
    final cancellation = Completer<Map<String, Object?>>();
    final cancelIssued = Completer<void>();
    harness.reply = (call) {
      if (call.command == 'media.thumbnail.cancel') {
        cancelIssued.complete();
        return cancellation.future;
      }
      return original.future;
    };
    final running = harness.jobs.command('media.thumbnail', _params(_first));
    final rejected = expectLater(running, throwsA(_code('cancelled')));
    var stopped = false;
    final stopping = harness.jobs
        .command('media.thumbnail.cancel', {
          'deviceId': 'phone',
          'operationId': _first,
        })
        .then((value) {
          stopped = true;
          return value;
        });
    await cancelIssued.future;
    expect(harness.calls.last.params, {'operationId': _first});
    expect(harness.calls.last.allowStart, isFalse);
    cancellation.complete({'reaped': true});
    await cancellation.future;
    expect(stopped, isFalse);
    original.complete({'data': '迟到结果不可交付'});
    expect((await stopping)['reaped'], isTrue);
    await rejected;
    await harness.close();
  });

  test('reaped:false保留同任务清理权，重试取消不重启解码', () async {
    final harness = _Harness();
    final original = Completer<Map<String, Object?>>();
    var attempts = 0;
    harness.reply = (call) async {
      if (call.command != 'media.thumbnail.cancel') return original.future;
      if (++attempts == 1) return {'reaped': false, 'cancelRequested': true};
      original.complete({'data': '已撤准入的迟到图像'});
      return {'reaped': true};
    };
    final running = harness.jobs.command('media.thumbnail', _params(_first));
    final rejected = expectLater(
      running,
      throwsA(_code('media_cleanup_unknown')),
    );
    await expectLater(
      harness.jobs.command('media.thumbnail.cancel', {
        'deviceId': 'phone',
        'operationId': _first,
      }),
      throwsA(_code('media_cleanup_unknown')),
    );
    await rejected;
    final result = await harness.jobs.command('media.thumbnail.cancel', {
      'deviceId': 'phone',
      'operationId': _first,
    });
    expect(result['reaped'], isTrue);
    expect(attempts, 2);
    expect(
      harness.calls.where((call) => call.command == 'media.thumbnail').length,
      1,
    );
    expect(
      harness.calls.every((call) => call.params['operationId'] == _first),
      isTrue,
    );
    await harness.close();
  });

  test('取消回执超时保留同Future，迟到确认后重试不重复发取消帧', () async {
    final harness = _Harness(cleanupTimeout: const Duration(milliseconds: 10));
    final original = Completer<Map<String, Object?>>();
    final cancellation = Completer<Map<String, Object?>>();
    var attempts = 0;
    harness.reply = (call) {
      if (call.command == 'media.thumbnail.cancel') {
        attempts++;
        return cancellation.future;
      }
      return original.future;
    };
    final running = harness.jobs.command('media.thumbnail', _params(_first));
    final rejected = expectLater(
      running,
      throwsA(_code('media_cleanup_unknown')),
    );
    await expectLater(
      harness.jobs.command('media.thumbnail.cancel', {
        'deviceId': 'phone',
        'operationId': _first,
      }),
      throwsA(_code('media_cleanup_unknown')),
    );
    await rejected;
    final retry = harness.jobs.command('media.thumbnail.cancel', {
      'deviceId': 'phone',
      'operationId': _first,
    });
    cancellation.complete({'reaped': true});
    original.complete({'thumbnail': true});
    expect((await retry)['reaped'], isTrue);
    expect(attempts, 1);
    await harness.close();
  });

  test('期限触发精确取消，仍排空迟到原Future后才报告超时', () async {
    final harness = _Harness(
      operationTimeout: const Duration(milliseconds: 10),
    );
    final original = Completer<Map<String, Object?>>();
    final cancelIssued = Completer<void>();
    harness.reply = (call) async {
      if (call.command == 'media.thumbnail.cancel') {
        cancelIssued.complete();
        return {'reaped': true};
      }
      return original.future;
    };
    final running = harness.jobs.command('media.thumbnail', _params(_first));
    final rejected = expectLater(running, throwsA(_code('media_timeout')));
    var finished = false;
    final completion = running.then<void>(
      (_) {
        finished = true;
      },
      onError: (Object _) {
        finished = true;
      },
    );
    await cancelIssued.future;
    expect(finished, isFalse);
    original.complete({'thumbnail': true});
    await rejected;
    await completion;
    expect(finished, isTrue);
    await harness.close();
  });

  test('close首败保留精确任务供重试，关闭期间不准入新任务', () async {
    final harness = _Harness();
    final original = Completer<Map<String, Object?>>();
    var attempts = 0;
    harness.reply = (call) async {
      if (call.command != 'media.thumbnail.cancel') return original.future;
      if (++attempts == 1) {
        original.complete({'thumbnail': true});
        throw const CompanionException('io', '通道首败');
      }
      return {'reaped': true};
    };
    final running = harness.jobs.command('media.thumbnail', _params(_first));
    final rejected = expectLater(
      running,
      throwsA(_code('media_cleanup_unknown')),
    );
    await expectLater(
      harness.jobs.close(),
      throwsA(_code('media_cleanup_unknown')),
    );
    await rejected;
    expect(
      () => harness.jobs.command('media.thumbnail', _params(_second)),
      throwsA(_code('disposed')),
    );
    await harness.jobs.close();
    expect(attempts, 2);
    expect(harness.client.unexpectedCalls, 0);
  });

  test('原请求报错也须确认reaped，完整清理后保留真实远端错误', () async {
    final harness = _Harness();
    harness.reply = (call) async {
      if (call.command == 'media.thumbnail.cancel') return {'reaped': true};
      throw const CompanionException(
        'thumbnail_api_pending',
        '旧Android不支持有界视频抽帧',
      );
    };
    await expectLater(
      harness.jobs.command('media.thumbnail', _params(_first)),
      throwsA(_code('thumbnail_api_pending')),
    );
    expect(harness.calls.map((call) => call.command), [
      'media.thumbnail',
      'media.thumbnail.cancel',
    ]);
    await harness.close();
  });

  test('停止原连接只清理其任务，后继连接可独立工作且不受旧停止影响', () async {
    final harness = _Harness();
    final previous = harness.current;
    final original = Completer<Map<String, Object?>>();
    final cancelIssued = Completer<void>();
    final cancellation = Completer<Map<String, Object?>>();
    harness.reply = (call) {
      if (call.command == 'media.thumbnail.cancel') {
        expect(identical(call.connection, previous), isTrue);
        cancelIssued.complete();
        return cancellation.future;
      }
      return identical(call.connection, previous)
          ? original.future
          : Future.value({'data': '新连接结果'});
    };
    final running = harness.jobs.command('media.thumbnail', _params(_first));
    final rejected = expectLater(running, throwsA(_code('cancelled')));
    final stopping = harness.jobs.stopForConnection('phone', previous);
    await cancelIssued.future;
    harness.replaceConnection();
    final next = await harness.jobs.command(
      'media.thumbnail',
      _params(_second),
    );
    expect(next['data'], '新连接结果');
    original.complete({'data': '原连接迟到结果'});
    cancellation.complete({'reaped': true});
    await stopping;
    await rejected;
    await harness.jobs.stopForConnection('phone', previous);
    expect(
      harness.calls
          .where((call) => call.command == 'media.thumbnail.cancel')
          .length,
      1,
    );
    expect(harness.client.unexpectedCalls, 0);
    await harness.close();
  });

  test('真实有序RPC写入迟到时令牌取消仍使用原ID收尾，不关闭共享通道', () async {
    final fixture = CoordinatorFixture();
    final writeGate = fixture.api.writeGate = Completer<void>();
    final started = fixture.api.requests.stream.firstWhere(
      (request) => request['command'] == 'media.thumbnail',
    );
    final cancellation = fixture.api.requests.stream.firstWhere(
      (request) => request['command'] == 'media.thumbnail.cancel',
    );
    Map<String, Object?>? original;
    fixture.api.onRequest = (request) {
      if (request['command'] == 'media.thumbnail') original = request;
      if (request['command'] == 'media.thumbnail.cancel') {
        fixture.reply(request, {'reaped': true});
        fixture.reply(original!, {'data': '已取消的迟到结果'});
      }
    };
    final jobs = MediaJobCoordinator(
      requireConnection: (_) => fixture.current!,
      request: fixture.companion.request,
    );
    final token = AdbCancellation();
    final running = jobs.command(
      'media.thumbnail',
      _params(_first),
      cancellation: token,
    );
    final rejected = expectLater(running, throwsA(_code('cancelled')));
    final first = await started;
    token.cancel();
    writeGate.complete();
    final cancel = await cancellation;
    expect(first['operationId'], _first);
    expect(cancel['operationId'], _first);
    await rejected;
    await jobs.close();
    expect(fixture.companion.hasActive('phone'), isTrue);
    expect(fixture.api.receivedCommands, [
      'media.thumbnail',
      'media.thumbnail.cancel',
    ]);
    await fixture.companion.close();
    expect(fixture.api.live, isEmpty);
    expect(fixture.api.disconnected, isEmpty);
  });

  test('ConnectionOwner先撤当前连接，媒体取消仍走原精确部署并等待真实回收', () async {
    final fixture = CoordinatorFixture();
    final originalConnection = fixture.current!;
    final issued = fixture.api.requests.stream.firstWhere(
      (request) => request['command'] == 'media.thumbnail',
    );
    final cancelIssued = fixture.api.requests.stream.firstWhere(
      (request) => request['command'] == 'media.thumbnail.cancel',
    );
    final allowReaped = Completer<void>();
    Map<String, Object?>? original;
    fixture.api.onRequest = (request) {
      if (request['command'] == 'media.thumbnail') original = request;
      if (request['command'] == 'media.thumbnail.cancel') {
        unawaited(
          allowReaped.future.then((_) {
            fixture.reply(request, {'reaped': true});
            fixture.reply(original!, {'data': '退休连接的迟到结果'});
          }),
        );
      }
    };
    late final ConnectionOwner connections;
    late final MediaJobCoordinator jobs;
    connections = ConnectionOwner(
      stopActivities: (device, exact) async {
        expect(
          connections.current(device),
          isNull,
          reason: '断开先同步撤销业务准入，不能为了取消暂时恢复旧连接。',
        );
        expect(identical(exact, originalConnection), isTrue);
        fixture.current = null;
        await jobs.stopForConnection(device, exact);
      },
    );
    await connections.replace(
      'phone',
      open: (_) async => originalConnection,
      verify: (_, _) async {},
    );
    jobs = MediaJobCoordinator(
      requireConnection: connections.require,
      request: fixture.companion.request,
    );
    addTearDown(() async {
      if (!allowReaped.isCompleted) allowReaped.complete();
      await jobs.close();
      await connections.close();
      await fixture.companion.close();
    });
    final running = jobs.command('media.thumbnail', _params(_first));
    final rejected = expectLater(running, throwsA(_code('cancelled')));
    await issued;
    var disconnected = false;
    final stopping = connections.disconnect('phone').then((_) {
      disconnected = true;
    });
    expect(connections.current('phone'), isNull);
    final cancellation = await cancelIssued;
    expect(cancellation['operationId'], _first);
    expect(disconnected, isFalse);
    expect(
      fixture.api.disconnected,
      isEmpty,
      reason: '未确认远端任务reaped及原RPC收尾前不能关闭连接。',
    );
    allowReaped.complete();
    await stopping;
    await rejected;
    expect(fixture.api.receivedCommands, [
      'media.thumbnail',
      'media.thumbnail.cancel',
    ], reason: '取消复用已登记部署，不能重新部署或把工作转给后继连接。');
    expect(fixture.api.disconnected, [originalConnection.device.id]);
  });

  test('真实CompanionCoordinator帧链复用同部署，任务close不关闭共享服务', () async {
    final fixture = CoordinatorFixture();
    fixture.api.onRequest = (request) {
      if (request['command'] == 'media.stat') {
        fixture.reply(request, {
          'sourceStamp': {'size': 17},
          'transformVersion': 1,
        });
      }
    };
    final jobs = MediaJobCoordinator(
      requireConnection: (_) => fixture.current!,
      request: fixture.companion.request,
    );
    final result = await jobs.command(
      'media.thumbnail',
      _params(_first, phase: 'stat'),
    );
    expect(result['sourceStamp'], {'size': 17});
    final frame = fixture.api.receivedCommands.single;
    expect(frame, 'media.stat');
    await jobs.close();
    expect(fixture.companion.hasActive('phone'), isTrue);
    expect(fixture.api.receivedCommands, ['media.stat']);
    expect(fixture.api.live, isNotEmpty);
    await fixture.companion.close();
    expect(fixture.api.live, isEmpty);
    expect(fixture.api.disconnected, isEmpty);
  });
}

final class _Call {
  _Call(
    this.command,
    this.params,
    this.allowStart,
    this.connection,
    this.cancellation,
  );
  final String command;
  final Map<String, Object?> params;
  final bool allowStart;
  final DeviceConnection? connection;
  final AdbCancellation? cancellation;
}

final class _UnusedClient implements AdbClient {
  int unexpectedCalls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('媒体任务不得关闭共享SDK资源：${invocation.memberName}');
  }
}

final class _Harness {
  _Harness({
    Duration operationTimeout = const Duration(seconds: 2),
    Duration cleanupTimeout = const Duration(seconds: 2),
  }) {
    replaceConnection();
    jobs = MediaJobCoordinator(
      requireConnection: (_) => current,
      request: _request,
      operationTimeout: operationTimeout,
      cleanupTimeout: cleanupTimeout,
    );
  }
  final client = _UnusedClient();
  late DeviceConnection current;
  late final MediaJobCoordinator jobs;
  final calls = <_Call>[];
  Future<Map<String, Object?>> Function(_Call)? reply;
  DeviceConnection replaceConnection() => current = DeviceConnection(
    client: client,
    device: const AdbDevice(id: 'exact', serial: 'serial', state: 'device'),
  );
  Future<Map<String, Object?>> _request(
    String device,
    String command,
    Map<String, Object?> params, {
    required bool allowStart,
    DeviceConnection? expectedConnection,
    AdbCancellation? cancellation,
  }) {
    final call = _Call(
      command,
      Map.of(params),
      allowStart,
      expectedConnection,
      cancellation,
    );
    calls.add(call);
    return reply?.call(call) ??
        Future.value(
          command == 'media.thumbnail.cancel'
              ? {'reaped': true}
              : {'thumbnail': true},
        );
  }

  Future<void> close() async {
    await jobs.close();
    expect(client.unexpectedCalls, 0);
  }
}
