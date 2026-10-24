import 'dart:async';

import 'package:adb/adb.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:flutter_test/flutter_test.dart';

const device = AdbDevice(id: 'connection', serial: 'serial', state: 'device');

void main() {
  test('来源状态使用当前连接句柄并保留原生实际计数和代次', () async {
    final native = SourceStatusScrcpyApi();
    final status = await ScrcpyClient(native)
        .sourceStatus(device, captureRef: 'capture', sourceId: 'source');
    expect(native.statusQueries, [('connection', 'capture', 'source')]);
    expect(identical(status, native.status), isTrue);
    expect(status.generation, 17);
    expect(status.packets, 4);
    expect(status.bytes, 1024);
    expect(status.kind, ScrcpySourceKind.audio);
    expect(status.status, ScrcpySourceState.closed);
  });

  test('来源状态缺少可选能力时明确失败，既有传输无需新增实现', () async {
    await expectLater(
      ScrcpyClient(FakeScrcpyApi())
          .sourceStatus(device, captureRef: 'capture', sourceId: 'source'),
      throwsA(
        isA<ScrcpyException>().having(
          (e) => e.code,
          'code',
          'source_status_unavailable',
        ),
      ),
    );
  });

  test('来源状态先核对同库身份，不能将外部连接送到原生登记表', () async {
    final native = SourceStatusScrcpyApi();
    final owner = Object();
    final scrcpy = ScrcpyClient(native, nativeOwner: owner);
    await expectLater(
      scrcpy.sourceStatus(device, captureRef: 'capture', sourceId: 'source'),
      throwsA(
        isA<ScrcpyException>().having(
          (e) => e.code,
          'code',
          'foreign_connection',
        ),
      ),
    );
    expect(native.statusQueries, isEmpty);
    await scrcpy.sourceStatus(
      AdbDevice(
        id: 'claimed-connection',
        serial: 'serial',
        state: 'device',
        nativeOwner: owner,
      ),
      captureRef: 'capture',
      sourceId: 'source',
    );
    expect(native.statusQueries.single.$1, 'claimed-connection');
  });

  for (final mismatch in [
    ('other-capture', 'source'),
    ('capture', 'other-source'),
  ]) {
    test('来源状态拒绝串用身份回执 $mismatch', () async {
      final native = SourceStatusScrcpyApi()
        ..status = ScrcpySourceStatus(
          captureRef: mismatch.$1,
          sourceId: mismatch.$2,
          generation: 0,
          kind: ScrcpySourceKind.video,
          codec: 'h264',
          status: ScrcpySourceState.waiting,
          packets: 0,
          bytes: 0,
        );
      await expectLater(
        ScrcpyClient(native)
            .sourceStatus(device, captureRef: 'capture', sourceId: 'source'),
        throwsA(
          isA<ScrcpyException>().having((e) => e.code, 'code', 'stale_source'),
        ),
      );
    });
  }

  test('原生未知或释放来源错误原样传播，不伪造空统计', () async {
    const error = ScrcpyException('stale_source', '来源已释放');
    final native = SourceStatusScrcpyApi()..statusError = error;
    await expectLater(
      ScrcpyClient(native)
          .sourceStatus(device, captureRef: 'capture', sourceId: 'source'),
      throwsA(same(error)),
    );
  });

  test('分阶段启动先返回控制，START_APP不被媒体等待阻塞', () async {
    final native = StagedScrcpyApi();
    final session = await ScrcpyClient(native).createSession(device);
    final control = session.startControl();
    native.control.complete(controlInfo);
    expect((await control).mediaReady, isFalse);
    expect(session.info!.source, isNull);
    var mediaDone = false;
    final ready = session.awaitMedia(generation: 17).then((value) {
      mediaDone = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    await session.sendControl(const ScrcpyStartApp('org.example.test'));
    expect(native.controls.single, isA<ScrcpyStartApp>());
    expect(mediaDone, isFalse);
    expect(native.mediaGenerations, [17]);
    native.media.complete(info);
    expect((await ready).mediaReady, isTrue);
    expect(native.controlCalls, 1);
    expect(native.startCalls, 0);
    await session.awaitMedia(generation: 23);
    expect(native.mediaGenerations, [17, 23]);
    await session.close();
  });

  test('便捷start复用同一控制阶段，关闭后迟到媒体不会复活', () async {
    final native = StagedScrcpyApi();
    final session = await ScrcpyClient(native).createSession(device);
    final control = session.startControl();
    final starting = session.start();
    final rejected = expectLater(
      starting,
      throwsA(isA<ScrcpyException>().having((e) => e.code, 'code', 'closed')),
    );
    native.control.complete(controlInfo);
    await control;
    await Future<void>.delayed(Duration.zero);
    expect(native.controlCalls, 1);
    await session.close();
    native.media.complete(info);
    await rejected;
    expect(native.stopped, ['capture']);
  });

  test('分阶段控制取消先关闭捕获，迟到控制结果被拒绝', () async {
    final native = StagedScrcpyApi();
    final session = await ScrcpyClient(native).createSession(device);
    final cancellation = AdbCancellation();
    final opening = session.startControl(cancellation: cancellation);
    final rejected = expectLater(
      opening,
      throwsA(
        isA<ScrcpyException>().having((e) => e.code, 'code', 'cancelled'),
      ),
    );
    cancellation.cancel();
    await rejected;
    expect(native.stopped, ['capture']);
    native.control.complete(controlInfo);
    await Future<void>.delayed(Duration.zero);
    expect(
      () => session.sendControl(const ScrcpyRotate()),
      throwsA(isA<ScrcpyException>()),
    );
  });

  test('连接排空先核对宿主归属，并等待原生确认后才完成', () async {
    final native = FakeScrcpyApi()..draining = Completer<void>();
    final owner = Object();
    final client = ScrcpyClient(native, nativeOwner: owner);
    await expectLater(
      client.drainConnection(device),
      throwsA(
        isA<ScrcpyException>().having(
          (e) => e.code,
          'code',
          'foreign_connection',
        ),
      ),
    );
    expect(native.drainedConnections, isEmpty);
    final paired = AdbDevice(
      id: 'claimed-connection',
      serial: 'serial',
      state: 'device',
      nativeOwner: owner,
    );
    var completed = false;
    final draining = client
        .drainConnection(paired)
        .then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(native.drainedConnections, ['claimed-connection']);
    expect(completed, isFalse);
    native.draining!.complete();
    await draining;
    expect(completed, isTrue);
    expect(native.stopped, isEmpty);
    expect(native.connectionId, isNull);
  });

  test('连接排空的未知清理不伪报成功，同一句柄仍可重试', () async {
    final native = FakeScrcpyApi()..draining = Completer<void>();
    final client = ScrcpyClient(native);
    final failure = const ScrcpyException('capture_cleanup_unverified');
    final draining = client.drainConnection(device);
    final rejected = expectLater(draining, throwsA(same(failure)));
    native.draining!.completeError(failure);
    await rejected;
    native.draining = null;
    await client.drainConnection(device);
    expect(native.drainedConnections, ['connection', 'connection']);
  });

  test('原生宿主拒绝其他库和无归属的设备，配套身份可以创建捕获', () async {
    final native = FakeScrcpyApi();
    final owner = Object();
    final client = ScrcpyClient(native, nativeOwner: owner);
    for (final candidate in [
      device,
      AdbDevice(
        id: 'connection',
        serial: 'serial',
        state: 'device',
        nativeOwner: Object(),
      ),
    ]) {
      await expectLater(
        client.createSession(candidate),
        throwsA(
          isA<ScrcpyException>().having(
            (e) => e.code,
            'code',
            'foreign_connection',
          ),
        ),
      );
      expect(native.connectionId, isNull);
    }
    final session = await client.createSession(
      AdbDevice(
        id: 'connection',
        serial: 'serial',
        state: 'device',
        nativeOwner: owner,
      ),
    );
    expect(native.connectionId, 'connection');
    await session.close();
  });

  test('事件订阅取消只释放观察者，暂停的观察者不阻塞捕获关闭', () async {
    final native = FakeScrcpyApi();
    final session = await ScrcpyClient(native).createSession(device);
    final observed = <ScrcpyEvent>[];
    final first = session.events.listen(observed.add);
    native.eventControllers.single.add(const ScrcpyClipboardChanged('text'));
    await Future<void>.delayed(Duration.zero);
    expect((observed.single as ScrcpyClipboardChanged).text, 'text');
    await first.cancel();
    expect(native.observerCancellations, 1);
    expect(native.stopped, isEmpty);

    final second = session.events.listen(observed.add)..pause();
    await session.close().timeout(const Duration(seconds: 1));
    expect(native.observerCancellations, 2);
    expect(native.stopped, ['capture']);
    await second.cancel();
  });

  test('观察清理失败后只重试观察者，不再次停止已释放捕获', () async {
    final native = FakeScrcpyApi()..observerCancelFails = true;
    final session = await ScrcpyClient(native).createSession(device);
    final observer = session.events.listen((_) {});
    await expectLater(session.close(), throwsStateError);
    expect(native.stopped, ['capture']);
    await session.close();
    expect(native.stopped, ['capture']);
    expect(native.observerCancellations, 2);
    await observer.cancel();
  });

  test('捕获停止失败后只重试捕获，不重复取消已释放观察者', () async {
    final native = FakeScrcpyApi()..stopFailures = 1;
    final session = await ScrcpyClient(native).createSession(device);
    final observer = session.events.listen((_) {});
    await expectLater(session.close(), throwsStateError);
    expect(native.stopped, ['capture']);
    expect(native.observerCancellations, 1);
    await session.close();
    expect(native.stopped, ['capture', 'capture']);
    expect(native.observerCancellations, 1);
    await observer.cancel();
  });

  test('观察者连续取消失败仍保留唯一捕获释放确认', () async {
    final native = FakeScrcpyApi()..observerCancelFailures = 2;
    final session = await ScrcpyClient(native).createSession(device);
    final observer = session.events.listen((_) {});
    await expectLater(session.close(), throwsStateError);
    await expectLater(session.close(), throwsStateError);
    await session.close();
    expect(native.stopped, ['capture']);
    expect(native.observerCancellations, 3);
    await observer.cancel();
  });

  test('附着会话连续关闭失败保留同一观察者，重试不停止共享捕获', () async {
    final native = FakeScrcpyApi()..observerCancelFailures = 2;
    final session = await ScrcpyClient(native).attach('capture');
    final subscription = session.events.listen((_) {});
    await expectLater(session.close(), throwsStateError);
    await expectLater(session.close(), throwsStateError);
    expect(native.observerCancellations, 2);
    expect(native.stopped, isEmpty);
    await session.close();
    expect(native.observerCancellations, 3);
    expect(native.eventControllers, hasLength(1));
    await subscription.cancel();
    expect(native.observerCancellations, 3);
  });

  test('附着使用渲染器代次，返回其他捕获时拒绝控制资格', () async {
    final native = FakeScrcpyApi();
    final session = await ScrcpyClient(native)
        .attach('capture', generation: 17);
    expect(native.inspectGeneration, 17);
    await session.close();
    await expectLater(
      ScrcpyClient(native).attach('replaced'),
      throwsA(
        isA<ScrcpyException>().having((e) => e.code, 'code', 'stale_capture'),
      ),
    );
  });

  test('启动失败保留原始异常，原生回收失败仍允许显式重试', () async {
    final native = FakeScrcpyApi()..stopFailures = 1;
    final session = await ScrcpyClient(native).createSession(device);
    final starting = session.start();
    final failed = expectLater(
      starting,
      throwsA(isA<ScrcpyException>().having((e) => e.code, 'code', 'encoder')),
    );
    native.starting.completeError(const ScrcpyException('encoder'));
    await failed;
    await session.close();
    expect(native.stopped, ['capture', 'capture']);
  });

  test('附着已有捕获只检查同一来源，关闭观察不停止业务所有者', () async {
    final native = FakeScrcpyApi();
    final session = await ScrcpyClient(native).attach('capture');
    expect(session.info!.source!.sourceId, 'source');
    expect((await session.start()).id, 'capture');
    expect(native.startCalls, 0);
    await session.sendControl(const ScrcpyRotate());
    await session.close();
    expect(native.stopped, isEmpty);
    expect(native.connectionId, isNull);
  });

  test('启动成功后取消旧请求不会停止已交付的会话', () async {
    final native = FakeScrcpyApi();
    final session = await ScrcpyClient(native).createSession(device);
    final cancellation = AdbCancellation();
    native.starting.complete(info);
    await session.start(cancellation: cancellation);
    cancellation.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(native.stopped, isEmpty);
    await session.close();
  });

  test('关闭启动中的会话立即撤销原生捕获，迟到启动不会复活句柄', () async {
    final native = FakeScrcpyApi();
    final session = await ScrcpyClient(native).createSession(device);
    final starting = session.start();
    final rejected = expectLater(
      starting,
      throwsA(isA<ScrcpyException>().having((e) => e.code, 'code', 'closed')),
    );

    await session.close();
    expect(native.stopped, ['capture']);
    native.starting.complete(info);
    await rejected;
    await session.close();
    expect(native.stopped, ['capture']);
    expect(
      () => session.sendControl(const ScrcpyRotate()),
      throwsA(isA<ScrcpyException>()),
    );
  });

  test('启动取消只关闭所属捕获，不触及共享 ADB 连接', () async {
    final native = FakeScrcpyApi();
    final session = await ScrcpyClient(native).createSession(device);
    final cancellation = AdbCancellation();
    final starting = session.start(cancellation: cancellation);
    final rejected = expectLater(starting, throwsA(isA<ScrcpyException>()));
    cancellation.cancel();
    await rejected;
    expect(native.stopped, ['capture']);
    native.starting.complete(info);
  });

  test('关闭失败保留重试资格，后续控制仍然拒绝', () async {
    final native = FakeScrcpyApi()..stopFailures = 1;
    final session = await ScrcpyClient(native).createSession(device);
    await expectLater(session.close(), throwsStateError);
    expect(
      () => session.sendControl(const ScrcpyRotate()),
      throwsA(isA<ScrcpyException>()),
    );
    await session.close();
    expect(native.stopped, ['capture', 'capture']);
  });

  test('创建期间取消回收迟到登记的捕获', () async {
    final native = FakeScrcpyApi()..registration = Completer<String>();
    final cancellation = AdbCancellation();
    final creating = ScrcpyClient(native)
        .createSession(device, cancellation: cancellation);
    final rejected = expectLater(creating, throwsA(isA<ScrcpyException>()));
    cancellation.cancel();
    native.registration!.complete('capture');
    await rejected;
    expect(native.stopped, ['capture']);
    expect(native.startCalls, 0);
  });

  test('创建取消后清理失败时把唯一捕获所有权交还异常调用者', () async {
    final native = FakeScrcpyApi()
      ..registration = Completer<String>()
      ..stopFailures = 1;
    final cancellation = AdbCancellation();
    final creating = ScrcpyClient(native)
        .createSession(device, cancellation: cancellation);
    final failure = expectLater(
      creating,
      throwsA(isA<ScrcpyCreationCleanupFailure>()),
    );
    cancellation.cancel();
    native.registration!.complete('capture');
    ScrcpySession? retained;
    try {
      await creating;
    } on ScrcpyCreationCleanupFailure catch (error) {
      retained = error.session;
    }
    await failure;
    await retained!.close();
    expect(native.stopped, ['capture', 'capture']);
  });

  test('配置对应上游参数，控制和原生源保持类型', () async {
    final native = FakeScrcpyApi();
    final session = await ScrcpyClient(native).createSession(
      device,
      options: const ScrcpyOptions(
        videoCodec: ScrcpyVideoCodec.h265,
        maxSize: 1280,
        maxFps: 30,
        videoBitRate: 4000000,
      ),
    );
    native.starting.complete(info);
    expect((await session.start()).source!.sourceId, 'source');
    await session.sendControl(
      const ScrcpyKey(action: ScrcpyKeyAction.down, keycode: 4),
    );
    expect(native.connectionId, 'connection');
    expect(native.options!.videoCodec, ScrcpyVideoCodec.h265);
    expect(native.controls.single, isA<ScrcpyKey>());
    await session.close();
  });
}

const info = ScrcpySessionInfo(
  id: 'capture',
  deviceName: 'Android',
  videoCodec: ScrcpyVideoCodec.h264,
  width: 1080,
  height: 1920,
  source: ScrcpyNativeSource(
    sourceId: 'source',
    generation: 1,
    codec: 'h264',
    width: 1080,
    height: 1920,
    attachAddress: 1,
    detachAddress: 2,
  ),
);

class SourceStatusScrcpyApi extends FakeScrcpyApi
    implements NativeScrcpySourceStatusApi {
  final statusQueries = <(String, String, String)>[];
  ScrcpyException? statusError;
  ScrcpySourceStatus status = const ScrcpySourceStatus(
    captureRef: 'capture',
    sourceId: 'source',
    generation: 17,
    kind: ScrcpySourceKind.audio,
    codec: 'pcm_s16le',
    status: ScrcpySourceState.closed,
    packets: 4,
    bytes: 1024,
  );

  @override
  Future<ScrcpySourceStatus> sourceStatus({
    required String connectionId,
    required String captureRef,
    required String sourceId,
  }) async {
    statusQueries.add((connectionId, captureRef, sourceId));
    if (statusError case final error?) throw error;
    return status;
  }
}

class FakeScrcpyApi implements NativeScrcpyApi, NativeScrcpyConnectionApi {
  final starting = Completer<ScrcpySessionInfo>();
  Completer<String>? registration;
  final stopped = <String>[];
  final _releasedCaptures = <String>{};
  final controls = <ScrcpyControlMessage>[];
  String? connectionId;
  ScrcpyOptions? options;
  int startCalls = 0;
  int stopFailures = 0;
  int? inspectGeneration;
  final eventControllers = <StreamController<ScrcpyEvent>>[];
  int observerCancellations = 0;
  bool observerCancelFails = false;
  int observerCancelFailures = 0;
  Completer<void>? draining;
  final drainedConnections = <String>[];

  @override
  Future<void> drainConnection(String connectionId) async {
    drainedConnections.add(connectionId);
    await draining?.future;
  }

  @override
  Future<String> createSession({
    required String connectionId,
    required ScrcpyOptions options,
  }) async {
    this.connectionId = connectionId;
    this.options = options;
    return registration?.future ?? 'capture';
  }

  @override
  Future<ScrcpySessionInfo> startSession(String sessionId) {
    startCalls++;
    return starting.future;
  }

  @override
  Future<ScrcpySessionInfo> inspect(
    String captureRef, {
    int generation = 1,
  }) async {
    inspectGeneration = generation;
    return info;
  }

  @override
  Future<void> stopSession(String sessionId) async {
    if (_releasedCaptures.contains(sessionId)) {
      throw const ScrcpyException('stale_capture');
    }
    stopped.add(sessionId);
    if (stopFailures-- > 0) throw StateError('cleanup');
    _releasedCaptures.add(sessionId);
  }

  @override
  Future<ScrcpyControlReceipt> sendControl(
    String sessionId,
    ScrcpyControlMessage message,
  ) async {
    controls.add(message);
    return const ScrcpyControlReceipt(ScrcpyControlCompletion.admitted);
  }

  @override
  ScrcpyEventObserver openEvents(String sessionId) {
    final controller = StreamController<ScrcpyEvent>();
    eventControllers.add(controller);
    final iterator = StreamIterator(controller.stream);
    return ScrcpyEventObserver(
      open: () async => 'observer-${eventControllers.length}',
      next: (_) async => await iterator.moveNext() ? iterator.current : null,
      cancel: (_) async {
        observerCancellations++;
        if (observerCancelFails || observerCancelFailures-- > 0) {
          observerCancelFails = false;
          throw StateError('observer cleanup');
        }
        await iterator.cancel();
        unawaited(controller.close());
      },
    );
  }
}

const controlInfo = ScrcpySessionInfo(
  id: 'capture',
  deviceName: 'Android',
  videoCodec: ScrcpyVideoCodec.h264,
  width: 1080,
  height: 1920,
  mediaReady: false,
  controlReady: true,
);

final class StagedScrcpyApi extends FakeScrcpyApi
    implements NativeScrcpyStagedApi {
  final control = Completer<ScrcpySessionInfo>();
  final media = Completer<ScrcpySessionInfo>();
  final mediaGenerations = <int>[];
  int controlCalls = 0;
  @override
  Future<ScrcpySessionInfo> startControl(String sessionId) {
    controlCalls++;
    return control.future;
  }

  @override
  Future<ScrcpySessionInfo> awaitMedia(
    String captureRef, {
    int generation = 1,
  }) {
    mediaGenerations.add(generation);
    return media.future;
  }

  @override
  Future<ScrcpyProcessInfo> processInfo(String captureRef) async =>
      const ScrcpyProcessInfo(
        pid: 42,
        started: 99,
        logTail: [],
        truncated: false,
      );
}
