import 'package:scrcpy_connect/models/device_connection.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/models/connection_policy.dart';
import 'package:scrcpy_connect/services/device_capability_facts_reader.dart';
import 'package:scrcpy_connect/services/device_capability_policy.dart';
import 'package:scrcpy_connect/services/adb_identity_service.dart';
import 'package:scrcpy_connect/stores/device_store.dart';

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.open());
  tearDown(() => fixture.close());

  test('离线只读本机身份，缓存在线与旧活动不能启动探测或证明功能可用', () async {
    await fixture.update((record) => record.copyWith(status: 'connected'));
    fixture.current = null;
    fixture.sessions = [
      {'deviceId': fixture.id, 'status': 'streaming'},
    ];
    fixture.audio = [
      {'deviceId': fixture.id, 'status': 'playing', 'nativeAttached': true},
    ];
    fixture.companion = {
      'calls': {'status': 'available'},
    };
    final disk = await fixture.records.file.readAsString();
    final prepares = fixture.identityApi.prepares;
    final result = await fixture.request('device.capabilities');
    for (final name in [
      'shell',
      'files',
      'screen',
      'audio',
      'notifications',
      'calls',
      'wirelessPairing',
    ]) {
      expect(_entry(result, name)['status'], 'unknown', reason: name);
    }
    expect(fixture.client.commands, isEmpty);
    expect(fixture.client.native.factReads, 0);
    expect(fixture.client.native.syncRequests, isEmpty);
    expect(fixture.tcpQueries, 0);
    expect(fixture.identityApi.prepares, prepares);
    expect(await fixture.records.file.readAsString(), disk);
  });

  test('公开 shell 与 SYNC 读事实，版本门槛、实际画面和播放分别判断', () async {
    await fixture.update((record) => record.copyWith(apiLevel: 29));
    final result = await fixture.request('device.capabilities');
    expect(_entry(result, 'shell')['status'], 'available');
    expect(_entry(result, 'files')['status'], 'available');
    expect(_entry(result, 'apps')['status'], 'available');
    expect(_entry(result, 'screen')['status'], 'limited');
    expect(_entry(result, 'audio')['status'], 'unavailable');
    expect(result['connectionId'], 'physical-1');
    expect(result['features'], ['shell_v2', 'stat_v2']);
    expect(fixture.client.commands, [
      DeviceCapabilityFactsReader.shellCommand,
      DeviceCapabilityFactsReader.packagesCommand,
    ]);
    expect(fixture.client.timeouts, everyElement(_budget));
    expect(fixture.client.native.syncRequests.single.kind, AdbSyncKind.stat);
    expect(
      utf8.decode(fixture.client.native.syncRequests.single.path),
      '/sdcard',
    );
    expect(fixture.client.native.syncTimeouts, [_budget.inMilliseconds]);
    expect(fixture.client.native.cancelled, ['sync-1']);
    await fixture.update((record) => record.copyWith(apiLevel: 36));
    fixture.sessions = [
      {'deviceId': fixture.id, 'status': 'streaming'},
    ];
    fixture.audio = [
      {'deviceId': fixture.id, 'status': 'playing', 'nativeAttached': false},
    ];
    final unattached = await fixture.request('device.capabilities');
    expect(_entry(unattached, 'screen')['status'], 'available');
    expect(_entry(unattached, 'audio')['status'], 'unknown');
    fixture.audio.single['nativeAttached'] = true;
    expect(
      _entry(await fixture.request('device.capabilities'), 'audio')['status'],
      'available',
    );
  });

  test('缺失身份不自动生成，网络权限失败不冒充地址不通或已授权', () async {
    fixture.current = null;
    await fixture.update((record) => record.copyWith(status: 'unauthorized'));
    final key = File.fromUri(
      fixture.directory.uri.resolve('host_identity.pem'),
    );
    await key.delete();
    final prepares = fixture.identityApi.prepares;
    fixture.tcp = (_, _, _) async =>
        throw const SocketException('权限未允许', osError: OSError('denied', 13));
    final result = await fixture.request('device.diagnose');
    expect(result['identityPresent'], isFalse);
    expect(result['identityError'], 'identity_unavailable');
    expect(result['tcpReachable'], isNull);
    expect(result['networkError'], 'permission_denied');
    expect(result['connected'], isFalse);
    expect((result['device'] as Map)['status'], 'unauthorized');
    expect(result['adbBurstRequested'], isTrue);
    expect((result['notes'] as List).join(), contains('主控网络权限'));
    expect(await key.exists(), isFalse);
    expect(fixture.identityApi.prepares, prepares);
    expect(fixture.client.commands, isEmpty);
  });

  test('真实本机 TCP 可达只证明端口，不建立 ADB、授权或配对连接', () async {
    fixture.current = null;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final received = <int>[];
    final peerClosed = Completer<void>();
    final readers = <StreamSubscription<List<int>>>[];
    final accepting = server.listen((socket) {
      sockets.add(socket);
      readers.add(
        socket.listen(
          received.addAll,
          onDone: () {
            if (!peerClosed.isCompleted) peerClosed.complete();
          },
        ),
      );
    });
    addTearDown(() async {
      await accepting.cancel();
      await server.close();
      for (final socket in sockets) {
        socket.destroy();
      }
      for (final reader in readers) {
        await reader.cancel();
      }
    });
    await fixture.update(
      (record) => record.copyWith(
        address: '127.0.0.1',
        port: server.port,
        status: 'unauthorized',
      ),
    );
    final result = await fixture.request('device.diagnose');
    expect(result['tcpReachable'], isTrue);
    expect(result['connected'], isFalse);
    expect(result['identityPresent'], isTrue);
    await peerClosed.future.timeout(const Duration(seconds: 5));
    expect(sockets, hasLength(1));
    expect(received, isEmpty);
    expect(fixture.client.commands, isEmpty);
    expect(fixture.client.native.factReads, 0);
  });

  test('各探测独立保留真实失败，不把包列表或文件权限失败认定为不支持', () async {
    fixture.client.errors[DeviceCapabilityFactsReader.shellCommand] =
        const AdbException('handshake_timeout', 'shell deadline');
    fixture.client.errors[DeviceCapabilityFactsReader.packagesCommand] =
        const AdbException('permission_denied', 'package access denied');
    fixture.client.native.syncFailure = const AdbException(
      'permission_denied',
      'stat access denied',
    );
    final facts = await fixture.reader().read(fixture.id, diagnose: false);
    expect(facts.observation('shell').code, 'handshake_timeout');
    expect(facts.observation('sync').code, 'permission_denied');
    expect(facts.observation('packages').code, 'permission_denied');
    final result = await fixture.request('device.capabilities');
    for (final feature in ['shell', 'files', 'apps']) {
      expect(_entry(result, feature)['status'], 'limited');
    }
  });

  test('无线诊断只读固定属性，查询失败仍保留网络和身份事实', () async {
    fixture.tcp = (_, _, _) async => throw TimeoutException('tcp budget');
    fixture.client.errors[DeviceCapabilityFactsReader.wirelessCommand] =
        const AdbException('query_unavailable', 'getprop failed');
    final result = await fixture.request('device.diagnose');
    expect(result['tcpReachable'], isFalse);
    expect(result['networkError'], 'connect_timeout');
    expect(result['identityPresent'], isTrue);
    expect((result['observations'] as Map)['wirelessProperties'], {
      'status': 'error',
      'code': 'query_unavailable',
      'message': 'getprop failed',
    });
    expect(fixture.client.commands, [
      DeviceCapabilityFactsReader.wirelessCommand,
    ]);
    expect(fixture.client.native.syncRequests, isEmpty);
  });

  test('USB 离线诊断不尝试缓存 IP 或创建 SDK 客户端', () async {
    fixture.current = null;
    await fixture.update(
      (record) => record.copyWith(transport: DeviceTransport.usb),
    );
    fixture.tcp = (_, _, _) async => throw StateError('不应执行 TCP');
    final result = await fixture.request('device.diagnose');
    expect(result['tcpReachable'], isNull);
    expect(result['usbBackendAvailable'], isNull);
    expect(fixture.tcpQueries, 0);
    expect(fixture.client.commands, isEmpty);
    expect(fixture.client.native.factReads, 0);
  });

  test('等待远端回执时连接被替换，拒绝迟到事实且不启动后续组', () async {
    final entered = Completer<void>(), release = Completer<void>();
    fixture.client.reply = (_) async* {
      entered.complete();
      await release.future;
      throw const AdbException('handshake_timeout', 'old connection');
    };
    final result = expectLater(
      fixture.request('device.capabilities'),
      _failure('stale_connection'),
    );
    await entered.future;
    fixture.current = DeviceConnection(client: fixture.client, device: _device);
    release.complete();
    await result;
    expect(fixture.client.commands, hasLength(1));
    expect(fixture.client.native.syncRequests, isEmpty);
  });

  test('同一 Dart 连接下的实际物理连接身份变化也拒绝旧查询', () async {
    fixture.client.reply = (command) async* {
      fixture.client.native.physicalId = 'physical-2';
      yield* _output(fixture.client.responses[command]!);
    };
    await expectLater(
      fixture.request('device.capabilities'),
      _failure('stale_connection'),
    );
  });

  for (final change in ['endpoint', 'identity', 'remove']) {
    test('等待期间改变 $change 会撤销本次事实', () async {
      final entered = Completer<void>(), release = Completer<void>();
      fixture.client.reply = (command) async* {
        entered.complete();
        await release.future;
        yield* _output(fixture.client.responses[command]!);
      };
      final result = expectLater(
        fixture.request('device.capabilities'),
        _failure('stale_connection'),
      );
      await entered.future;
      switch (change) {
        case 'endpoint':
          await fixture.update((record) => record.copyWith(port: 5556));
        case 'identity':
          await fixture.records.bindIdentity(fixture.id, 'b' * 64);
        case 'remove':
          await fixture.records.remove(fixture.id);
      }
      release.complete();
      await result;
      expect(fixture.client.commands, hasLength(1));
    });
  }

  test('本机视频能力等待期间磁盘私钥改变，不把旧授权身份当作仍有效', () async {
    final policy = fixture.explain(
      video: () async {
        await File.fromUri(fixture.directory.uri.resolve('host_identity.pem'))
            .writeAsString('changed-key');
        return {};
      },
    );
    await expectLater(
      policy.request('device.capabilities', {'deviceId': fixture.id}),
      _failure('identity_changed'),
    );
  });

  test('取消等待真实读取收尾，不把取消归入某个能力受限', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final stop = AdbCancellation();
    fixture.client.reply = (command) async* {
      entered.complete();
      await release.future;
      yield* _output(fixture.client.responses[command]!);
    };
    final result = expectLater(
      fixture.reader().read(fixture.id, diagnose: false, cancellation: stop),
      throwsA(
        isA<AdbException>().having((error) => error.code, 'code', 'cancelled'),
      ),
    );
    await entered.future;
    stop.cancel();
    release.complete();
    await result;
    expect(fixture.client.finished, [DeviceCapabilityFactsReader.shellCommand]);
    expect(fixture.client.native.syncRequests, isEmpty);
  });
}

const _budget = Duration(milliseconds: 731);
const _device = AdbDevice(
  id: 'exact-handle',
  serial: 'selector',
  state: 'device',
);

Json _entry(Json result, String id) => (result['capabilities'] as List)
    .cast<Json>()
    .singleWhere((item) => item['id'] == id);
Matcher _failure(String code) =>
    throwsA(isA<RequestFailure>().having((error) => error.code, 'code', code));

final class _Fixture {
  _Fixture(this.directory);
  final Directory directory;
  late DeviceStore records;
  late AdbIdentityService identities;
  final identityApi = _Identities();
  final client = _Client();
  late String id;
  DeviceConnection? current;
  List<Map<String, Object?>> sessions = [], audio = [];
  Map<String, Object?> companion = {};
  Future<Socket> Function(String, int, Duration)? tcp;
  int tcpQueries = 0;

  static Future<_Fixture> open() async {
    final fixture = _Fixture(
      await Directory.systemTemp.createTemp('capability-facts-'),
    );
    fixture.records = await DeviceStore.open(directory: fixture.directory);
    fixture.identities = await AdbIdentityService.open(
      directory: fixture.directory,
      records: fixture.records,
      identities: fixture.identityApi,
      invalidate: (_, {required global}) async {},
    );
    fixture.id = (await fixture.records.add(
      address: '192.0.2.7',
      port: 5555,
    )).id;
    fixture.current = DeviceConnection(client: fixture.client, device: _device);
    return fixture;
  }

  Future<void> update(DeviceRecord Function(DeviceRecord) change) async {
    await records.update(id, change);
  }

  DeviceCapabilityFactsReader reader() => DeviceCapabilityFactsReader(
    records: records,
    identities: identities,
    connectionForDevice: (device) => device == id ? current : null,
    policy: const ConnectionPolicy(probeTimeout: _budget),
    companionState: (_) => companion,
    sessions: () => sessions,
    audioSources: () => audio,
    openTcp: (address, port, timeout) {
      tcpQueries++;
      expect(timeout, _budget);
      return tcp?.call(address, port, timeout) ??
          Socket.connect(address, port, timeout: timeout);
    },
  );
  DeviceCapabilityPolicy explain({Future<Json> Function()? video}) =>
      DeviceCapabilityPolicy(
        facts: reader(),
        burstRequested: () => true,
        localVideoCapabilities: video,
      );
  Future<Json> request(String command) =>
      explain().request(command, {'deviceId': id});
  Future<void> close() async {
    await client.services.close();
    await directory.delete(recursive: true);
  }
}

Stream<AdbShellEvent> _output(String text) async* {
  yield AdbShellEvent(
    AdbShellChannel.stdout,
    Uint8List.fromList(utf8.encode(text)),
  );
  yield AdbShellEvent(AdbShellChannel.exit, Uint8List(0), exitCode: 0);
}

final class _Client implements AdbClient {
  final commands = <String>[], finished = <String>[];
  final timeouts = <Duration>[];
  final errors = <String, Object>{};
  final responses = {
    DeviceCapabilityFactsReader.shellCommand: 'interop-capability-check',
    DeviceCapabilityFactsReader.packagesCommand: 'package:android\n',
    DeviceCapabilityFactsReader.wirelessCommand: 'service.adb.tcp.port=5555\n',
  };
  Stream<AdbShellEvent> Function(String)? reply;
  late final native = _Native();
  @override
  late final services = AdbServices(
    () => native,
    (device) async => device,
    () {},
  );
  @override
  AdbCapabilities get capabilities => const AdbCapabilities(
    officialServer: false,
    suppressAuthorizationPrompt: true,
    forceTlsWithoutMdns: true,
    androidUsbFd: true,
  );
  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) async* {
    commands.add(command);
    timeouts.add(timeout);
    try {
      if (errors[command] case final error?) throw error;
      if (reply case final handler?) {
        yield* handler(command);
      } else {
        final output =
            responses[command] ?? (throw StateError('意外远端命令：$command'));
        yield* _output(output);
      }
    } finally {
      finished.add(command);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Native implements NativeAdbApi {
  final syncRequests = <AdbSyncRequest>[];
  final syncTimeouts = <int>[];
  final cancelled = <String>[];
  final stages = <String, int>{};
  String? physicalId = 'physical-1';
  int factReads = 0;
  Object? syncFailure;
  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async {
    expect(id, _device.id);
    factReads++;
    return AdbConnectionFacts(
      officialServer: false,
      closed: false,
      features: const ['shell_v2', 'stat_v2'],
      connectionId: physicalId,
    );
  }

  @override
  Future<String> sync(String id, AdbSyncRequest request, int timeoutMs) async {
    expect(id, _device.id);
    syncRequests.add(request);
    syncTimeouts.add(timeoutMs);
    if (syncFailure case final error?) throw error;
    final operation = 'sync-${syncRequests.length}';
    stages[operation] = 0;
    return operation;
  }

  @override
  Future<NativeAdbEvent?> next(String id) async {
    final stage = stages[id]!;
    stages[id] = stage + 1;
    return NativeAdbEvent(
      kind: stage == 0 ? 'stat' : 'sync',
      bytes: Uint8List(0),
      done: stage != 0,
      facts: stage == 0
          ? const AdbServiceFacts(metadata: AdbFileMetadata(0x4000, 0, 1))
          : null,
    );
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    stages.remove(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Identities implements AdbIdentities {
  int prepares = 0;
  AdbIdentityInfo info(String text) => AdbIdentityInfo(
    fingerprint: (text == 'test-key' ? 'a' : 'b') * 64,
    fingerprintAlgorithm: 'sha256',
    fingerprintInput: 'adb-public-key-interop-v1',
    bits: 2048,
    exponent: 65537,
  );
  @override
  Future<void> prepareIdentity(String path) async {
    prepares++;
    if (!await File(path).exists()) await File(path).writeAsString('test-key');
  }

  @override
  Future<AdbIdentityInfo?> inspectIdentity(String path) async =>
      await File(path).exists() ? info(await File(path).readAsString()) : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
