import '../support/adb_event_fixture.dart';

import 'package:scrcpy_connect/models/device_connection.dart';
import 'package:scrcpy_connect/models/device_facts.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/device_probe.dart';
import 'package:scrcpy_connect/models/device_record.dart';

const _device = AdbDevice(
  id: 'native-handle',
  serial: '192.0.2.1:5555',
  state: 'device',
);

void main() {
  test('身份来自固定属性查询，连接选择器不是设备序列号', () async {
    final cancellation = AdbCancellation();
    final client = _Client((_) => shellOutput(_properties()));
    final connection = DeviceConnection(client: client, device: _device);
    final facts = await const DeviceProbe().readIdentity(
      connection,
      cancellation: cancellation,
      timeout: const Duration(seconds: 2),
    );
    expect(facts.serial, 'hardware-serial');
    expect(facts.bootSerial, 'boot-serial');
    expect(facts.model, '目标手机');
    expect(facts.androidVersion, '16');
    expect(facts.apiLevel, 36);
    expect(facts.guid, 'wireless-guid');
    expect(client.calls.single.device, same(_device));
    expect(client.calls.single.cancellation, same(cancellation));
    expect(client.calls.single.timeout, const Duration(seconds: 2));
    expect(client.calls.single.command, contains('ro.serialno'));
    expect(
      client.calls.single.command,
      contains('persist.adb.tls_server.guid'),
    );
    expect(client.calls.single.command, isNot(contains(_device.serial)));
  });

  test('跨 chunk 的 UTF-8 与 NUL 边界完整解码，旧 shell 无退出码也可读取', () async {
    final bytes = _properties();
    final client = _Client((_) async* {
      for (final byte in bytes) {
        yield AdbShellEvent(AdbShellChannel.stdout, Uint8List.fromList([byte]));
      }
      yield AdbShellEvent(AdbShellChannel.exit, Uint8List(0));
    });
    final facts = await const DeviceProbe().readIdentity(
      DeviceConnection(client: client, device: _device),
    );
    expect(facts.model, '目标手机');
    expect(facts.serial, 'hardware-serial');
  });

  test('未知属性不使用地址、缓存或另一种序列号属性填充', () async {
    final client = _Client(
      (_) => shellOutput(
        _properties(
          serial: 'unknown',
          bootSerial: 'null',
          model: ' ',
          release: 'unknown',
          api: '-1',
          guid: 'null',
        ),
      ),
    );
    final connection = DeviceConnection(client: client, device: _device);
    final unknown = await const DeviceProbe().readIdentity(connection);
    expect(unknown.serial, isNull);
    expect(unknown.bootSerial, isNull);
    expect(unknown.guid, isNull);
    expect(unknown.model, isNull);
    expect(unknown.androidVersion, isNull);
    expect(unknown.apiLevel, isNull);
    unknown.assertMatches(_record(serial: 'saved-serial', guid: 'saved-guid'));
    expect(unknown.serial, isNull);
    final bootOnly = await const DeviceProbe().readIdentity(
      DeviceConnection(
        client: _Client((_) => shellOutput(_properties(serial: ''))),
        device: _device,
      ),
    );
    expect(bootOnly.serial, isNull);
    expect(bootOnly.bootSerial, 'boot-serial');
  });

  test('原记录序列号和 GUID 任一可读冲突均拒绝，严格核验不接受未知序列号', () {
    const facts = DeviceFacts(serial: 'real-serial', guid: 'real-guid');
    facts.assertMatches(
      _record(serial: 'real-serial', guid: 'real-guid'),
      requireKnownSerial: true,
    );
    expect(
      () => facts.assertMatches(_record(serial: 'other', guid: 'real-guid')),
      _failure('device_identity_mismatch'),
    );
    expect(
      () => facts.assertMatches(_record(serial: 'real-serial', guid: 'other')),
      _failure('device_identity_mismatch'),
    );
    expect(
      () => facts.assertMatches(_record(), requireKnownSerial: true),
      _failure('device_identity_unverified'),
    );
    expect(
      () => const DeviceFacts().assertMatches(
        _record(serial: 'real-serial'),
        requireKnownSerial: true,
      ),
      _failure('device_identity_unverified'),
    );
  });

  for (final (index, malformed) in [
    <int>[0xff, 0],
    utf8.encode('serial\x00boot\x00model\x00version\x0036\x00'),
    _properties(model: '伪造\nserial'),
    _properties(guid: 'x' * 257),
    [..._properties(), 0],
  ].indexed) {
    test('拒绝无效 UTF-8、字段边界、控制字符或超长属性 $index', () async {
      final client = _Client((_) => shellOutput(malformed));
      await expectLater(
        const DeviceProbe().readIdentity(
          DeviceConnection(client: client, device: _device),
        ),
        _failure('invalid_data'),
      );
    });
  }

  test('API 级别按十进制 u32 解析，无效属性保持未知', () async {
    for (final invalid in ['0x24', '4294967296', 'NaN', '']) {
      final client = _Client((_) => shellOutput(_properties(api: invalid)));
      final facts = await const DeviceProbe().readIdentity(
        DeviceConnection(client: client, device: _device),
      );
      expect(facts.apiLevel, isNull);
    }
  });

  for (final status in [null, 1]) {
    test('已输出完整属性但缺少成功终态不能伪报探测成功 $status', () async {
      final client = _Client((_) async* {
        yield AdbShellEvent(
          AdbShellChannel.stdout,
          Uint8List.fromList(_properties()),
        );
        if (status != null) {
          yield AdbShellEvent(
            AdbShellChannel.exit,
            Uint8List(0),
            exitCode: status,
          );
        }
      });
      await expectLater(
        const DeviceProbe().readIdentity(
          DeviceConnection(client: client, device: _device),
        ),
        _failure('query_unavailable'),
      );
    });
  }

  test('退出之后的迟到输出不能被拼接成成功回执', () async {
    final client = _Client((_) async* {
      yield* shellOutput(_properties());
      yield AdbShellEvent(AdbShellChannel.stderr, Uint8List(0));
    });
    await expectLater(
      const DeviceProbe().readIdentity(
        DeviceConnection(client: client, device: _device),
      ),
      _failure('invalid_data'),
    );
  });

  test('stdout 与 stderr 共用字节限额，超限仍等待实际命令回收', () async {
    final closing = Completer<void>();
    final released = Completer<void>();
    final client = _Client((_) async* {
      try {
        yield AdbShellEvent(AdbShellChannel.stderr, Uint8List(64 * 1024));
        yield AdbShellEvent(AdbShellChannel.stdout, Uint8List.fromList([1]));
      } finally {
        closing.complete();
        await released.future;
      }
    });
    var finished = false;
    final reading = const DeviceProbe().readIdentity(
      DeviceConnection(client: client, device: _device),
    );
    final rejected = expectLater(reading, _failure('byte_limit')).then((_) {
      finished = true;
    });
    await closing.future;
    expect(finished, isFalse);
    released.complete();
    await rejected;
  });

  test('取消已交回但尚未消费的属性时不接纳迟到事实，并等命令清理确认', () async {
    final cancellation = AdbCancellation();
    final closing = Completer<void>();
    final released = Completer<void>();
    final response = StreamController<AdbShellEvent>(
      onCancel: () async {
        closing.complete();
        await released.future;
      },
    );
    final client = _Client((_) => response.stream);
    var settled = false;
    final reading = const DeviceProbe().readIdentity(
      DeviceConnection(client: client, device: _device),
      cancellation: cancellation,
    );
    final rejected = expectLater(
      reading,
      throwsA(isA<AdbException>().having((e) => e.code, 'code', 'cancelled')),
    ).then((_) => settled = true);
    expect(response.hasListener, isTrue);
    response.add(
      AdbShellEvent(AdbShellChannel.stdout, Uint8List.fromList(_properties())),
    );
    response.add(
      AdbShellEvent(AdbShellChannel.exit, Uint8List(0), exitCode: 0),
    );
    cancellation.cancel();
    await closing.future;
    expect(settled, isFalse);
    released.complete();
    await rejected;
    await response.close();
  });

  test('SDK 超时仍须等待真实收尾，调用方不会收到被丢弃 Future 的早退结果', () async {
    final closing = Completer<void>();
    final released = Completer<void>();
    const timedOut = AdbException('timed_out', '设备没有回应');
    final client = _Client((query) async* {
      expect(query.timeout, const Duration(milliseconds: 5));
      try {
        throw timedOut;
      } finally {
        closing.complete();
        await released.future;
      }
    });
    var settled = false;
    final reading = const DeviceProbe().readIdentity(
      DeviceConnection(client: client, device: _device),
      timeout: const Duration(milliseconds: 5),
    );
    final rejected = expectLater(reading, throwsA(same(timedOut))).then((_) {
      settled = true;
    });
    await closing.future;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(settled, isFalse);
    released.complete();
    await rejected;
  });

  test('外部取消发生在完整输出之后、实际收尾之前也不能交付事实', () async {
    final cancellation = AdbCancellation();
    final closing = Completer<void>();
    final released = Completer<void>();
    final client = _Client((_) async* {
      try {
        yield* shellOutput(_properties());
      } finally {
        closing.complete();
        await released.future;
      }
    });
    final reading = const DeviceProbe().readIdentity(
      DeviceConnection(client: client, device: _device),
      cancellation: cancellation,
    );
    final rejected = expectLater(
      reading,
      throwsA(isA<AdbException>().having((e) => e.code, 'code', 'cancelled')),
    );
    await closing.future;
    cancellation.cancel();
    released.complete();
    await rejected;
  });

  test('清理失败保留真实错误，不把它伪装成成功或普通输出失败', () async {
    final cleanupFailure = StateError('原生 worker 尚未退出');
    final client = _Client((_) async* {
      try {
        yield* shellOutput(_properties());
      } finally {
        throw cleanupFailure;
      }
    });
    await expectLater(
      const DeviceProbe().readIdentity(
        DeviceConnection(client: client, device: _device),
      ),
      throwsA(same(cleanupFailure)),
    );
  });

  test('已取消或无效超时不启动任何设备命令', () async {
    final client = _Client((_) => shellOutput(_properties()));
    final connection = DeviceConnection(client: client, device: _device);
    final cancellation = AdbCancellation()..cancel();
    await expectLater(
      const DeviceProbe().readIdentity(connection, cancellation: cancellation),
      throwsA(isA<AdbException>()),
    );
    await expectLater(
      const DeviceProbe().readIdentity(connection, timeout: Duration.zero),
      throwsArgumentError,
    );
    expect(client.calls, isEmpty);
  });

  test('可选电量被扣留时身份仍可完成，不以供电状态猜测充电', () async {
    final batteryStarted = Completer<void>();
    final batteryResponse = Completer<void>();
    final client = _Client((query) async* {
      if (query.command == 'dumpsys battery') {
        expect(query.timeout, const Duration(seconds: 3));
        batteryStarted.complete();
        await batteryResponse.future;
        yield* shellOutput(
          utf8.encode(
            'level: 39\nscale: 50\nstatus: 4\nUSB powered: true\n'
            'temperature: 321\nvoltage: 4120\nhealth: 2\n',
          ),
        );
      } else {
        yield* shellOutput(_properties());
      }
    });
    final connection = DeviceConnection(client: client, device: _device);
    var batterySettled = false;
    final battery = const DeviceProbe().readBattery(connection).then((value) {
      batterySettled = true;
      return value;
    });
    await batteryStarted.future;
    final facts = await const DeviceProbe().readIdentity(connection);
    expect(facts.serial, 'hardware-serial');
    expect(batterySettled, isFalse);
    batteryResponse.complete();
    final value = await battery;
    expect(value.level, 78);
    expect(value.charging, isFalse);
    expect(value.temperatureC, 32.1);
    expect(value.voltageMv, 4120);
    expect(value.health, 2);
  });
}

List<int> _properties({
  String serial = 'hardware-serial',
  String bootSerial = 'boot-serial',
  String model = '目标手机',
  String release = '16',
  String api = '36',
  String guid = 'wireless-guid',
}) => utf8.encode(
  '$serial\x00$bootSerial\x00$model\x00$release\x00$api\x00$guid\x00',
);

final class _Query {
  const _Query(this.device, this.command, this.timeout, this.cancellation);
  final AdbDevice device;
  final String command;
  final Duration timeout;
  final AdbCancellation? cancellation;
}

final class _Client implements AdbClient {
  _Client(this.respond);
  final Stream<AdbShellEvent> Function(_Query) respond;
  final calls = <_Query>[];

  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) {
    final query = _Query(device, command, timeout, cancellation);
    calls.add(query);
    return respond(query);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Matcher _failure(String code) =>
    throwsA(isA<RequestFailure>().having((error) => error.code, 'code', code));

DeviceRecord _record({String? serial, String? guid}) => DeviceRecord(
  id: '0b771116-878d-42d5-a47a-3179cc4ae758',
  name: '旧名称',
  address: '192.0.2.1',
  port: 5555,
  transport: DeviceTransport.tcp,
  serial: serial,
  guid: guid,
  model: '旧型号',
  androidVersion: '旧版本',
  apiLevel: 30,
);
