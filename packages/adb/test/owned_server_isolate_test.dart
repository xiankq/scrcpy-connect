import 'dart:io';
import 'dart:isolate';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final binary = Platform.environment['INTEROP_OFFICIAL_ADB_BINARY'];
  test(
    '真实isolate退出后认领同Child，旧lease不能关闭新owner且不改身份',
    () async {
      final root = await Directory.systemTemp.createTemp('adb-isolate-owner-');
      final dataPath = root.path;
      final binaryPath = File(binary!).parent.path;
      addTearDown(() async {
        final api = await createNativeAdbApi();
        final servers = api as NativeAdbServerApi;
        for (final entry in await servers.listServers()) {
          final home = entry.launch.environment['ANDROID_USER_HOME'];
          if (home != null && p.isWithin(dataPath, home)) {
            await servers.closeServer(entry.leaseId);
          }
        }
        await root.delete(recursive: true);
      });
      // 返回即代表原isolate已退出；没有保留原AdbHost对象，也没有调用close。
      final before = await Isolate.run(
        () => _prepareInIsolate(dataPath, binaryPath),
      );
      final oldLease = before['leaseId'] as String;
      final after = await Isolate.run(
        () => _restoreInIsolate(dataPath, binaryPath, oldLease),
      );
      expect(after['serverId'], before['serverId']);
      expect(after['pid'], before['pid']);
      expect(before['pid'], isA<int>());
      expect(after['leaseId'], isNot(before['leaseId']));
      expect(after['bytes'], before['bytes']);
      expect(after['modified'], before['modified']);
      expect(after['oldClosePreserved'], isTrue);
      expect(after['removed'], isTrue);
      await expectLater(
        Socket.connect('127.0.0.1', before['port'] as int),
        throwsA(isA<SocketException>()),
      );
    },
    skip: binary == null ? '需要显式受控官方ADB二进制' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('真实受控CLI使用数字-H时监听者缺失不自动启动daemon', () async {
    final directory = await Directory.systemTemp.createTemp(
      'adb-no-autostart-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final result = await Process.run(
      binary!,
      ['-H', '127.0.0.1', '-P', '$port', 'devices'],
      environment: {
        'ANDROID_USER_HOME': directory.path,
        'ADB_MDNS_AUTO_CONNECT': '0',
      },
    );
    expect(result.exitCode, isNot(0));
    expect(
      result.stderr.toString(),
      contains('cannot start server on remote host'),
    );
    await expectLater(
      Socket.connect('127.0.0.1', port),
      throwsA(isA<SocketException>()),
    );
  }, skip: binary == null ? '需要显式受控官方ADB二进制' : false);
}

Future<Map<String, Object?>> _prepareInIsolate(
  String dataPath,
  String binaryPath,
) async {
  final host = await AdbHost.prepare(
    bindings: await createNativeAdbApi(),
    dataDirectory: Directory(dataPath),
    binaryDirectory: Directory(binaryPath),
  );
  final configuration = host.nativeConfiguration!;
  final api = await createNativeAdbApi();
  final info = (await (api as NativeAdbServerApi).listServers()).singleWhere(
    (entry) => entry.leaseId == configuration['leaseId'],
  );
  final identity = File(configuration['identityPath'] as String);
  return {
    ...configuration,
    'pid': info.pid,
    'bytes': await identity.readAsBytes(),
    'modified': (await identity.lastModified()).microsecondsSinceEpoch,
  };
}

Future<Map<String, Object?>> _restoreInIsolate(
  String dataPath,
  String binaryPath,
  String oldLease,
) async {
  final api = await createNativeAdbApi();
  final servers = api as NativeAdbServerApi;
  final host = await AdbHost.restore(
    dataDirectory: Directory(dataPath),
    binaryDirectory: Directory(binaryPath),
    bindings: api,
    leaseId: oldLease,
  );
  final configuration = host.nativeConfiguration!;
  try {
    await servers.closeServer(oldLease);
    final info = (await servers.listServers()).singleWhere(
      (entry) => entry.leaseId == configuration['leaseId'],
    );
    final identity = File(configuration['identityPath'] as String);
    final result = {
      ...configuration,
      'pid': info.pid,
      'oldClosePreserved': info.phase == AdbServerPhase.ready,
      'bytes': await identity.readAsBytes(),
      'modified': (await identity.lastModified()).microsecondsSinceEpoch,
    };
    await host.close();
    return {
      ...result,
      'removed': !(await servers.listServers()).any(
        (entry) => entry.serverId == info.serverId,
      ),
    };
  } finally {
    await host.close();
  }
}
