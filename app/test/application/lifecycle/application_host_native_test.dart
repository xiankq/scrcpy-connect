import 'dart:io';
import 'dart:isolate';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/stores/application_host.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/models/connection_policy.dart';
import 'package:scrcpy_connect/services/platform/bundled_servers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('应用宿主使用真实同库 SDK 身份和精确 Child 登记，策略只保留在 Dart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'application-host-native-',
    );
    ApplicationHost? current;
    addTearDown(() async {
      await current?.close();
      await ApplicationHost.closeRetiredHosts();
      await directory.delete(recursive: true);
    });
    final binary = Platform.environment['INTEROP_OFFICIAL_ADB_BINARY'];
    final binaryDirectory = binary == null ? null : File(binary).parent;
    const policy = ConnectionPolicy(
      requestAuthorization: false,
      healthEnabled: false,
      reconnectEnabled: false,
      tcp: AdbTcpOptions(keepalive: null, userTimeout: null),
    );
    final host = current = await ApplicationHost.attach(
      dataDirectory: directory.path,
      connectionPolicy: policy,
      adbBinaryDirectory: binaryDirectory,
    );
    expect(host.fileScopeId, isNotEmpty);
    expect(
      host.helperArtifacts.keys,
      containsAll(['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86']),
    );
    await host.preferences.update({'maxFps': 30, 'appearance': 'dark'});
    expect(
      await ApplicationHost.attach(
        dataDirectory: directory.path,
        connectionPolicy: policy,
      ),
      same(host),
    );
    expect(host.preferences.current.values['appearance'], 'dark');
    final path = p.join(
      await directory.resolveSymbolicLinks(),
      'selected-key.pem',
    );
    await host.identities.prepareIdentity(path);
    final fingerprint = (await host.identities.inspectIdentity(path))!
        .fingerprint;
    final client = await host.clientForIdentity(
      identityPath: path,
      fingerprint: fingerprint,
    );
    expect(await client.devices(), isA<List<AdbDevice>>());
    final servers = await (host.bindings as NativeAdbServerApi).listServers();
    final own = servers
        .where((server) => server.launch.environment['ADB_VENDOR_KEYS'] == path)
        .single;
    expect(own.pid, greaterThan(0));
    await expectLater(
      ApplicationHost.attach(dataDirectory: directory.path),
      throwsA(
        isA<ApplicationCommandException>().having(
          (error) => error.code,
          'code',
          'runtime_connection_policy_mismatch',
        ),
      ),
    );
    final stillOwned =
        (await (host.bindings as NativeAdbServerApi).listServers()).singleWhere(
          (server) => server.serverId == own.serverId,
        );
    expect(stillOwned.pid, own.pid);
    expect(stillOwned.leaseId, own.leaseId);
    await host.close();
    expect(
      (await (host.bindings as NativeAdbServerApi).listServers()).any(
        (server) => server.serverId == own.serverId,
      ),
      isFalse,
    );
    current = await ApplicationHost.attach(
      dataDirectory: directory.path,
      connectionPolicy: const ConnectionPolicy(
        tcp: AdbTcpOptions(keepalive: null, userTimeout: null),
      ),
      adbBinaryDirectory: binaryDirectory,
    );
    expect(
      current.connectionPolicy.requestAuthorization,
      isTrue,
      reason: '原资源已实际关闭后，冷宿主可以选择新的产品策略',
    );
  }, skip: !(Platform.isLinux || Platform.isMacOS || Platform.isWindows));
  test('原 isolate 退出后从同库真实登记恢复同 Child，旧 lease 关闭不伤后继', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'application-host-isolate-',
    );
    final path = await temporary.resolveSymbolicLinks();
    final directory = Directory(path);
    final assets = await BundledServers().prepare(directory);
    // 此根 isolate 保持库 watcher 存活；本例不声称覆盖 FRB 零存活 isolate 的上游窗口。
    final api = await createNativeScrcpyAdbApi();
    final serverApi = api as NativeAdbServerApi;
    final binary = Platform.environment['INTEROP_OFFICIAL_ADB_BINARY'];
    final binaryDirectory = binary == null ? null : File(binary).parent.path;
    ApplicationHost? recovered;
    addTearDown(() async {
      await recovered?.close();
      await ApplicationHost.closeRetiredHosts();
      await directory.delete(recursive: true);
    });
    final old = await Isolate.run(() async {
      final host = await ApplicationHost.attach(
        dataDirectory: path,
        connectionPolicy: _restorationPolicy,
        adbBinaryDirectory: binaryDirectory == null
            ? null
            : Directory(binaryDirectory),
        dependencies: _VerifiedAssets(assets),
      );
      final key = p.join(path, 'isolate-key.pem');
      await host.identities.prepareIdentity(key);
      final fingerprint = (await host.identities.inspectIdentity(key))!
          .fingerprint;
      await (await host.clientForIdentity(
        identityPath: key,
        fingerprint: fingerprint,
      )).devices();
      final server = (await (host.bindings as NativeAdbServerApi).listServers())
          .singleWhere(
            (server) => server.launch.environment['ADB_VENDOR_KEYS'] == key,
          );
      return (
        id: server.serverId,
        lease: server.leaseId,
        pid: server.pid,
        key: key,
        fingerprint: fingerprint,
        bytes: await File(key).readAsBytes(),
        modified: (await File(key).stat()).modified.microsecondsSinceEpoch,
      );
    });
    recovered = await ApplicationHost.attach(
      dataDirectory: path,
      connectionPolicy: _restorationPolicy,
      adbBinaryDirectory: binaryDirectory == null
          ? null
          : Directory(binaryDirectory),
    );
    final server = (await serverApi.listServers()).singleWhere(
      (server) => server.serverId == old.id,
    );
    expect(server.pid, old.pid);
    expect(server.leaseId, isNot(old.lease));
    expect(await File(old.key).readAsBytes(), old.bytes);
    expect(
      (await File(old.key).stat()).modified.microsecondsSinceEpoch,
      old.modified,
    );
    await serverApi.closeServer(old.lease);
    final client = await recovered.clientForIdentity(
      identityPath: old.key,
      fingerprint: old.fingerprint,
    );
    expect(await client.devices(), isA<List<AdbDevice>>());
    await recovered.close();
    expect(
      (await serverApi.listServers()).any(
        (server) => server.serverId == old.id,
      ),
      isFalse,
    );
  }, skip: !(Platform.isLinux || Platform.isMacOS || Platform.isWindows));
}

const _restorationPolicy = ConnectionPolicy(
  tcp: AdbTcpOptions(keepalive: null, userTimeout: null),
);

class _VerifiedAssets extends ApplicationHostDependencies {
  const _VerifiedAssets(this.files);
  final BundledServerFiles files;
  @override
  Future<BundledServerFiles> assets(Directory directory) async => files;
}
