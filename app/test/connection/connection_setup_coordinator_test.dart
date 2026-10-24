import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/connection/connection_policy.dart';
import 'package:scrcpy_connect/connection/connection_setup_coordinator.dart';
import 'package:scrcpy_connect/connection/device_coordinator.dart';
import 'package:scrcpy_connect/connection/device_discovery.dart';
import 'package:scrcpy_connect/connection/identity_manager.dart';
import 'package:scrcpy_connect/connection/records/device_record_store.dart';

const _guid = 'adb-phone-guid';
const _policy = ConnectionPolicy(
  setupLeaseTimeout: Duration(seconds: 30),
  qrPairingTimeout: Duration(seconds: 30),
  pairingDiscoveryTimeout: Duration(milliseconds: 300),
  setupPollInterval: Duration(milliseconds: 100),
  tcpipReconnectTimeout: Duration(milliseconds: 300),
  tcpipRetryInterval: Duration(milliseconds: 100),
  tcp: AdbTcpOptions(keepalive: null, userTimeout: null),
);
const _pair = <String, dynamic>{
  'address': '192.0.2.10',
  'port': 37001,
  'code': '123456',
};
const _dedicated = <String, Object?>{
  'scope': 'device',
  'privateKeyPem': 'key-b',
};

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.open());
  tearDown(() async => fixture.close());

  test('配对成功后仅拨号匹配 GUID 的 TLS 发现端口，保留实际执行参数', () async {
    fixture.advertise(_guid, AdbDiscoveryKind.tlsConnect, port: 42000);
    fixture.advertise(
      'another-phone',
      AdbDiscoveryKind.tlsConnect,
      port: 42001,
    );
    fixture.burst = true;
    final result = await fixture.setup.request('devices.pair', _pair);

    expect(result['paired'], isTrue);
    expect(result['connected'], isTrue);
    expect(fixture.client.pairs.single.address, '192.0.2.10:37001');
    expect(fixture.client.connects.single.address, '192.0.2.10:42000');
    expect(fixture.client.connects.single.requireTls, isTrue);
    expect(fixture.client.connects.single.options!.burstMode, isTrue);
    expect(
      fixture.client.connects.single.options!.publicKeyComment,
      _policy.publicKeyComment,
    );
    final record = fixture.records.current.devices.single;
    expect(record.port, 42000);
    expect(record.guid, _guid);
    expect(record.transport, DeviceTransport.tls);
    expect(fixture.devices.current(record.id), isNotNull);
    expect((await fixture.diskDevices()).single['port'], 42000);
  });

  test('没有连接服务时只保存 paired 离线记录，不把配对端口当连接端口', () async {
    fixture.advertise(_guid, AdbDiscoveryKind.pairing, port: 37001);
    final result = await fixture.setup.request('devices.pair', _pair);

    expect(result['paired'], isTrue);
    expect(result['connected'], isFalse);
    expect(result['connectionPortRequired'], isTrue);
    expect(fixture.client.connects, isEmpty);
    final record = fixture.records.current.devices.single;
    expect(record.status, 'offline');
    expect(record.port, 0);
    expect((await fixture.diskDevices()).single['port'], 0);
  });

  test('取消等待迟到 SDK 成功 GUID，先保存配对事实且不再连接', () async {
    final reply = fixture.client.pairReply = Completer<String>();
    final request = fixture.setup.request('devices.pair', {
      ..._pair,
      'attemptId': 'late-pair',
    });
    await fixture.client.pairStarted.future;
    var drained = false;
    final cancelling = fixture.setup
        .beforeRequest('devices.cancel', {'attemptId': 'late-pair'})
        .then((_) => drained = true);
    expect(fixture.client.pairs.single.cancellation!.isCancelled, isTrue);
    expect(drained, isFalse);
    reply.complete(_guid);

    final result = await request;
    await cancelling;
    expect(result['paired'], isTrue);
    expect(result['cancelled'], isTrue);
    expect(result['connected'], isFalse);
    expect(fixture.client.connects, isEmpty);
    final stored = (await fixture.diskDevices()).single;
    expect(stored['guid'], _guid);
    expect(stored['status'], 'offline');
    expect(stored['port'], 0);
  });

  test('配对结果未知不伪造 GUID 或离线 paired 记录，也不自动重放', () async {
    fixture.client.pairError = const AdbException('pair_result_unknown');
    await expectLater(
      fixture.setup.request('devices.pair', _pair),
      _failure('pair_result_unknown'),
    );
    expect(fixture.client.pairs, hasLength(1));
    expect(fixture.records.current.devices, isEmpty);
    expect(fixture.client.connects, isEmpty);
  });

  test('QR 只向本次精确实例配对，秘密只进握手，结果通过 pairing.changed 交付', () async {
    final qr = Completer<Map<String, dynamic>>();
    final pairReply = Completer<String>();
    fixture.client.pairReply = pairReply;
    fixture.beforeQuery = (query) async {
      if (query.fullyQualifiedName != '_adb-tls-pairing._tcp.local') return;
      final payload = (await qr.future)['payload']! as String;
      final fields = _qrFields(payload);
      fixture.advertise(
        '${fields.instance}-other',
        AdbDiscoveryKind.pairing,
        port: 37009,
      );
      fixture.advertise(fields.instance, AdbDiscoveryKind.pairing, port: 37002);
      fixture.advertise(_guid, AdbDiscoveryKind.tlsConnect, port: 42000);
    };
    final changed = fixture.event('qr-1');
    final receipt = await fixture.setup.request('devices.pair.qr', {
      'attemptId': 'qr-1',
    });
    qr.complete(receipt);
    final payload = receipt['payload']! as String;
    final fields = _qrFields(payload);
    expect(fields.instance, matches(r'^studio-[A-Za-z0-9_-]{16}$'));
    expect(fields.password, matches(r'^[A-Za-z0-9_-]{43}$'));
    await fixture.client.pairStarted.future;
    // 精确选择约束配对阶段；GUID 返回后为 TLS 连接执行的普通扫描可以查询其他实例。
    expect(
      fixture.queries,
      contains('${fields.instance}._adb-tls-pairing._tcp.local/33'),
    );
    expect(
      fixture.queries,
      isNot(
        contains('${fields.instance}-other._adb-tls-pairing._tcp.local/33'),
      ),
    );
    pairReply.complete(_guid);
    final result = await changed;

    expect(result['type'], 'pairing.changed');
    expect((result['data'] as Map)['status'], 'paired');
    expect(((result['data'] as Map)['result'] as Map)['connected'], isTrue);
    expect(fixture.client.pairs.single.address, '192.0.2.10:37002');
    expect(fixture.client.pairs.single.password, fields.password);
    expect(jsonEncode(fixture.events), isNot(contains(fields.password)));
    expect(
      await fixture.records.file.readAsString(),
      isNot(contains(fields.password)),
    );
    expect(fixture.queries, contains('_adb-tls-connect._tcp.local/12'));
  });

  test('已有 GUID 的 QR 获得另一真实 GUID 时报告身份冲突，不能冒充原记录成功', () async {
    final id = await fixture.savedDevice(guid: _guid);
    fixture.client.pairGuid = 'another-real-guid';
    final event = await fixture.qr(params: {'deviceId': id});
    final data = event['data']! as Map<String, dynamic>;
    expect(data['status'], 'failed');
    expect(data['code'], 'device_identity_mismatch');
    final actual = data['result']! as Map<String, dynamic>;
    expect(actual['paired'], isTrue);
    expect(actual['guid'], 'another-real-guid');
    expect(actual.containsKey('deviceId'), isFalse);
    expect(fixture.records.current.devices, hasLength(1));
    expect(fixture.records.current.find(id)!.guid, _guid);
    expect((await fixture.diskDevices()).single['guid'], _guid);
    expect(fixture.client.connects, isEmpty);
  });

  test('QR 专属身份已保存配对后清理首败，事件仍为 paired 并带可重试清理事实', () async {
    fixture.releaseFailures = 1;
    final event = await fixture.qr(params: {'identity': _dedicated});
    final data = event['data']! as Map<String, dynamic>;
    expect(data['status'], 'paired');
    final result = data['result']! as Map<String, dynamic>;
    expect(result['guid'], _guid);
    expect(result['connected'], isFalse);
    expect(
      (result['cleanupFailure'] as Map)['code'],
      'setup_cleanup_unconfirmed',
    );
    expect((await fixture.diskDevices()).single['guid'], _guid);
    final candidate = fixture.releasedIdentities.single;
    expect(await File(candidate.path).exists(), isTrue);
    await fixture.setup.dispose();
    expect(await File(candidate.path).exists(), isFalse);
    expect(fixture.client.pairs, hasLength(1));
  });

  test('QR 同实例首地址不可达才尝试下一地址，每次使用 endpointTimeout', () async {
    fixture.client.pairFailures.add(const AdbException('unreachable'));
    final event = await fixture.qr(addresses: ['192.0.2.10', '192.0.2.11']);
    expect((event['data'] as Map)['status'], 'paired');
    expect(fixture.client.pairs.map((pair) => pair.address), [
      '192.0.2.10:37002',
      '192.0.2.11:37002',
    ]);
    expect(
      fixture.client.pairs.map((pair) => pair.timeout),
      List.filled(2, _policy.endpointTimeout),
    );
    expect(
      fixture.client.pairs.first.password,
      fixture.client.pairs.last.password,
    );
    expect((await fixture.diskDevices()).single['guid'], _guid);
  });

  test('QR 配对结果未知不能重放到同实例下一地址', () async {
    fixture.client.pairFailures.add(const AdbException('pair_result_unknown'));
    final event = await fixture.qr(addresses: ['192.0.2.10', '192.0.2.11']);
    final data = event['data']! as Map<String, dynamic>;
    expect(data['status'], 'failed');
    expect(data['code'], 'pair_result_unknown');
    expect(fixture.client.pairs, hasLength(1));
    expect(fixture.client.pairs.single.timeout, _policy.endpointTimeout);
    expect(fixture.records.current.devices, isEmpty);
  });

  test('配置变更先取消并排空旧配对发现，迟到 TLS 回答不能覆盖后继配置', () async {
    final id = await fixture.savedDevice(guid: _guid);
    final discoveryStarted = Completer<void>();
    final lateAnswer = Completer<void>();
    fixture.beforeQuery = (query) async {
      if (query.fullyQualifiedName != '_adb-tls-connect._tcp.local') return;
      discoveryStarted.complete();
      await lateAnswer.future;
    };
    final pairing = fixture.setup.request('devices.pair', {
      ..._pair,
      'deviceId': id,
    });
    await discoveryStarted.future;
    expect(fixture.records.current.find(id)!.guid, _guid);
    var drained = false;
    final cancelling = fixture.setup
        .beforeRequest('devices.configure', {'deviceId': id})
        .then((_) => drained = true);
    expect(drained, isFalse);
    fixture.advertise(_guid, AdbDiscoveryKind.tlsConnect, port: 42000);
    lateAnswer.complete();
    await cancelling;
    final result = await pairing;
    expect(result['paired'], isTrue);
    expect(result['cancelled'], isTrue);
    expect(fixture.client.connects, isEmpty);
    await fixture.devices.command('devices.configure', {
      'deviceId': id,
      'host': '192.0.2.99',
      'port': 43000,
      'transport': 'tls',
    });
    expect(fixture.client.connects.single.address, '192.0.2.99:43000');
    expect(fixture.records.current.find(id)!.address, '192.0.2.99');
    expect((await fixture.diskDevices()).single['port'], 43000);
  });

  test('发现投影仅将精确已配对 GUID 标为 trusted，不创建设备记录', () async {
    final known = await fixture.records.add(
      address: '192.0.2.10',
      port: 0,
      transport: DeviceTransport.tls,
      guid: _guid,
    );
    fixture.advertise(_guid, AdbDiscoveryKind.tlsConnect, port: 42000);
    fixture.advertise(
      '$_guid-suffix',
      AdbDiscoveryKind.tlsConnect,
      port: 42001,
    );
    fixture.advertise('pairing', AdbDiscoveryKind.pairing, port: 37001);
    final result = await fixture.setup.request('devices.discover', {});
    final candidates = (result['devices'] as List).cast<Map<String, dynamic>>();
    final trusted = candidates.where((item) => item['trusted'] == true).single;
    expect(trusted['deviceId'], known.id);
    expect(trusted['instance'], _guid);
    expect(
      candidates.where((item) => item['kind'] == 'pairing').single['trusted'],
      isFalse,
    );
    expect(fixture.records.current.devices, hasLength(1));
    expect(fixture.client.pairs, isEmpty);
    expect(fixture.client.connects, isEmpty);
  });

  test('TCPIP 必须收到精确端口确认，失败不改配置或重发 restart', () async {
    final id = await fixture.connectedDevice();
    final original = fixture.devices.requireConnection(id);
    fixture.client.native.restartResponse = 'restarting in TCP mode port: 6666';
    await expectLater(
      fixture.setup.request('devices.wireless', {
        'deviceId': id,
        'address': '192.0.2.25',
        'port': 5555,
      }),
      _failure('wireless_setup_failed'),
    );
    expect(fixture.client.native.restarts, ['5555']);
    expect(fixture.client.connects, hasLength(1));
    expect(fixture.devices.current(id), isNull);
    expect(fixture.client.disconnects, contains(original.device.id));
    expect(fixture.records.current.find(id)!.address, '192.0.2.10');
    expect(fixture.records.current.find(id)!.autoReconnect, isFalse);
  });

  test('TCPIP 只 restart 一次，有限重试后核验原序列号再提交明文端点', () async {
    final id = await fixture.connectedDevice();
    fixture.client.connectFailures.addAll([
      const AdbException('unreachable'),
      const AdbException('timeout'),
    ]);
    final result = await fixture.setup.request('devices.wireless', {
      'deviceId': id,
      'address': '192.0.2.25',
      'port': 5555,
    });
    expect(result['enabled'], isTrue);
    expect(result['connected'], isTrue);
    expect(result['encrypted'], isFalse);
    expect(fixture.client.native.restarts, ['5555']);
    expect(
      fixture.client.connects.skip(1).map((item) => item.address),
      List.filled(3, '192.0.2.25:5555'),
    );
    expect(fixture.delays, List.filled(2, _policy.tcpipRetryInterval));
    final record = fixture.records.current.find(id)!;
    expect(record.address, '192.0.2.25');
    expect(record.transport, DeviceTransport.tcp);
    expect(record.serial, 'hardware-serial');
    expect(record.guid, isNull);
    expect(record.autoReconnect, isTrue);
  });

  test('TCPIP 连续不可达按时间预算停止，不重启 adbd 或无限重拨', () async {
    final id = await fixture.connectedDevice();
    fixture.client.connectError = const AdbException('unreachable');
    await expectLater(
      fixture.setup.request('devices.wireless', {
        'deviceId': id,
        'address': '192.0.2.25',
        'port': 5555,
      }),
      _failure('timeout'),
    );
    expect(fixture.client.native.restarts, ['5555']);
    expect(fixture.client.connects.skip(1), hasLength(4));
    expect(
      fixture.delays.fold(Duration.zero, (a, b) => a + b),
      _policy.tcpipReconnectTimeout,
    );
    expect(fixture.records.current.find(id)!.address, '192.0.2.10');
    expect(fixture.records.current.find(id)!.autoReconnect, isFalse);
  });

  test('TCPIP 退休后取消会排空迟到候选，保留旧端点且不能恢复自动重连', () async {
    final id = await fixture.connectedDevice();
    final original = fixture.devices.requireConnection(id);
    final started = fixture.client.nextConnectStarted = Completer<void>();
    final reply = fixture.client.connectReply = Completer<AdbDevice>();
    final request = fixture.setup.request('devices.wireless', {
      'deviceId': id,
      'attemptId': 'tcpip',
      'address': '192.0.2.25',
      'port': 5555,
    });
    final cancelled = expectLater(request, _failure('cancelled'));
    await started.future;
    expect(fixture.devices.current(id), isNull);
    expect(fixture.client.disconnects, contains(original.device.id));
    var drained = false;
    final cancelling = fixture.setup
        .beforeRequest('devices.cancel', {'attemptId': 'tcpip'})
        .then((_) => drained = true);
    expect(drained, isFalse);
    reply.complete(
      const AdbDevice(id: 'late-tcp', serial: 'wireless', state: 'device'),
    );
    await cancelled;
    await cancelling;
    expect(fixture.client.native.restarts, ['5555']);
    expect(fixture.client.disconnects, contains('late-tcp'));
    expect(fixture.devices.current(id), isNull);
    expect(fixture.records.current.find(id)!.address, '192.0.2.10');
    expect(fixture.records.current.find(id)!.autoReconnect, isFalse);
  });

  test('TCPIP 目标必须来自原精确连接的真实网络查询，拒绝任意输入地址', () async {
    final id = await fixture.connectedDevice();
    await expectLater(
      fixture.setup.request('devices.wireless', {
        'deviceId': id,
        'address': '192.0.2.99',
        'port': 5555,
      }),
      _failure('address_changed'),
    );
    expect(fixture.client.shellCommands, contains('ip -o addr show'));
    expect(fixture.client.native.restarts, isEmpty);
    expect(fixture.client.connects, hasLength(1));
  });

  test('桌面 USB 只选择有 usbPath 的传输，不误选同列 TCP 设备', () async {
    fixture.client.official = true;
    fixture.client.attached = const [
      AdbTransport(serial: '192.0.2.11:5555', state: 'device'),
      AdbTransport(
        serial: 'USB-serial',
        state: 'device',
        usbPath: '1-2',
        model: 'USB 手机',
        transportId: 7,
      ),
    ];
    final result = await fixture.setup.request('devices.usb', {});
    expect(result['connected'], isTrue);
    expect(fixture.client.connects.single.address, 'USB-serial');
    expect(fixture.client.connects.single.options, isNull);
    expect(
      fixture.records.current.devices.single.transport,
      DeviceTransport.usb,
    );
    expect(fixture.client.transportCalls, 1);
  });

  test('桌面多个 USB 返回真实选择列表，排除无线传输且不偷偷拨号', () async {
    fixture.client.attached = const [
      AdbTransport(serial: 'wireless', state: 'device'),
      AdbTransport(serial: 'one', state: 'device', usbPath: '1-1'),
      AdbTransport(serial: 'two', state: 'unauthorized', usbPath: '1-2'),
    ];
    final result = await fixture.setup.request('devices.usb', {});
    expect(result['selectionRequired'], isTrue);
    expect((result['devices'] as List).map((item) => (item as Map)['serial']), [
      'one',
      'two',
    ]);
    expect(fixture.client.connects, isEmpty);
    expect(fixture.records.current.devices, isEmpty);
  });

  test('USB 唯一保存 serial 复用原记录，枚举不创建重复记录', () async {
    final id = await fixture.savedDevice();
    fixture.client.attached = const [
      AdbTransport(serial: 'hardware-serial', state: 'device', usbPath: '1-2'),
    ];
    final result = await fixture.setup.request('devices.usb', {});
    expect(result['deviceId'], id);
    expect(result['connected'], isTrue);
    expect(fixture.records.current.devices, hasLength(1));
    expect(fixture.records.current.find(id)!.transport, DeviceTransport.usb);
  });

  test('USB 同 serial 多条保存记录要求明确选择，不能任选一条交付', () async {
    await fixture.savedDevice();
    await fixture.savedDevice();
    fixture.client.attached = const [
      AdbTransport(serial: 'hardware-serial', state: 'device', usbPath: '1-2'),
    ];
    await expectLater(
      fixture.setup.request('devices.usb', {}),
      _failure('usb_selection_required'),
    );
    expect(fixture.client.connects, isEmpty);
    expect(fixture.records.current.devices, hasLength(2));
  });

  test('USB 枚举匹配原 serial 仍须核验实际设备，不符时回收候选保留原记录', () async {
    final id = await fixture.savedDevice();
    fixture.client.serial = 'another-hardware';
    fixture.client.attached = const [
      AdbTransport(serial: 'hardware-serial', state: 'device', usbPath: '1-2'),
    ];
    await expectLater(
      fixture.setup.request('devices.usb', {}),
      _failure('device_identity_mismatch'),
    );
    expect(fixture.client.disconnects, ['handle-1']);
    expect(fixture.devices.current(id), isNull);
    expect(fixture.records.current.devices, hasLength(1));
    expect(fixture.records.current.find(id)!.serial, 'hardware-serial');
  });

  test('平台权限迟到时取消必须等原回执，登记并释放 lease 后才完成 drain', () async {
    final permission = Completer<Map<String, dynamic>>();
    final started = Completer<void>();
    fixture.authorize = (_) {
      started.complete();
      return permission.future;
    };
    final request = fixture.setup.request('devices.usb', {'attemptId': 'usb'});
    final failed = expectLater(request, _failure('cancelled'));
    await started.future;
    var drained = false;
    final cancelling = fixture.setup
        .beforeRequest('devices.cancel', {'attemptId': 'usb'})
        .then((_) => drained = true);
    await fixture.platformCancelled.future;
    expect(drained, isFalse);
    expect(fixture.releasedUsb, isEmpty);
    permission.complete({'fd': 42, 'usbLeaseId': 'late-permission'});
    await failed;
    await cancelling;
    expect(fixture.releasedUsb, ['late-permission']);
    expect(fixture.client.connects, isEmpty);
    expect(fixture.records.current.devices, isEmpty);
  });

  test('临时身份先精确释放 SDK client，再删除 PEM，不关闭共享永久 client', () async {
    fixture.client.pairError = const AdbException('pair_failed');
    await expectLater(
      fixture.setup.request('devices.pair', {..._pair, 'identity': _dedicated}),
      _failure('pair_failed'),
    );
    final candidate = fixture.releasedIdentities.single;
    expect(fixture.releaseSawPem, [true]);
    expect(await File(candidate.path).exists(), isFalse);
    expect(fixture.client.closeCalls, 0);
    expect(fixture.records.current.devices, isEmpty);
  });

  test('配对已成功但临时客户端清理失败，错误保留真实结果且重试不删已绑定密钥', () async {
    fixture.releaseFailures = 1;
    await expectLater(
      fixture.setup.request('devices.pair', {..._pair, 'identity': _dedicated}),
      throwsA(
        isA<ApplicationCommandException>()
            .having((error) => error.code, 'code', 'setup_cleanup_unconfirmed')
            .having(
              (error) =>
                  ((error.details! as Map<String, dynamic>)['result']
                      as Map<String, dynamic>)['paired'],
              '真实配对结果',
              isTrue,
            ),
      ),
    );
    final record = fixture.records.current.devices.single;
    expect(record.guid, _guid);
    // 新专属身份的绑定会撤销旧授权投影；真实配对 GUID 仍须独立保留。
    expect(record.status, 'unauthorized');
    expect(record.autoReconnect, isFalse);
    final persisted = (await fixture.diskDevices()).single;
    expect(persisted['guid'], _guid);
    expect(persisted['status'], 'unauthorized');
    final candidate = fixture.releasedIdentities.single;
    final bound = await fixture.identities.selectForDevice(record.id);
    expect(bound.path, isNot(candidate.path));
    expect(await File(candidate.path).exists(), isTrue);
    await fixture.setup.dispose();
    expect(await File(candidate.path).exists(), isFalse);
    expect(await File(bound.path).readAsString(), 'key-b');
    expect(fixture.client.pairs, hasLength(1));
    expect(fixture.releasedIdentities.map((item) => item.path), [
      candidate.path,
      candidate.path,
    ]);
  });

  test('候选客户端释放首败保留 PEM 与精确责任，dispose 重试成功才删除', () async {
    fixture.client.pairError = const AdbException('pair_failed');
    fixture.releaseFailures = 1;
    await expectLater(
      fixture.setup.request('devices.pair', {..._pair, 'identity': _dedicated}),
      _failure('setup_cleanup_unconfirmed'),
    );
    final candidate = fixture.releasedIdentities.single;
    expect(await File(candidate.path).exists(), isTrue);
    await fixture.setup.dispose();
    expect(fixture.releasedIdentities.map((item) => item.path), [
      candidate.path,
      candidate.path,
    ]);
    expect(fixture.releaseSawPem, [true, true]);
    expect(await File(candidate.path).exists(), isFalse);
    expect(fixture.client.closeCalls, 0);
  });
}

Matcher _failure(String code) => throwsA(
  isA<ApplicationCommandException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

({String instance, String password}) _qrFields(String payload) {
  final match = RegExp(r'^WIFI:T:ADB;S:([^;]+);P:([^;]+);;$')
      .firstMatch(payload)!;
  return (instance: match.group(1)!, password: match.group(2)!);
}

/// 身份和设备记录走真实磁盘；这里只替换 RSA、ADB 和平台权限机制。
final class _Fixture {
  _Fixture(this.root);
  final Directory root;
  late final DeviceRecordStore records;
  late final IdentityManager identities;
  late final DeviceCoordinator devices;
  late final DeviceDiscovery discovery;
  late final ConnectionSetupCoordinator setup;
  final client = _Client();
  final identityApi = _Identities();
  final events = <Map<String, dynamic>>[];
  final changed = <String, Completer<Map<String, dynamic>>>{};
  final answers = <String, List<ResourceRecord>>{};
  final queries = <String>[];
  final sockets = <_Socket>[];
  final delays = <Duration>[];
  final releasedUsb = <String>[];
  final releasedIdentities = <IdentitySelection>[];
  final releaseSawPem = <bool>[];
  final platformCancelled = Completer<void>();
  DateTime now = DateTime.utc(2026, 10, 24);
  bool burst = false, devicesReady = false;
  int releaseFailures = 0, _nextId = 0;
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? authorize;
  Future<void> Function(ResourceRecordQuery)? beforeQuery;

  static Future<_Fixture> open() async {
    final fixture = _Fixture(
      await Directory.systemTemp.createTemp('setup-typed-'),
    );
    fixture.records = await DeviceRecordStore.open(
      directory: fixture.root,
      idFactory: () =>
          '00000000-0000-4000-8000-${(++fixture._nextId).toString().padLeft(12, '0')}',
    );
    fixture.identities = await IdentityManager.open(
      directory: fixture.root,
      records: fixture.records,
      identities: fixture.identityApi,
      invalidate: (ids, {required global}) => fixture.devicesReady
          ? fixture.devices.invalidate(ids)
          : Future<void>.value(),
    );
    fixture.devices = DeviceCoordinator(
      records: fixture.records,
      identities: fixture.identities,
      clientForIdentity: (_) => fixture.client,
      prepareConnection: (_, _) async {},
      policy: _policy,
      burstMode: () => fixture.burst,
      stopActivities: (_, _) async {},
      now: () => fixture.now,
    );
    fixture.devicesReady = true;
    fixture.discovery = DeviceDiscovery(
      now: () => fixture.now,
      listenAddresses: [InternetAddress.anyIPv4],
      socketFactory:
          (
            host,
            port, {
            bool reuseAddress = true,
            bool reusePort = true,
            int ttl = 1,
          }) async {
            final socket = _Socket();
            fixture.sockets.add(socket);
            return socket;
          },
      clientFactory: (factory) => _Mdns(fixture, factory),
    );
    fixture.setup = ConnectionSetupCoordinator(
      devices: fixture.devices,
      discovery: fixture.discovery,
      clientForIdentity: (_) => fixture.client,
      releaseIdentityClient: (selection) async {
        fixture.releasedIdentities.add(selection);
        fixture.releaseSawPem.add(await File(selection.path).exists());
        if (fixture.releaseFailures-- > 0) {
          throw StateError('exact identity client cleanup unconfirmed');
        }
      },
      policy: _policy,
      burstMode: () => fixture.burst,
      emit: (event) {
        fixture.events.add(event);
        final data = event['data'];
        if (event['type'] == 'pairing.changed' && data is Map) {
          final attempt = data['attemptId'];
          final waiting = fixture.changed[attempt];
          if (waiting != null && !waiting.isCompleted) waiting.complete(event);
        }
      },
      authorizeUsb: (params) async =>
          await fixture.authorize?.call(params) ?? params,
      cancelUsb: (_) async {
        if (!fixture.platformCancelled.isCompleted) {
          fixture.platformCancelled.complete();
        }
      },
      releaseUsb: (params) async =>
          fixture.releasedUsb.add(params['usbLeaseId']! as String),
      now: () => fixture.now,
      delay: (duration) async {
        fixture.delays.add(duration);
        fixture.now = fixture.now.add(duration);
      },
    );
    return fixture;
  }

  Future<Map<String, dynamic>> event(String attempt) =>
      changed.putIfAbsent(attempt, Completer<Map<String, dynamic>>.new).future;

  /// 在真实 PTR 查询边界发布本次 QR 的候选，避免依赖异步调度早晚。
  Future<Map<String, dynamic>> qr({
    Map<String, dynamic> params = const {},
    List<String> addresses = const ['192.0.2.10'],
  }) async {
    final receipt = Completer<Map<String, dynamic>>();
    beforeQuery = (query) async {
      if (query.fullyQualifiedName != '_adb-tls-pairing._tcp.local') return;
      final fields = _qrFields((await receipt.future)['payload']! as String);
      advertise(fields.instance, AdbDiscoveryKind.pairing, port: 37002);
      final hostname = '${fields.instance}.local';
      final expiry = now.add(const Duration(minutes: 1)).millisecondsSinceEpoch;
      answers['$hostname/1'] = [
        for (final address in addresses)
          IPAddressResourceRecord(
            hostname,
            expiry,
            address: InternetAddress(address),
          ),
      ];
    };
    final changed = event('qr-case');
    receipt.complete(
      await setup.request('devices.pair.qr', {
        ...params,
        'attemptId': 'qr-case',
      }),
    );
    return changed;
  }

  Future<List<Map<String, dynamic>>> diskDevices() async =>
      (jsonDecode(await records.file.readAsString())['devices'] as List)
          .cast<Map<String, dynamic>>();

  Future<String> savedDevice({String? guid}) async {
    final record = await records.add(
      address: '192.0.2.10',
      port: 42000,
      transport: guid == null ? DeviceTransport.tcp : DeviceTransport.tls,
      guid: guid,
    );
    await records.update(
      record.id,
      (value) => value.copyWith(serial: 'hardware-serial'),
    );
    return record.id;
  }

  Future<String> connectedDevice() async {
    final added = await devices.command('devices.add', {
      'host': '192.0.2.10',
      'port': 5555,
    });
    final id = added['deviceId']! as String;
    await devices.command('devices.connect', {'deviceId': id});
    return id;
  }

  void advertise(
    String instance,
    AdbDiscoveryKind kind, {
    int port = 37000,
    String address = '192.0.2.10',
  }) {
    final suffix = switch (kind) {
      AdbDiscoveryKind.pairing => '_adb-tls-pairing._tcp.local',
      AdbDiscoveryKind.tlsConnect => '_adb-tls-connect._tcp.local',
      AdbDiscoveryKind.tcpConnect => '_adb._tcp.local',
    };
    final fullname = '$instance.$suffix';
    final expiry = now.add(const Duration(minutes: 1)).millisecondsSinceEpoch;
    final pointers = answers.putIfAbsent('$suffix/12', () => []);
    pointers.removeWhere(
      (record) => record is PtrResourceRecord && record.domainName == fullname,
    );
    pointers.add(PtrResourceRecord(suffix, expiry, domainName: fullname));
    answers['$fullname/33'] = [
      SrvResourceRecord(
        fullname,
        expiry,
        target: '$instance.local',
        port: port,
        priority: 0,
        weight: 0,
      ),
    ];
    answers['$instance.local/1'] = [
      IPAddressResourceRecord(
        '$instance.local',
        expiry,
        address: InternetAddress(address),
      ),
    ];
  }

  Future<void> close() async {
    releaseFailures = 0;
    await setup.dispose();
    await devices.close();
    await client.services.close();
    await root.delete(recursive: true);
  }
}

final class _Connect {
  _Connect(this.address, this.requireTls, this.options);
  final String address;
  final bool requireTls;
  final AdbConnectOptions? options;
}

final class _Pair {
  _Pair(this.address, this.password, this.cancellation, this.timeout);
  final String address, password;
  final AdbCancellation? cancellation;
  final Duration timeout;
}

final class _Client implements AdbClient, AdbTransportDiscovery {
  bool official = false;
  int closeCalls = 0, transportCalls = 0;
  final pairs = <_Pair>[];
  final connects = <_Connect>[];
  final shellCommands = <String>[];
  final disconnects = <String>[];
  final connectFailures = <AdbException>[];
  final pairFailures = <AdbException>[];
  String pairGuid = _guid, serial = 'hardware-serial';
  Object? connectError, pairError;
  Completer<String>? pairReply;
  Completer<AdbDevice>? connectReply;
  Completer<void>? nextConnectStarted;
  final pairStarted = Completer<void>();
  List<AdbTransport> attached = const [];
  late final native = _Native(this);
  @override
  late final services = AdbServices(
    () => native,
    (device) async => device,
    () {},
  );
  @override
  AdbCapabilities get capabilities => AdbCapabilities(
    officialServer: official,
    suppressAuthorizationPrompt: !official,
    forceTlsWithoutMdns: !official,
    androidUsbFd: false,
  );
  @override
  Future<AdbDevice> connect(
    String address, {
    bool requireTls = false,
    bool authorize = true,
    Duration timeout = const Duration(seconds: 15),
    AdbConnectOptions? directOptions,
    AdbCancellation? cancellation,
  }) async {
    cancellation?.check();
    connects.add(_Connect(address, requireTls, directOptions));
    if (connectFailures.isNotEmpty) throw connectFailures.removeAt(0);
    if (connectError case final error?) throw error;
    nextConnectStarted?.complete();
    nextConnectStarted = null;
    if (connectReply case final reply?) {
      connectReply = null;
      return reply.future;
    }
    return AdbDevice(
      id: 'handle-${connects.length}',
      serial: address,
      state: 'device',
    );
  }

  @override
  Future<String> pair(
    String address,
    String password, {
    Duration timeout = const Duration(seconds: 30),
    AdbCancellation? cancellation,
  }) async {
    pairs.add(_Pair(address, password, cancellation, timeout));
    if (!pairStarted.isCompleted) pairStarted.complete();
    if (pairFailures.isNotEmpty) throw pairFailures.removeAt(0);
    if (pairError case final error?) throw error;
    // 真实 SDK 已确认 GUID 后不会因迟到取消抹去信任事实。
    return await pairReply?.future ?? pairGuid;
  }

  @override
  Future<List<AdbTransport>> transports({
    Duration timeout = const Duration(seconds: 3),
    AdbCancellation? cancellation,
  }) async {
    cancellation?.check();
    transportCalls++;
    return attached;
  }

  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) async* {
    cancellation?.check();
    shellCommands.add(command);
    final output = command == 'ip -o addr show'
        ? '2: wlan0    inet 192.0.2.25/24 brd 192.0.2.255 scope global wlan0\n'
        : '$serial\x00boot-serial\x00测试手机\x0016\x0036\x00$_guid\x00';
    yield AdbShellEvent(
      AdbShellChannel.stdout,
      Uint8List.fromList(utf8.encode(output)),
    );
    yield AdbShellEvent(AdbShellChannel.exit, Uint8List(0), exitCode: 0);
  }

  @override
  Future<void> disconnect(AdbDevice device) async => disconnects.add(device.id);
  @override
  Future<void> close() async => closeCalls++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Native implements NativeAdbApi {
  _Native(this.client);
  final _Client client;
  final restarts = <String>[];
  final pending = <String>{};
  String restartResponse = 'restarting in TCP mode port: 5555\n';
  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async =>
      AdbConnectionFacts(
        officialServer: client.official,
        closed: false,
        features: const [],
        connectionId: 'physical-$id',
        burstMode: client.connects.last.options?.burstMode,
      );
  @override
  Future<String> service(
    String id,
    AdbServiceRequest request,
    int timeoutMs,
  ) async {
    if (request.kind != AdbServiceKind.tcpIp) {
      throw StateError('unexpected service');
    }
    restarts.add(request.service);
    final operation = 'restart-${restarts.length}';
    pending.add(operation);
    return operation;
  }

  @override
  Future<NativeAdbEvent?> next(String id) async {
    if (!pending.contains(id)) throw StateError('unknown operation');
    return NativeAdbEvent(
      kind: 'response',
      bytes: Uint8List.fromList(utf8.encode(restartResponse)),
      done: true,
    );
  }

  @override
  Future<void> cancel(String id) async => pending.remove(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Mdns extends MDnsClient {
  _Mdns(this.fixture, this.bind);
  final _Fixture fixture;
  final RawDatagramSocketFactory bind;
  @override
  Future<void> start({
    InternetAddress? listenAddress,
    NetworkInterfacesFactory? interfacesFactory,
    int mDnsPort = 5353,
    InternetAddress? mDnsAddress,
    Function? onError,
  }) async => await bind(listenAddress ?? InternetAddress.anyIPv4, mDnsPort);
  @override
  Stream<T> lookup<T extends ResourceRecord>(
    ResourceRecordQuery query, {
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    fixture.queries.add(
      '${query.fullyQualifiedName}/${query.resourceRecordType}',
    );
    await fixture.beforeQuery?.call(query);
    yield* Stream<ResourceRecord>.fromIterable(
      fixture.answers['${query.fullyQualifiedName}/${query.resourceRecordType}'] ??
          const [],
    ).cast<T>();
  }

  @override
  void stop() {}
}

final class _Socket implements RawDatagramSocket {
  bool closed = false;
  @override
  void close() => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Identities implements AdbIdentities {
  AdbIdentityInfo info(String pem) => AdbIdentityInfo(
    fingerprint: (pem == 'key-a' ? 'a' : 'b') * 64,
    fingerprintAlgorithm: 'sha256',
    fingerprintInput: 'adb-public-key-interop-v1',
    bits: 2048,
    exponent: 65537,
  );
  @override
  Future<void> prepareIdentity(String path) async {
    final file = File(path);
    if (!await file.exists()) await file.writeAsString('key-a', flush: true);
  }

  @override
  Future<AdbIdentityInfo?> inspectIdentity(String path) async {
    final file = File(path);
    return await file.exists() ? info(await file.readAsString()) : null;
  }

  @override
  Future<AdbIdentityInfo> validateIdentity(String pem) async => info(pem);
  @override
  Future<AdbIdentityCommitReceipt> replaceIdentity(
    String path,
    String pem, {
    String? expectedFingerprint,
  }) async {
    if ((await inspectIdentity(path))?.fingerprint != expectedFingerprint) {
      return const AdbIdentityCommitReceipt(
        state: AdbIdentityCommitState.unchanged,
      );
    }
    final staging = File('$path.tmp');
    await staging.writeAsString(pem, flush: true);
    await staging.rename(path);
    return AdbIdentityCommitReceipt(
      state: AdbIdentityCommitState.committed,
      identity: info(pem),
    );
  }
}
