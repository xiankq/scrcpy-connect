import 'dart:async';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/connection/connection_owner.dart';
import 'package:scrcpy_connect/connection/connection_policy.dart';
import 'package:scrcpy_connect/connection/device_health_coordinator.dart';

void main() {
  late _Fixture f;
  setUp(() => f = _Fixture());
  tearDown(() async {
    f.api.failClose = false;
    await f.health.close();
  });

  test('实际closed在禁用探测时仍退休，并允许活动停止反向排空监测', () async {
    await f.health.close();
    f.createHealth(enabled: false);
    f.api.closed = true;
    f.attach('a');
    await f.health.checkNow();
    expect(f.retired, ['a:transport_closed']);
    expect(f.api.opened, isEmpty);
  });

  test('持续入站活动跳过探测，闲置后拒绝响应也重置失败', () async {
    f.attach('a');
    await f.health.checkNow();
    f.elapsed += const Duration(seconds: 11);
    f.api.activity = '1';
    await f.health.checkNow();
    expect(f.api.opened, isEmpty);
    f.elapsed += const Duration(seconds: 11);
    f.api.outcome = AdbOpenProbeOutcome.rejected;
    await f.health.checkNow();
    expect(f.api.opened, hasLength(1));
    expect(f.api.released, ['probe-0']);
    expect(f.retired, isEmpty);
  });

  test('只有实际写出且无响应达到阈值才退休，退休没有自锁', () async {
    f.attach('a');
    await f.health.checkNow();
    f.elapsed += const Duration(seconds: 11);
    f.api.outcome = AdbOpenProbeOutcome.timedOut;
    await f.health.checkNow();
    expect(f.retired, isEmpty);
    await f.health.checkNow();
    expect(f.retired, ['a:health_response_timeout']);
    expect(f.api.released, ['probe-0', 'probe-1']);
  });

  test('本机未写出容量取消及不确定错误不积累对端失败', () async {
    f.attach('a');
    await f.health.checkNow();
    f.elapsed += const Duration(seconds: 11);
    for (final outcome in [
      AdbOpenProbeOutcome.notWritten,
      AdbOpenProbeOutcome.localCapacity,
      AdbOpenProbeOutcome.cancelled,
      AdbOpenProbeOutcome.io,
      AdbOpenProbeOutcome.protocol,
    ]) {
      f.api.outcome = outcome;
      for (var i = 0; i < 3; i++) {
        await f.health.checkNow();
      }
    }
    expect(f.retired, isEmpty);
    expect(f.api.opened, hasLength(15));
  });

  test('探测期间其他流真实入站阻止把响应超时当整条连接失活', () async {
    f.attach('a');
    await f.health.checkNow();
    f.elapsed += const Duration(seconds: 11);
    f.api.outcome = AdbOpenProbeOutcome.timedOut;
    f.api.resultActivity = '1';
    await f.health.checkNow();
    f.api.activity = '1';
    await f.health.checkNow();
    expect(f.api.opened, hasLength(1));
    expect(f.retired, isEmpty);
  });

  test('同连接不重叠且另设备不等阻塞结果，停止等待真实探针释放', () async {
    final a = f.attach('a');
    f.attach('b');
    await f.health.checkNow();
    f.elapsed += const Duration(seconds: 11);
    f.api.blockConnection = a.device.id;
    final tick = f.health.checkNow();
    await f.api.probeStarted.future;
    final again = f.health.checkNow();
    await f.api.otherReleased.future;
    expect(f.api.opened.where((id) => id == 'a'), hasLength(1));
    await f.health.stopConnection('a', a);
    await Future.wait([tick, again]);
    expect(f.api.released, contains('probe-0'));
    expect(f.retired, isEmpty);
  });

  test('迟到创建必须真实交出精确句柄并关闭后stop才返回', () async {
    final connection = f.attach('a');
    await f.health.checkNow();
    f.elapsed += const Duration(seconds: 11);
    f.api.createGate = Completer<void>();
    final checking = f.health.checkNow();
    await f.api.createStarted.future;
    var stopped = false;
    final stopping = f.health.stopConnection('a', connection).then((_) {
      stopped = true;
    });
    // Dart 调用尚未交付本机句柄时不能假装已经停止。
    await Future<void>.value();
    expect(stopped, isFalse);
    f.api.createGate!.complete();
    await Future.wait([checking, stopping]);
    expect(f.api.released, ['probe-0']);
    expect(f.retired, isEmpty);
  });

  test('关闭失败保留同探针重试，不开始后继探针也不关闭共享client', () async {
    final a = f.attach('a');
    await f.health.checkNow();
    f.elapsed += const Duration(seconds: 11);
    f.api.failClose = true;
    await expectLater(f.health.checkNow(), throwsStateError);
    expect(f.api.opened, hasLength(1));
    await expectLater(f.health.checkNow(), throwsStateError);
    expect(f.api.opened, hasLength(1));
    await expectLater(f.health.stopConnection('a', a), throwsStateError);
    f.api.failClose = false;
    await f.health.stopConnection('a', a);
    expect(f.api.released, ['probe-0']);
    expect(f.client.closed, isFalse);
  });

  test('迟到结果不能退休后继，同设备旧stop也不结束新探针', () async {
    final old = f.attach('a');
    await f.health.checkNow();
    f.elapsed += const Duration(seconds: 11);
    f.api.blockConnection = 'a';
    final checking = f.health.checkNow();
    await f.api.probeStarted.future;
    final replacement = DeviceConnection(
      client: f.client,
      device: const AdbDevice(id: 'replacement', serial: 'a', state: 'device'),
    );
    f.current['a'] = replacement;
    f.health.start('a', replacement);
    await f.health.stopConnection('a', old);
    await checking;
    expect(f.retired, isEmpty);
    await f.health.checkNow();
    expect(f.current['a'], same(replacement));
  });

  test('相同Dart对象的物理连接事实变化须退休，未知身份不能探测冒充支持', () async {
    f.attach('a');
    await f.health.checkNow();
    f.api.physicalId = 'replacement';
    await f.health.checkNow();
    expect(f.retired, ['a:health_connection_identity_changed']);
    f.api.physicalId = null;
    f.attach('b');
    await f.health.checkNow();
    expect(f.retired.last, 'b:health_connection_identity_unavailable');
    expect(f.api.opened, isEmpty);
  });

  test('探测后物理身份变化不能用有效响应替后继授予健康', () async {
    f.attach('a');
    await f.health.checkNow();
    f.elapsed += const Duration(seconds: 11);
    f.api.afterResult = () => f.api.physicalId = 'new-physical';
    await f.health.checkNow();
    expect(f.retired, ['a:health_connection_identity_changed']);
    expect(f.api.released, ['probe-0']);
  });

  test('退休失败保留原连接责任，后续核对及close可以重试', () async {
    f.attach('a');
    f.api.closed = true;
    f.failRetire = true;
    await expectLater(f.health.checkNow(), throwsStateError);
    expect(f.retired, isEmpty);
    f.failRetire = false;
    await f.health.close();
    expect(f.retired, ['a:transport_closed']);
  });
}

final class _Fixture {
  _Fixture() {
    client = _Client(api);
    createHealth();
  }
  final api = _Api();
  late final _Client client;
  late DeviceHealthCoordinator health;
  final current = <String, DeviceConnection>{};
  final retired = <String>[];
  Duration elapsed = Duration.zero;
  bool failRetire = false;

  void createHealth({bool enabled = true}) {
    health = DeviceHealthCoordinator(
      current: (id) => current[id],
      policy: ConnectionPolicy(
        monitorInterval: const Duration(days: 1),
        healthEnabled: enabled,
      ),
      elapsed: () => elapsed,
      retire: (id, connection, {required reason}) async {
        // 真实组合中 ConnectionOwner.stopActivities 会回到相同监测所有者。
        await health.stopConnection(id, connection);
        if (failRetire) throw StateError('retirement pending');
        if (identical(current[id], connection)) current.remove(id);
        retired.add('$id:$reason');
      },
    );
  }

  DeviceConnection attach(String id) {
    final connection = DeviceConnection(
      client: client,
      device: AdbDevice(id: id, serial: id, state: 'device'),
    );
    current[id] = connection;
    health.start(id, connection);
    return connection;
  }
}

final class _Client implements AdbClient {
  _Client(_Api api) {
    services = AdbServices(() => api, (device) async => device, () {});
  }
  bool closed = false;
  @override
  late final AdbServices services;
  @override
  Future<void> close() async => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Api implements NativeAdbApi, NativeAdbOpenProbeApi {
  bool closed = false, failClose = false;
  String activity = '0';
  String? physicalId = 'physical';
  String? resultActivity;
  void Function()? afterResult;
  String? blockConnection;
  Completer<void>? createGate;
  final createStarted = Completer<void>();
  AdbOpenProbeOutcome outcome = AdbOpenProbeOutcome.okay;
  final opened = <String>[];
  final released = <String>[];
  final pending = <String, Completer<AdbOpenProbeFacts>>{};
  final probeStarted = Completer<void>();
  final otherReleased = Completer<void>();

  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async =>
      AdbConnectionFacts(
        officialServer: false,
        closed: closed,
        connectionId: physicalId,
        features: const [],
        inboundActivity: activity,
      );

  @override
  Future<String> createOpenProbe(
    String id,
    String service,
    int timeoutMs,
  ) async {
    expect(service, 'sync:');
    final probeId = 'probe-${opened.length}';
    opened.add(id);
    if (!createStarted.isCompleted) createStarted.complete();
    await createGate?.future;
    if (id == blockConnection) {
      pending[probeId] = Completer<AdbOpenProbeFacts>();
      if (!probeStarted.isCompleted) probeStarted.complete();
    }
    return probeId;
  }

  AdbOpenProbeFacts facts(AdbOpenProbeOutcome result) => AdbOpenProbeFacts(
    layer: AdbOpenProbeLayer.directAdb,
    openWritten:
        result != AdbOpenProbeOutcome.notWritten &&
        result != AdbOpenProbeOutcome.localCapacity,
    outcome: result,
    inboundActivity: resultActivity ?? activity,
  );

  @override
  Future<AdbOpenProbeFacts> openProbeResult(String id) async {
    if (pending[id] case final result?) return result.future;
    final result = facts(outcome);
    if (resultActivity != null) activity = resultActivity!;
    afterResult?.call();
    return result;
  }

  @override
  Future<void> closeOpenProbe(String id, int timeoutMs) async {
    if (failClose) throw StateError('probe cleanup not confirmed');
    if (pending[id] case final result?) {
      if (!result.isCompleted) {
        result.complete(facts(AdbOpenProbeOutcome.cancelled));
      }
    }
    if (!released.contains(id)) released.add(id);
    if (id == 'probe-1' && !otherReleased.isCompleted) otherReleased.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
