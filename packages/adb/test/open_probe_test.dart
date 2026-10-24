import 'dart:async';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

const _device = AdbDevice(id: 'connection', serial: 'probe', state: 'device');
const _facts = AdbOpenProbeFacts(
  layer: AdbOpenProbeLayer.directAdb,
  openWritten: true,
  outcome: AdbOpenProbeOutcome.rejected,
  inboundActivity: 'opaque-mark',
);

void main() {
  test('旧适配器未知入站标记为空，不伪造 OPEN 探测支持', () async {
    const facts = AdbConnectionFacts(
      officialServer: false,
      closed: false,
      features: [],
    );
    expect(facts.inboundActivity, isNull);
    final services = NativeAdbClient(_LegacyApi(), '').services;
    await expectLater(
      services.createOpenProbe(
        _device,
        service: 'sync:',
        timeout: const Duration(seconds: 1),
      ),
      throwsA(_code('unsupported')),
    );
    await services.close();
  });

  test('预取消不发原生创建，非法参数也不登记操作', () async {
    final api = _Api();
    final services = NativeAdbClient(api, '').services;
    addTearDown(services.close);
    await expectLater(
      services.createOpenProbe(
        _device,
        service: 'sync:',
        timeout: const Duration(seconds: 1),
        cancellation: AdbCancellation()..cancel(),
      ),
      throwsA(_code('cancelled')),
    );
    for (final service in ['', 'sync:\u0000', '界' * 22000]) {
      await expectLater(
        services.createOpenProbe(
          _device,
          service: service,
          timeout: const Duration(seconds: 1),
        ),
        throwsArgumentError,
      );
    }
    await expectLater(
      services.createOpenProbe(
        _device,
        service: 'sync:',
        timeout: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(api.creates, isEmpty);
  });

  test('事实终态不自动丢弃关闭责任，关闭首败后同句柄重试且共享服务仍可写', () async {
    final api = _Api()..failures = 1;
    final services = NativeAdbClient(api, '').services;
    final shell = await services.exec(_device, 'cat');
    final probe = await services.createOpenProbe(
      _device,
      service: 'sync:',
      timeout: const Duration(milliseconds: 731),
    );
    api.result.complete(_facts);
    expect(await probe.result, same(_facts));
    expect(api.closes, isEmpty);
    expect(api.creates, [('connection', 'sync:', 731)]);
    await expectLater(probe.close(), throwsA(_code('adb_cleanup_unconfirmed')));
    await shell.write(Uint8List.fromList([7]));
    await probe.close();
    await probe.close();
    expect(api.closes, ['probe', 'probe']);
    expect(api.written, [7]);
    await services.close();
    expect(api.cancelled, ['parallel-shell']);
  });

  test('结果失败保留原类型和精确回收责任，不关闭共享 Client', () async {
    final api = _Api();
    final services = NativeAdbClient(api, '').services;
    final probe = await services.createOpenProbe(
      _device,
      service: 'sync:',
      timeout: const Duration(seconds: 1),
    );
    const failure = AdbException('protocol_error', 'bad status');
    final rejected = expectLater(probe.result, throwsA(same(failure)));
    api.result.completeError(failure);
    await rejected;
    await services.close();
    expect(api.closes, ['probe']);
    expect(api.cancelled, isEmpty);
  });

  test('创建中取消仍取得迟到句柄，等待真实回收后才结束创建', () async {
    final api = _Api()
      ..creation = Completer<String>()
      ..drain = Completer<void>();
    final services = NativeAdbClient(api, '').services;
    final token = AdbCancellation();
    final opening = services.createOpenProbe(
      _device,
      service: 'sync:',
      timeout: const Duration(seconds: 1),
      cancellation: token,
    );
    final rejected = expectLater(opening, throwsA(_code('cancelled')));
    await api.started.future;
    token.cancel();
    api.creation!.complete('late-probe');
    await api.closing.future;
    var completed = false;
    unawaited(rejected.then((_) => completed = true));
    expect(completed, isFalse);
    expect(api.closes, ['late-probe']);
    api.drain!.complete();
    await rejected;
    await services.close();
    expect(api.closes, ['late-probe']);
  });

  test('facade 关闭等待迟到创建且失败保留重试权，关闭后不再准入', () async {
    final api = _Api()
      ..creation = Completer<String>()
      ..failures = 2;
    final services = NativeAdbClient(api, '').services;
    final opening = services.createOpenProbe(
      _device,
      service: 'sync:',
      timeout: const Duration(seconds: 1),
    );
    final rejected = expectLater(
      opening,
      throwsA(isA<AdbOpenProbeCleanupFailure>()),
    );
    await api.started.future;
    final closing = expectLater(
      services.close(),
      throwsA(_code('adb_cleanup_unconfirmed')),
    );
    api.creation!.complete('late-probe');
    await rejected;
    await closing;
    expect(api.closes, ['late-probe', 'late-probe']);
    await services.close();
    expect(api.closes, ['late-probe', 'late-probe', 'late-probe']);
    await expectLater(
      services.createOpenProbe(
        _device,
        service: 'sync:',
        timeout: const Duration(seconds: 1),
      ),
      throwsA(_code('closed')),
    );
  });

  test('创建中取消且关闭首败交还精确 owner，可单独重试而不停止并行 shell', () async {
    final api = _Api()
      ..creation = Completer<String>()
      ..failures = 1;
    final services = NativeAdbClient(api, '').services;
    final shell = await services.exec(_device, 'cat');
    final token = AdbCancellation();
    AdbOpenProbeCleanupFailure? failure;
    final opening = services.createOpenProbe(
      _device,
      service: 'sync:',
      timeout: const Duration(seconds: 1),
      cancellation: token,
    );
    final rejected = expectLater(
      opening,
      throwsA(
        isA<AdbOpenProbeCleanupFailure>().having(
          (error) {
            failure = error;
            return error.cause;
          },
          'cause',
          _code('adb_cleanup_unconfirmed'),
        ),
      ),
    );
    await api.started.future;
    token.cancel();
    api.creation!.complete('late-cancelled-probe');
    await rejected;
    expect(failure!.probe.id, 'late-cancelled-probe');
    await shell.write(Uint8List.fromList([1]));
    await failure!.probe.close();
    expect(
      (await failure!.probe.result).outcome,
      AdbOpenProbeOutcome.cancelled,
    );
    await shell.write(Uint8List.fromList([2]));
    expect(api.closes, ['late-cancelled-probe', 'late-cancelled-probe']);
    expect(api.cancelled, isEmpty);
    expect(api.written, [1, 2]);
    await services.close();
    expect(api.cancelled, ['parallel-shell']);
  });

  test('取消只回收本次探针，关闭失败由显式 close 重试并等待实际排空', () async {
    final api = _Api()..failures = 1;
    final services = NativeAdbClient(api, '').services;
    final token = AdbCancellation();
    final probe = await services.createOpenProbe(
      _device,
      service: 'sync:',
      timeout: const Duration(seconds: 1),
      cancellation: token,
    );
    token.cancel();
    final firstClose = probe.close();
    await api.closing.future;
    // 与自动关闭共用同一 Future，必须看见真实首败，而非直接尝试新的关闭。
    await expectLater(firstClose, throwsA(_code('adb_cleanup_unconfirmed')));
    api.drain = Completer<void>();
    final retry = probe.close();
    expect(identical(probe.close(), retry), isTrue);
    api.drain!.complete();
    await retry;
    expect((await probe.result).outcome, AdbOpenProbeOutcome.cancelled);
    await services.close();
    expect(api.closes, ['probe', 'probe']);
    expect(api.cancelled, isEmpty);
  });
}

Matcher _code(String code) =>
    isA<AdbException>().having((error) => error.code, 'code', code);

class _LegacyApi implements NativeAdbApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Api extends _LegacyApi implements NativeAdbOpenProbeApi {
  final creates = <(String, String, int)>[];
  final closes = <String>[];
  final cancelled = <String>[];
  final written = <int>[];
  final started = Completer<void>();
  final closing = Completer<void>();
  final result = Completer<AdbOpenProbeFacts>();
  Completer<String>? creation;
  Completer<void>? drain;
  int failures = 0;

  @override
  Future<String> createOpenProbe(
    String connectionId,
    String service,
    int timeoutMs,
  ) async {
    creates.add((connectionId, service, timeoutMs));
    started.complete();
    return creation?.future ?? 'probe';
  }

  @override
  Future<AdbOpenProbeFacts> openProbeResult(String id) => result.future;
  @override
  Future<void> closeOpenProbe(String id, int timeoutMs) async {
    closes.add(id);
    if (!closing.isCompleted) closing.complete();
    if (failures > 0) {
      failures--;
      throw const AdbException('adb_cleanup_unconfirmed');
    }
    await drain?.future;
    if (!result.isCompleted) {
      result.complete(
        const AdbOpenProbeFacts(
          layer: AdbOpenProbeLayer.directAdb,
          openWritten: false,
          outcome: AdbOpenProbeOutcome.cancelled,
          inboundActivity: '0',
        ),
      );
    }
  }

  @override
  Future<String> service(
    String id,
    AdbServiceRequest request,
    int timeoutMs,
  ) async => 'parallel-shell';
  @override
  Future<void> write(String id, AdbServiceInput input) async =>
      written.addAll(input.bytes);
  @override
  Future<void> cancel(String id) async => cancelled.add(id);
}
