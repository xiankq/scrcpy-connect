import 'dart:async';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/connection/device_discovery.dart';

void main() {
  late _Fixture fixture;
  setUp(() => fixture = _Fixture());
  tearDown(() async => fixture.owner?.close());

  test('执行三类 PTR→SRV→A/AAAA 查询，不把名称或端口当作信任', () async {
    fixture.advertise('phone', AdbDiscoveryKind.tlsConnect);
    fixture.advertise('pairing', AdbDiscoveryKind.pairing, port: 37001);
    fixture.advertise('legacy', AdbDiscoveryKind.tcpConnect, port: 5555);
    final discovery = fixture.create();
    final endpoints = await discovery.scan();
    expect(
      endpoints.map((e) => e.kind).toSet(),
      AdbDiscoveryKind.values.toSet(),
    );
    expect(endpoints.every(discovery.isCurrent), isTrue);
    expect(
      fixture.clients.single.queries,
      containsAll([
        '_adb-tls-pairing._tcp.local/12',
        '_adb-tls-connect._tcp.local/12',
        '_adb._tcp.local/12',
        'phone._adb-tls-connect._tcp.local/33',
        'phone.local/1',
        'phone.local/28',
      ]),
    );
    expect(fixture.sockets.single.closed, isTrue);
  });

  test('只接受本次二维码精确 instance，仍查询配对服务并保留真正配对端口', () async {
    fixture.advertise('studio-this', AdbDiscoveryKind.pairing, port: 37001);
    fixture.advertise('studio-other', AdbDiscoveryKind.pairing, port: 37002);
    fixture.advertise('connect', AdbDiscoveryKind.tlsConnect);
    final result = await fixture.create().scan(pairingInstance: 'studio-this');
    expect(result.single.instance, 'studio-this');
    expect(result.single.port, 37001);
    expect(fixture.clients.single.queries.where((q) => q.endsWith('/12')), [
      '_adb-tls-pairing._tcp.local/12',
    ]);
    expect(
      fixture.clients.single.queries,
      isNot(contains('studio-other._adb-tls-pairing._tcp.local/33')),
    );
  });

  test('GUID 仅接受精确值与数字冲突别名，拒绝前缀和任意后缀', () {
    expect(DeviceDiscovery.matchesGuid('adb-x', 'adb-x'), isTrue);
    expect(DeviceDiscovery.matchesGuid('adb-x (12)', 'adb-x'), isTrue);
    for (final value in [
      'adb-xy',
      'adb-x-12',
      'adb-x ()',
      'adb-x (a)',
      'adb-x (1)tail',
    ]) {
      expect(DeviceDiscovery.matchesGuid(value, 'adb-x'), isFalse);
    }
    expect(DeviceDiscovery.matchesGuid('', ''), isFalse);
  });

  test('有效期取 PTR/SRV/地址最早值，同端点刷新后旧候选代次仍有效', () async {
    fixture.advertise('phone', AdbDiscoveryKind.tlsConnect, ttl: 20);
    fixture.answers['phone.local/1'] = [
      fixture.ip('phone.local', '192.0.2.1', ttl: 5),
    ];
    final discovery = fixture.create();
    final original = (await discovery.scan()).single;
    expect(original.validUntil.isUtc, isTrue);
    expect(original.validUntil, fixture.now.add(const Duration(seconds: 5)));
    fixture.now = fixture.now.add(const Duration(seconds: 2));
    fixture.advertise('phone', AdbDiscoveryKind.tlsConnect, ttl: 20);
    final renewed = (await discovery.scan()).single;
    expect(renewed.generation, original.generation);
    fixture.now = fixture.now.add(const Duration(seconds: 4));
    expect(discovery.isCurrent(original), isTrue);
    expect(fixture.clients, hasLength(2));
  });

  test('同服务地址变化撤旧候选，过期及 goodbye 后重现不能复用代次', () async {
    fixture.advertise('phone', AdbDiscoveryKind.tlsConnect, ttl: 2);
    final discovery = fixture.create();
    final original = (await discovery.scan()).single;
    fixture.advertise(
      'phone',
      AdbDiscoveryKind.tlsConnect,
      address: '192.0.2.2',
      ttl: 2,
    );
    final replacement = (await discovery.scan()).single;
    expect(discovery.isCurrent(original), isFalse);
    fixture.answers['_adb-tls-connect._tcp.local/12'] = [
      PtrResourceRecord(
        '_adb-tls-connect._tcp.local',
        fixture.now.millisecondsSinceEpoch,
        domainName: replacement.serviceName,
      ),
    ];
    expect(await discovery.scan(), isEmpty);
    expect(discovery.isCurrent(replacement), isFalse);
    fixture.advertise(
      'phone',
      AdbDiscoveryKind.tlsConnect,
      address: '192.0.2.2',
      ttl: 2,
    );
    final reappeared = (await discovery.scan()).single;
    expect(reappeared.generation, greaterThan(replacement.generation));
    fixture.now = fixture.now.add(const Duration(seconds: 3));
    expect(discovery.isCurrent(reappeared), isFalse);
  });

  test('地址 goodbye 同样撤销旧端点，完整查询无回答不提前抹掉有效缓存', () async {
    fixture.advertise('phone', AdbDiscoveryKind.tlsConnect);
    final discovery = fixture.create();
    final original = (await discovery.scan()).single;
    fixture.answers.clear();
    expect((await discovery.scan()).single.generation, original.generation);
    fixture.advertise('phone', AdbDiscoveryKind.tlsConnect);
    fixture.answers['phone.local/1'] = [
      fixture.ip('phone.local', '192.0.2.1', ttl: 0),
    ];
    expect(await discovery.scan(), isEmpty);
    expect(discovery.isCurrent(original), isFalse);
  });

  test('保留可路由 IPv6，拒绝无接口的链路本地、未指定和组播地址', () async {
    fixture.advertise('phone', AdbDiscoveryKind.tlsConnect);
    fixture.answers['phone.local/1'] = [fixture.ip('phone.local', '0.0.0.0')];
    fixture.answers['phone.local/28'] = [
      fixture.ip('phone.local', '2001:db8::1'),
      fixture.ip('phone.local', 'fe80::1'),
      fixture.ip('phone.local', 'ff02::fb'),
    ];
    final result = await fixture.create().scan();
    expect(result.single.address, '2001:db8::1');
  });

  test('服务数与端点数超限明确失败，不交付残缺成功', () async {
    fixture.advertise('one', AdbDiscoveryKind.tlsConnect);
    fixture.advertise('two', AdbDiscoveryKind.tlsConnect);
    await expectLater(
      fixture.create(maxServices: 1).scan(),
      _error('discovery_limit'),
    );
    await fixture.owner!.close();
    fixture.owner = null;
    await expectLater(
      fixture.create(maxEndpoints: 1).scan(),
      _error('discovery_limit'),
    );
    expect(fixture.sockets.every((s) => s.closed), isTrue);
  });

  test('解析并发有界，排队服务在前一解析结束后才查询', () async {
    for (final name in ['one', 'two', 'three']) {
      fixture.advertise(name, AdbDiscoveryKind.tlsConnect);
    }
    final controllers = <StreamController<ResourceRecord>>[];
    final twoStarted = Completer<void>(), threeStarted = Completer<void>();
    var active = 0, maximum = 0;
    fixture.queryOverride = (query, _) {
      if (query.resourceRecordType != ResourceRecordType.service) {
        return Stream.fromIterable(
          fixture.answers['${query.fullyQualifiedName}/${query.resourceRecordType}'] ??
              [],
        );
      }
      final controller = StreamController<ResourceRecord>(
        onListen: () {
          active++;
          if (active > maximum) maximum = active;
        },
        onCancel: () {
          active--;
        },
      );
      controllers.add(controller);
      if (controllers.length == 2) twoStarted.complete();
      if (controllers.length == 3) threeStarted.complete();
      return controller.stream;
    };
    final scan = fixture.create(maxConcurrentResolutions: 2).scan();
    await twoStarted.future;
    expect(controllers, hasLength(2));
    await Future.wait(controllers.toList().map((c) => c.close()));
    await threeStarted.future;
    await controllers.last.close();
    expect(await scan, isEmpty);
    expect(maximum, 2);
  });

  test('跨轮缓存同样有界，超限失败不会交付新候选或废弃原有效候选', () async {
    fixture.advertise('one', AdbDiscoveryKind.tlsConnect);
    final discovery = fixture.create(maxEndpoints: 1);
    final original = (await discovery.scan()).single;
    fixture.answers.clear();
    fixture.advertise('two', AdbDiscoveryKind.tlsConnect);
    await expectLater(discovery.scan(), _error('discovery_limit'));
    expect(discovery.isCurrent(original), isTrue);
  });

  test('发现窗口到期会结束不返回的查询并关闭 socket，不能遗留后台扫描', () async {
    final streams = <StreamController<ResourceRecord>>[];
    fixture.queryOverride = (_, _) {
      final controller = StreamController<ResourceRecord>();
      streams.add(controller);
      return controller.stream;
    };
    final result = await fixture
        .create(timeout: const Duration(milliseconds: 30))
        .scan();
    expect(result, isEmpty);
    expect(streams.every((s) => !s.hasListener), isTrue);
    expect(fixture.sockets.single.closed, isTrue);
    for (final stream in streams) {
      await stream.close();
    }
  });

  test('预先取消不创建客户端，也不泄漏取消监听', () async {
    final cancellation = AdbCancellation()..cancel();
    await expectLater(
      fixture.create().scan(cancellation: cancellation),
      _error('cancelled'),
    );
    expect(fixture.clients, isEmpty);
  });

  test('启动尚未返回时取消，必须等迟到 socket 登记并关闭后才完成', () async {
    final gate = Completer<void>();
    fixture.bindGate = gate;
    final cancellation = AdbCancellation();
    final scan = fixture.create().scan(cancellation: cancellation);
    final failed = expectLater(scan, _error('cancelled'));
    await fixture.bindStarted.future;
    cancellation.cancel();
    var completed = false;
    scan.then<void>(
      (_) => completed = true,
      onError: (Object _) {
        completed = true;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    gate.complete();
    await failed;
    expect(fixture.sockets.single.closed, isTrue);
  });

  test('start 创建 socket 后失败仍关闭，不能依赖未 started 的 MDnsClient.stop', () async {
    fixture.startFailure = StateError('join multicast failed');
    await expectLater(fixture.create().scan(), _error('discovery_unavailable'));
    expect(fixture.sockets.single.closed, isTrue);
  });

  test('查询取消主动结束订阅，等待取消确认后才释放 socket', () async {
    final cancelled = Completer<void>();
    final stream = StreamController<ResourceRecord>(
      onCancel: () => cancelled.future,
    );
    fixture.queryOverride = (query, _) =>
        query.fullyQualifiedName == '_adb-tls-pairing._tcp.local'
        ? stream.stream
        : const Stream.empty();
    final token = AdbCancellation();
    final result = fixture.create().scan(cancellation: token);
    final failed = expectLater(result, _error('cancelled'));
    await fixture.queryStarted.future;
    token.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(fixture.sockets.single.closed, isFalse);
    cancelled.complete();
    await failed;
    expect(fixture.sockets.single.closed, isTrue);
    await stream.close();
  });

  test('后继查询先等待旧轮迟到启动回收，旧轮不能覆盖新候选', () async {
    final gate = Completer<void>();
    fixture.bindGate = gate;
    fixture.advertise('phone', AdbDiscoveryKind.tlsConnect);
    final discovery = fixture.create();
    final first = discovery.scan();
    final failed = expectLater(first, _error('cancelled'));
    await fixture.bindStarted.future;
    fixture.bindGate = null;
    final second = discovery.scan();
    expect(fixture.clients, hasLength(1));
    gate.complete();
    await failed;
    final result = await second;
    expect(result.single.instance, 'phone');
    expect(fixture.sockets.every((s) => s.closed), isTrue);
  });

  test('关闭失败保留精确 socket 并关闭准入，重试只能收尾原资源', () async {
    fixture.closeFailures = 2;
    final discovery = fixture.create();
    await expectLater(
      discovery.scan(),
      _error('discovery_cleanup_unconfirmed'),
    );
    await expectLater(
      discovery.close(),
      _error('discovery_cleanup_unconfirmed'),
    );
    expect(fixture.sockets.single.closed, isFalse);
    await expectLater(discovery.scan(), _error('disposed'));
    await discovery.close();
    expect(fixture.sockets.single.closed, isTrue);
    expect(fixture.sockets, hasLength(1));
  });
}

Matcher _error(String code) =>
    throwsA(isA<RequestFailure>().having((e) => e.code, 'code', code));

final class _Fixture {
  DateTime now = DateTime.utc(2026, 10, 24);
  final answers = <String, List<ResourceRecord>>{};
  final clients = <_Client>[];
  final sockets = <_Socket>[];
  final bindStarted = Completer<void>(), queryStarted = Completer<void>();
  Completer<void>? bindGate;
  Object? startFailure;
  int closeFailures = 0;
  Stream<ResourceRecord> Function(ResourceRecordQuery, int)? queryOverride;
  DeviceDiscovery? owner;

  DeviceDiscovery create({
    int maxServices = 128,
    int maxEndpoints = 256,
    int maxConcurrentResolutions = 8,
    Duration timeout = const Duration(seconds: 3),
  }) => owner = DeviceDiscovery(
    now: () => now,
    timeout: timeout,
    maxServices: maxServices,
    maxEndpoints: maxEndpoints,
    maxConcurrentResolutions: maxConcurrentResolutions,
    listenAddresses: [InternetAddress.anyIPv4],
    socketFactory:
        (
          host,
          port, {
          bool reuseAddress = true,
          bool reusePort = true,
          int ttl = 1,
        }) async {
          if (!bindStarted.isCompleted) bindStarted.complete();
          await bindGate?.future;
          final socket = _Socket(closeFailures);
          sockets.add(socket);
          return socket;
        },
    clientFactory: (factory) {
      final client = _Client(this, factory);
      clients.add(client);
      return client;
    },
  );

  IPAddressResourceRecord ip(String hostname, String address, {int ttl = 30}) =>
      IPAddressResourceRecord(
        hostname,
        now.add(Duration(seconds: ttl)).millisecondsSinceEpoch,
        address: InternetAddress(address),
      );

  void advertise(
    String instance,
    AdbDiscoveryKind kind, {
    int port = 37000,
    String address = '192.0.2.1',
    int ttl = 30,
  }) {
    final suffix = switch (kind) {
      AdbDiscoveryKind.pairing => '_adb-tls-pairing._tcp.local',
      AdbDiscoveryKind.tlsConnect => '_adb-tls-connect._tcp.local',
      AdbDiscoveryKind.tcpConnect => '_adb._tcp.local',
    };
    final name = '$instance.$suffix';
    final expiry = now.add(Duration(seconds: ttl)).millisecondsSinceEpoch;
    final pointers = answers.putIfAbsent('$suffix/12', () => []);
    pointers.removeWhere((r) => r is PtrResourceRecord && r.domainName == name);
    pointers.add(PtrResourceRecord(suffix, expiry, domainName: name));
    answers['$name/33'] = [
      SrvResourceRecord(
        name,
        expiry,
        target: '$instance.local',
        port: port,
        priority: 0,
        weight: 0,
      ),
    ];
    answers['$instance.local/1'] = [ip('$instance.local', address, ttl: ttl)];
  }
}

final class _Client extends MDnsClient {
  _Client(this.fixture, this.bind);
  final _Fixture fixture;
  final RawDatagramSocketFactory bind;
  final queries = <String>[];

  @override
  Future<void> start({
    InternetAddress? listenAddress,
    NetworkInterfacesFactory? interfacesFactory,
    int mDnsPort = 5353,
    InternetAddress? mDnsAddress,
    Function? onError,
  }) async {
    await bind(listenAddress ?? InternetAddress.anyIPv4, mDnsPort);
    if (fixture.startFailure case final error?) throw error;
  }

  @override
  Stream<T> lookup<T extends ResourceRecord>(
    ResourceRecordQuery query, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final key = '${query.fullyQualifiedName}/${query.resourceRecordType}';
    queries.add(key);
    if (!fixture.queryStarted.isCompleted) fixture.queryStarted.complete();
    return (fixture.queryOverride?.call(query, queries.length) ??
            Stream<ResourceRecord>.fromIterable(
              fixture.answers[key] ?? const [],
            ))
        .cast<T>();
  }

  @override
  void stop() {}
}

final class _Socket implements RawDatagramSocket {
  _Socket(this.failures);
  int failures;
  bool closed = false;
  @override
  void close() {
    if (failures > 0) {
      failures--;
      throw StateError('close failed');
    }
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
