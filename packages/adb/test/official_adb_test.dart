import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final binary = Platform.environment['INTEROP_OFFICIAL_ADB_BINARY'];
  final key = Platform.environment['INTEROP_OFFICIAL_ADB_KEY'];
  final address = Platform.environment['INTEROP_OFFICIAL_ADBD'];
  test(
    'owned official adb controls discovery and terminates only its server',
    () async {
      final root = await Directory.systemTemp.createTemp('flutter-adb-real-');
      addTearDown(() => root.delete(recursive: true));
      await File(key!).copy(p.join(root.path, 'host_identity.pem'));
      final host = await AdbHost.prepare(
        bindings: await createNativeAdbApi(),
        dataDirectory: root,
        binaryDirectory: File(binary!).parent,
      );
      addTearDown(host.close);
      final client = host.client;
      final device = await client.connect(address!);
      expect(
        (await client.devices()).any(
          (d) => d.serial == address && d.state == 'device',
        ),
        isTrue,
      );
      // 完整二进制服务由 device_runtime/test/adb_services_native_test.dart
      // 使用真实生成适配器验证；本独立包测试仅负责官方守护进程和控制进程的生命周期。
      await client.disconnect(device);
      final port = host.nativeConfiguration!['port'] as int;
      await host.close();
      await expectLater(
        Socket.connect('127.0.0.1', port),
        throwsA(isA<SocketException>()),
      );
    },
    skip: binary == null || key == null || address == null
        ? 'Set explicit authorized official adb binary/key/adbd fixture'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
