import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final target = Platform.environment['INTEROP_SCRCPY_AVD'];
  final serverPath = Platform.environment['INTEROP_SCRCPY_SERVER_JAR'];
  final identityPath = Platform.environment['INTEROP_ADB_KEY'];
  test(
    '独立 scrcpy 动态库用配套 ADB 创建、控制和关闭真实捕获',
    () async {
      final directory = await Directory.systemTemp.createTemp('scrcpy-sdk-');
      ScrcpyNativeHost? host;
      ScrcpySession? session;
      try {
        final identity = await File(identityPath!)
            .copy('${directory.path}/identity.pem');
        host = await createNativeScrcpyHost(
          serverBytes: await File(serverPath!).readAsBytes(),
          identityPath: identity.path,
        );
        final device = await host.adb.connect(target!);
        expect(
          (await host.adb.devices()).any((entry) => entry.id == device.id),
          isTrue,
        );
        await expectLater(
          host.scrcpy.createSession(
            AdbDevice(
              id: device.id,
              serial: device.serial,
              state: device.state,
              nativeOwner: Object(),
            ),
          ),
          throwsA(
            isA<ScrcpyException>().having(
              (error) => error.code,
              'code',
              'foreign_connection',
            ),
          ),
        );
        session = await host.scrcpy.createSession(
          device,
          options: const ScrcpyOptions(maxSize: 720, maxFps: 30),
        );
        final info = await session.start();
        expect(info.source!.attachAddress, greaterThan(0));
        expect(info.source!.detachAddress, greaterThan(0));
        final receipt = await session.sendControl(
          const ScrcpyClipboard('独立桥接回归'),
        );
        expect(
          receipt.completion,
          ScrcpyControlCompletion.clipboardAcknowledged,
        );
        await session.close();
        session = null;
        final output = await host.adb
            .shell(device, 'printf sdk-connection-alive')
            .toList();
        expect(
          utf8.decode(output.expand((event) => event.bytes).toList()),
          'sdk-connection-alive',
        );
        await host.adb.disconnect(device);
      } finally {
        try {
          await session?.close();
        } finally {
          try {
            await host?.close();
          } finally {
            await directory.delete(recursive: true);
          }
        }
      }
    },
    skip: target == null || serverPath == null || identityPath == null
        ? '需要已授权目标、显式服务器 JAR 和测试身份。'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
