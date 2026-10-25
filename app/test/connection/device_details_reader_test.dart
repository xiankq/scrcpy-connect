import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/connection/connection_owner.dart';
import 'package:scrcpy_connect/connection/device_details_reader.dart';
import 'package:scrcpy_connect/connection/records/device_record_store.dart';

void main() {
  late Directory directory;
  late DeviceRecordStore records;
  late DeviceRecord record;
  late _Client client;
  late DeviceConnection? current;
  late DeviceDetailsReader details;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('device-details-');
    records = await DeviceRecordStore.open(directory: directory);
    record = await records.add(address: '192.0.2.7', port: 5555);
    client = _Client();
    current = DeviceConnection(client: client, device: _device);
    details = DeviceDetailsReader(
      records: records,
      connectionForDevice: (id) => id == record.id ? current : null,
      now: () => DateTime.fromMillisecondsSinceEpoch(123456000),
    );
  });
  tearDown(() => directory.delete(recursive: true));

  Future<Map<String, Object?>> request(
    String name, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) => details.command(name, {
    'deviceId': record.id,
    'connectionId': ?connectionId,
  }, cancellation: cancellation);

  test('以实际连接为准，完整详情不依赖记录中的在线标记或补齐旧动态值', () async {
    client.responses.addAll({
      'getprop':
          '[ro.product.model]: [手机]\n[ro.build.version.sdk]: [36]\n'
          '[ro.product.cpu.abilist]: []\n[ro.product.cpu.abi]: [arm64-v8a]',
      'dumpsys battery':
          'level: 39\nscale: 50\nstatus: 4\n'
          'USB powered: true\ntemperature: 321\nvoltage: 4120\nhealth: 2',
      'wm size; wm density; dumpsys display':
          'Physical size: 1440x3120\n'
          'Override size: 1080x2340\nPhysical density: 560\nOverride density: 420\n'
          'DisplayInfo{Built-in, displayId 0, renderFrameRate 60.000004, supportedModes [fps=120]}\n'
          'DisplayInfo{Virtual, displayId 3, renderFrameRate 90,}',
      'dumpsys power; dumpsys window policy':
          'mWakefulness=Asleep\nmKeyguardShowing=true',
      'ip -o addr show': _addresses,
      'cat /proc/meminfo; cat /sys/devices/system/cpu/present':
          'MemTotal: 1024 kB\nMemAvailable: 512 kB\n0-3,6,6-7\n',
      'df -k /data':
          'Filesystem 1K-blocks Used Available Use% Mounted on\n'
          '/dev/block/dm-1 2097152 1048576 1048576 50% /data',
    });
    final result = await request('device.data.get', connectionId: 'physical-1');
    expect(result['connectionId'], 'physical-1');
    expect(result['observedAt'], 123456);
    expect(result['stale'], isFalse);
    expect(result['failures'], isEmpty);
    expect(_map(result, 'system'), containsPair('model', '手机'));
    expect(_map(result, 'system'), containsPair('abi', 'arm64-v8a'));
    expect(_map(result, 'battery'), containsPair('level', 78));
    expect(_map(result, 'battery'), containsPair('charging', false));
    expect(_map(result, 'battery'), containsPair('temperatureC', 32.1));
    expect(_map(result, 'display'), {
      'width': 1080,
      'height': 2340,
      'densityDpi': 420,
      'refreshRate': 60.000004,
      'screenOn': false,
      'locked': true,
    });
    expect(_map(result, 'memory'), {
      'totalBytes': 1048576,
      'availableBytes': 524288,
    });
    expect(_map(result, 'processor'), {'cores': 6});
    expect(_map(result, 'storage'), {
      'totalBytes': 2147483648,
      'availableBytes': 1073741824,
    });
    expect(client.commands, hasLength(7));
    expect(client.factReads, 2);
    expect(records.current.find(record.id)!.status, 'offline');
  });

  test('离线仅显示带时间的本机稳定信息，缓存 connected 和电量不能证明实时连接', () async {
    await records.update(
      record.id,
      (old) => old.copyWith(
        status: 'connected',
        model: '旧型号',
        androidVersion: '15',
        apiLevel: 35,
        lastSeen: 100,
        battery: 99,
        charging: true,
      ),
    );
    current = null;
    final result = await request('device.data.get');
    expect(result, {
      'deviceId': record.id,
      'stale': true,
      'observedAt': 100,
      'system': {'model': '旧型号', 'androidVersion': '15', 'apiLevel': 35},
    });
    expect(client.commands, isEmpty);
    expect(client.factReads, 0);
    await expectLater(
      request('device.data.get', connectionId: 'physical-1'),
      _failure('stale_connection'),
    );
    await expectLater(request('device.network.get'), _failure('disconnected'));
  });

  test('查询前核对物理连接标识、关闭事实与缺失事实，拒绝启动远端命令', () async {
    await expectLater(
      request('device.network.get', connectionId: 'other'),
      _failure('stale_connection'),
    );
    client.closed = true;
    await expectLater(
      request('device.network.get'),
      _failure('stale_connection'),
    );
    client.closed = false;
    client.physicalId = null;
    await expectLater(
      request('device.network.get'),
      _failure('query_unavailable'),
    );
    expect(client.commands, isEmpty);
  });

  test('查询间撤准入立即停止，不把旧连接回执放入后继设备详情', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    client.reply = (command) async* {
      started.complete();
      await release.future;
      yield* _output('[ro.product.model]: [旧手机]');
    };
    final rejected = expectLater(
      request('device.data.get'),
      _failure('stale_connection'),
    );
    await started.future;
    current = DeviceConnection(client: client, device: _device);
    release.complete();
    await rejected;
    expect(client.commands, ['getprop']);
  });

  test('同一 Dart 句柄下物理连接替换也不能发布旧查询', () async {
    client.reply = (_) async* {
      client.physicalId = 'physical-2';
      yield* _output(_addresses);
    };
    await expectLater(
      request('device.network.get'),
      _failure('stale_connection'),
    );
  });

  test('查询失败回执迟到且设备已移除时按失效拒绝，不返回混合的分组错误', () async {
    client.reply = (_) async* {
      await records.remove(record.id);
      throw const AdbException('timeout', 'query timed out');
    };
    await expectLater(request('device.data.get'), _failure('stale_connection'));
    expect(client.commands, hasLength(1));
  });

  test('普通分组失败保留具体原因，其他未知字段不转成确定值', () async {
    client.reply = (command) => command == 'dumpsys battery'
        ? Stream.error(const AdbException('permission_denied', '受限'))
        : _output('');
    final result = await request('device.data.get');
    expect(_map(result, 'failures'), {
      'battery': {'code': 'permission_denied', 'message': '受限'},
    });
    expect(_map(result, 'battery').values, everyElement(isNull));
    expect(_map(result, 'display').values, everyElement(isNull));
    expect(_map(result, 'memory').values, everyElement(isNull));
    expect(_map(result, 'storage').values, everyElement(isNull));
  });

  test('取消中止整个查询，不降格为可忽略的分组失败', () async {
    final cancellation = AdbCancellation();
    client.reply = (_) async* {
      cancellation.cancel();
      yield* _output('');
    };
    await expectLater(
      request('device.data.get', cancellation: cancellation),
      _failure('cancelled'),
    );
    expect(client.commands, hasLength(1));
  });

  test('地址来自目标接口，过滤特殊地址、去重并保留 IPv6 链路作用域', () async {
    client.responses['ip -o addr show'] = _addresses;
    final result = await request('device.network.get');
    expect(result['addresses'], [
      {'interface': 'wlan0', 'address': '192.168.1.8'},
      {'interface': 'wlan0', 'address': 'fe80::1%wlan0'},
      {'interface': 'tun0', 'address': '10.0.0.2'},
    ]);
  });

  for (final (text, screenOn, locked) in <(String, bool?, bool?)>[
    ('unknown OEM dump\nshowing=true', null, null),
    (
      'mWakefulness=Awake\nKeyguardServiceDelegate\n showing=false',
      true,
      false,
    ),
    ('mInteractive=false\nmKeyguardShowing=true', false, true),
    ('mWakefulness=Dozing\nmKeyguardShowing=trueevil', false, null),
    ('KeyguardService:\nOtherService:\n showing=true', null, null),
  ]) {
    test('屏幕事实保留未知，不误用其他服务的 showing：$text', () async {
      client.responses['dumpsys power; dumpsys window policy'] = text;
      final result = await request('device.screen.state');
      expect(result['screenOn'], screenOn);
      expect(result['locked'], locked);
    });
  }

  test('只接纳默认显示器唯一前台包名，不从其他屏幕或多个候选猜测', () async {
    client.responses['dumpsys activity activities'] =
        'Display #0:\n mResumedActivity: ActivityRecord{a u0 com.example.app/.Main t42}\n'
        'Display #2:\n mResumedActivity: ActivityRecord{b u0 com.other.app/.Main t43}';
    expect(
      (await request('apps.foreground'))['packageName'],
      'com.example.app',
    );
    client.responses['dumpsys activity activities'] =
        'mResumedActivity: com.one.app/.A\ntopResumedActivity=com.two.app/.B';
    await expectLater(
      request('apps.foreground'),
      _failure('foreground_unavailable'),
    );
  });

  test('不采用支持模式最大刷新率，无效计数、溢出和错误挂载点保持未知', () async {
    client.responses.addAll({
      'wm size; wm density; dumpsys display':
          'mSupportedModes=[fps=120]\nPhysical size: 0x1440\n'
          'DisplayInfo{Virtual, displayId 2, renderFrameRate 90,}',
      'cat /proc/meminfo; cat /sys/devices/system/cpu/present': 'MemTotal: 9223372036854775807 kB\nMemAvailable: -1 kB\n0-99999999999',
      'df -k /data': '/dev/block/dm-1 100 50 50 50% /data/media',
      'dumpsys battery': 'status: 2.9\nhealth: NaN\nlevel: 101\nscale: 100',
    });
    final result = await request('device.data.get');
    expect(_map(result, 'display')['refreshRate'], isNull);
    expect(_map(result, 'display')['width'], isNull);
    expect(_map(result, 'memory').values, everyElement(isNull));
    expect(_map(result, 'storage').values, everyElement(isNull));
    expect(_map(result, 'processor')['cores'], isNull);
    expect(_map(result, 'battery')['charging'], isNull);
    expect(_map(result, 'battery')['level'], isNull);
  });

  test('有界查询拒绝超大或无退出回执的输出，仍可展示其他查询结果', () async {
    client.reply = (command) async* {
      if (command == 'getprop') {
        yield AdbShellEvent(AdbShellChannel.stderr, Uint8List(256 * 1024 + 1));
      } else if (command == 'dumpsys battery') {
        yield AdbShellEvent(
          AdbShellChannel.stdout,
          Uint8List.fromList(utf8.encode('level: 99\nscale: 100')),
        );
      } else {
        yield* _output('');
      }
    };
    final result = await request('device.data.get');
    final failures = _map(result, 'failures');
    expect(_map(failures, 'system')['code'], 'byte_limit');
    expect(_map(failures, 'battery')['code'], 'query_unavailable');
    expect(_map(result, 'battery')['level'], isNull);
  });
}

Map<String, Object?> _map(Map<String, Object?> value, String key) =>
    value[key]! as Map<String, Object?>;

Matcher _failure(String code) => throwsA(
  isA<ApplicationCommandException>().having((e) => e.code, 'code', code),
);

const _device = AdbDevice(
  id: 'native-handle',
  serial: 'selector',
  state: 'device',
);
const _addresses =
    '1: lo inet 127.0.0.1/8 scope host lo\n'
    '2: wlan0 inet 192.168.1.8/24 scope global wlan0\n'
    '2: wlan0 inet6 fe80::1/64 scope link\n'
    '3: tun0@NONE inet 10.0.0.2/24 scope global\n'
    '2: wlan0 inet 192.168.1.8/24 scope global\n'
    '2: wlan0 inet 224.0.0.1/4 scope global\n'
    '2: wlan0 inet6 ff02::1/16 scope link\n'
    '2: wlan0 inet 0.0.0.0/0 scope global';

Stream<AdbShellEvent> _output(String text) async* {
  yield AdbShellEvent(
    AdbShellChannel.stdout,
    Uint8List.fromList(utf8.encode(text)),
  );
  yield AdbShellEvent(AdbShellChannel.exit, Uint8List(0), exitCode: 0);
}

final class _Client implements AdbClient {
  final responses = <String, String>{};
  final commands = <String>[];
  Stream<AdbShellEvent> Function(String)? reply;
  String? physicalId = 'physical-1';
  bool closed = false;
  int factReads = 0;
  @override
  late final services = AdbServices(
    () => _Facts(this),
    (device) async => device,
    () {},
  );

  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) {
    commands.add(command);
    return reply?.call(command) ?? _output(responses[command] ?? '');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Facts implements NativeAdbApi {
  _Facts(this.client);
  final _Client client;
  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async {
    client.factReads++;
    return AdbConnectionFacts(
      officialServer: false,
      closed: client.closed,
      features: const [],
      connectionId: client.physicalId,
      burstMode: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
