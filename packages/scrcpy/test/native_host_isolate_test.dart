import 'dart:io';
import 'dart:isolate';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';

void main() {
  final binary = Platform.environment['INTEROP_OFFICIAL_ADB_BINARY'];
  final serverPath =
      Platform.environment['INTEROP_SCRCPY_SERVER_JAR'] ??
      File('../../servers/vendor/scrcpy-server-v5.0.1').absolute.path;
  test(
    'scrcpy同库跨isolate列举认领同Child，不重启或重写身份',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'scrcpy-isolate-owner-',
      );
      final dataPath = root.path;
      final binaryPath = File(binary!).parent.path;
      addTearDown(() async {
        for (final entry in await listNativeScrcpyServers()) {
          final home = entry.launch.environment['ANDROID_USER_HOME'];
          if (home != null &&
              Directory(home).absolute.uri
                  .toString()
                  .startsWith(Directory(dataPath).absolute.uri.toString())) {
            final host = await restoreNativeScrcpyHost(
              serverBytes: await File(serverPath).readAsBytes(),
              dataDirectory: Directory(dataPath),
              binaryDirectory: Directory(binaryPath),
              leaseId: entry.leaseId,
            );
            await host.close();
          }
        }
        await root.delete(recursive: true);
      });
      final before = await Isolate.run(
        () => _create(dataPath, binaryPath, serverPath),
      );
      final after = await Isolate.run(
        () => _restore(
          dataPath,
          binaryPath,
          serverPath,
          before['leaseId'] as String,
        ),
      );
      expect(after['serverId'], before['serverId']);
      expect(after['pid'], before['pid']);
      expect(after['pid'], isA<int>());
      expect(after['leaseId'], isNot(before['leaseId']));
      expect(after['bytes'], before['bytes']);
      expect(after['modified'], before['modified']);
      expect(after['removed'], isTrue);
      expect(after['staleCode'], 'host_unavailable');
      await expectLater(
        Socket.connect('127.0.0.1', before['port'] as int),
        throwsA(isA<SocketException>()),
      );
    },
    skip: binary == null ? '需要显式受控官方ADB二进制' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<Map<String, Object?>> _create(
  String dataPath,
  String binaryPath,
  String serverPath,
) async {
  final host = await createNativeScrcpyHost(
    serverBytes: await File(serverPath).readAsBytes(),
    identityPath: File.fromUri(Directory(dataPath).uri.resolve('identity.pem'))
        .path,
    dataDirectory: Directory(dataPath),
    binaryDirectory: Directory(binaryPath),
  );
  // 不关闭宿主，返回后销毁原isolate，原生Child必须独立继续存活。
  return _facts(host);
}

Future<Map<String, Object?>> _restore(
  String dataPath,
  String binaryPath,
  String serverPath,
  String oldLease,
) async {
  final before = (await listNativeScrcpyServers()).singleWhere(
    (entry) => entry.leaseId == oldLease,
  );
  if (before.phase != AdbServerPhase.ready) {
    throw StateError('原isolate退出后服务器未保持ready');
  }
  final host = await restoreNativeScrcpyHost(
    serverBytes: await File(serverPath).readAsBytes(),
    dataDirectory: Directory(dataPath),
    binaryDirectory: Directory(binaryPath),
    leaseId: oldLease,
  );
  try {
    final result = await _facts(host);
    String? staleCode;
    try {
      final unexpected = await restoreNativeScrcpyHost(
        serverBytes: await File(serverPath).readAsBytes(),
        dataDirectory: Directory(dataPath),
        binaryDirectory: Directory(binaryPath),
        leaseId: oldLease,
      );
      await unexpected.close();
    } on AdbException catch (error) {
      staleCode = error.code;
    }
    await host.close();
    return {
      ...result,
      'staleCode': staleCode,
      'removed': !(await listNativeScrcpyServers()).any(
        (entry) => entry.serverId == before.serverId,
      ),
    };
  } finally {
    await host.close();
  }
}

Future<Map<String, Object?>> _facts(ScrcpyNativeHost host) async {
  final configuration = host.nativeConfiguration!;
  final entry = (await listNativeScrcpyServers()).singleWhere(
    (entry) => entry.leaseId == configuration['leaseId'],
  );
  final identity = File(configuration['identityPath'] as String);
  return {
    ...configuration,
    'pid': entry.pid,
    'bytes': await identity.readAsBytes(),
    'modified': (await identity.lastModified()).microsecondsSinceEpoch,
  };
}
