import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binary = Platform.environment['INTEROP_OFFICIAL_ADB_BINARY'];
  final probe = [
    '/bin/true',
    '/usr/bin/true',
  ].where((path) => File(path).existsSync()).firstOrNull;
  final heldProgram = [
    '/bin/cat',
    '/usr/bin/cat',
  ].where((path) => File(path).existsSync()).firstOrNull;
  test(
    'Dart进程回收器启用后原生官方CLI仍保留真实退出回执并精确关闭服务器',
    () async {
      final held = await Process.start(heldProgram!, const []);
      final drained = Future.wait([
        held.stdout.drain<void>(),
        held.stderr.drain<void>(),
      ]);
      var heldExited = false;
      final heldExit = held.exitCode.then((code) {
        heldExited = true;
        return code;
      });
      try {
        final first = await Process.run(probe!, const []);
        expect(first.exitCode, 0);
        expect(heldExited, isFalse);
        final root = await Directory.systemTemp.createTemp(
          'adb-process-interop-',
        );
        addTearDown(() => root.delete(recursive: true));
        final host = await AdbHost.prepare(
          dataDirectory: root,
          binaryDirectory: File(binary!).parent,
          oneDevice: 'interop-test-no-usb-device',
        );
        addTearDown(host.close);
        for (var index = 0; index < 25; index++) {
          // cat 直到 stdin EOF 才退出，真实存活窗口覆盖全部 CLI，不依赖调度延迟。
          expect(heldExited, isFalse);
          final devices = await host.client.devices();
          expect(heldExited, isFalse);
          expect(devices.every((device) => device.serial.isNotEmpty), isTrue);
        }
        final port = host.nativeConfiguration!['port'] as int;
        await host.close();
        expect(heldExited, isFalse);
        await expectLater(
          Socket.connect('127.0.0.1', port),
          throwsA(isA<SocketException>()),
        );
      } finally {
        // 明确 EOF 并等待真实退出及双管道结束，不能遗留用于竞争的 Dart Child。
        await held.stdin.close();
        expect(await heldExit, 0);
        await drained;
      }
    },
    skip: binary == null || probe == null || heldProgram == null
        ? '需要显式受控ADB二进制及Linux/macOS系统true、cat程序'
        : false,
  );
}
