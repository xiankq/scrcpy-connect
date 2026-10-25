import 'dart:async';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:adb/src/official_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/owned_server_fake.dart';

Matcher _error(String code) =>
    throwsA(isA<AdbException>().having((error) => error.code, 'code', code));

Future<OfficialAdbClient> _client(OwnedServerFake api) async {
  final client = OfficialAdbClient(api, await api.readyServer());
  addTearDown(() async {
    api.commandCloseGate = null;
    api.createCommandGate = null;
    await client.close();
    await api.dispose();
  });
  return client;
}

void main() {
  test('类型化发现保留 USB 与无线原始元数据和非在线状态，不开启连接', () async {
    final api = OwnedServerFake()
      ..running = (_, _) async => commandResult('''
List of devices attached
usb-phone device usb:1-2.3 product:oriole model:Pixel_6 device:oriole transport_id:11
192.0.2.20:4444 device product:panther model:Pixel_7 device:panther transport_id:12
usb-locked unauthorized usb:2-1 transport_id:13
192.0.2.21:5555 offline transport_id:14
''');
    final client = await _client(api);
    final AdbTransportDiscovery discovery = client;
    final values = await discovery.transports(
      timeout: const Duration(milliseconds: 837),
    );
    expect(values.map((value) => value.serial), [
      'usb-phone',
      '192.0.2.20:4444',
      'usb-locked',
      '192.0.2.21:5555',
    ]);
    expect(values.first.usbPath, '1-2.3');
    expect(values.first.model, 'Pixel_6');
    expect(values.first.product, 'oriole');
    expect(values.first.device, 'oriole');
    expect(values.first.transportId, 11);
    expect(values[1].usbPath, isNull);
    expect(values[2].state, 'unauthorized');
    expect(values[2].usbPath, '2-1');
    expect(values[3].state, 'offline');
    expect(values[3].model, isNull);
    expect(api.arguments(api.specs.keys.single), ['devices', '-l']);
    expect(api.specs.values.single.timeoutMs, 837);
    expect(api.specs.values.single.mayCreateTransport, isFalse);
    expect(api.opened, isEmpty);
    expect(() => values.clear(), throwsUnsupportedError);
  });

  test('没有 usb 字段的 USB 形状序列号保持未知，权限帮助文本不冒充设备状态', () async {
    final api = OwnedServerFake()
      ..running = (_, _) async => commandResult('''
List of devices attached
ABC123 unauthorized transport_id:2
denied no permissions (user in plugdev group; are your udev rules wrong?); see [http://developer.android.com/tools/device.html] usb:3-2 transport_id:3
''');
    final client = await _client(api);
    final values = await client.transports();
    expect(values.first.usbPath, isNull);
    expect(values.last.state, 'no permissions');
    expect(values.last.usbPath, '3-2');
    expect(values.last.transportId, 3);
  });

  test('旧 devices 仍解析在线精确句柄，发现本身不创建握手或无线连接', () async {
    final api = OwnedServerFake()
      ..running = (_, _) async => commandResult('''
List of devices attached
usb-phone device usb:1-2 transport_id:1
other unauthorized usb:1-3 transport_id:2
''');
    final client = await _client(api);
    await client.transports();
    expect(api.handshakes, isEmpty);
    final devices = await client.devices();
    expect(devices.first.serial, 'usb-phone');
    expect(devices.first.id, isNot('usb-phone'));
    expect(devices.last.serial, 'other');
    expect(devices.last.state, 'unauthorized');
    expect(api.opened, ['usb-phone']);
    expect(api.specs.keys.map(api.arguments), everyElement(['devices', '-l']));
  });

  for (final response in [
    'wrong header\nphone device\n',
    'List of devices attached\nphone\n',
    'List of devices attached\nphone broken\n',
    'List of devices attached\nphone device usb:\n',
    'List of devices attached\nphone device unexpected\n',
    'List of devices attached\nphone device usb:1 usb:2\n',
    'List of devices attached\nphone device transport_id:0\n',
    'List of devices attached\nphone device transport_id:-1\n',
    'List of devices attached\nphone device transport_id:9223372036854775808\n',
    'List of devices attached\nphone device\nphone unauthorized\n',
    'List of devices attached\nphone device transport_id:2\nother device transport_id:2\n',
    'List of devices attached\nphone device\x00 usb:1\n',
  ]) {
    test('异常或重复传输完整拒绝：${response.replaceAll('\n', r'\n')}', () async {
      final api = OwnedServerFake()
        ..running = (_, _) async => commandResult(response);
      final client = await _client(api);
      await expectLater(
        client.transports(),
        _error('invalid_devices_response'),
      );
      expect(api.opened, isEmpty);
      expect(api.commandCloses, hasLength(1));
    });
  }

  test('非法 UTF8 与非零退出不能作为空的成功列表', () async {
    final api = OwnedServerFake()
      ..running = (_, _) async => AdbServerCommandResult(
        status: AdbServerCommandStatus.exited,
        exitCode: 0,
        stdout: Uint8List.fromList([0xff]),
        stderr: Uint8List(0),
      );
    final client = await _client(api);
    await expectLater(client.transports(), _error('invalid_devices_response'));
    api.running = (_, _) async =>
        commandResult('List of devices attached\n', exit: 1);
    await expectLater(client.transports(), _error('devices_failed'));
  });

  test('取消等待真实退出及精确 close，迟到正常退出不能交付发现结果', () async {
    final api = _ClosingCommandApi();
    final started = Completer<void>(),
        cancelled = Completer<void>(),
        exited = Completer<void>();
    final closed = Completer<void>();
    api.commandCloseGate = closed.future;
    api.running = (_, _) async {
      started.complete();
      await exited.future;
      return commandResult('List of devices attached\nphone device usb:1-2\n');
    };
    api.cancelling = (_) {
      if (!cancelled.isCompleted) cancelled.complete();
    };
    final client = await _client(api);
    final stop = AdbCancellation();
    var finished = false;
    final pending = client.transports(cancellation: stop).whenComplete(() {
      finished = true;
    });
    final rejected = expectLater(pending, _error('cancelled'));
    await started.future;
    stop.cancel();
    await cancelled.future;
    expect(finished, isFalse);
    exited.complete();
    // close 必须仍持有已经退出命令的精确回执，不能丢下它立即返回。
    await api.closing.future;
    expect(finished, isFalse);
    closed.complete();
    await rejected;
    expect(api.commandCancels, [api.specs.keys.single]);
    expect(api.commandCloses, [api.specs.keys.single]);
    expect(api.entries.values.single.transportStateUnknown, isFalse);
    expect(api.opened, isEmpty);
  });
}

final class _ClosingCommandApi extends OwnedServerFake {
  final closing = Completer<void>();
  @override
  Future<void> closeServerCommand(String id) {
    final pending = super.closeServerCommand(id);
    if (!closing.isCompleted) closing.complete();
    return pending;
  }
}
