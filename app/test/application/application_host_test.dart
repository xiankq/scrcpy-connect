import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/application/lifecycle/application_host.dart';
import 'package:scrcpy_connect/application/lifecycle/application_host_record.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/platform/native/bundled_servers.dart';

void main() {
  test('临时释放失败也可由宿主关闭重试同一个 owner', () async {
    final fixture = await _Fixture.open();
    final path = fixture.identity('candidate.pem');
    await fixture.client(path);
    final owner = fixture.dependencies.owners.single;
    owner.closeFailures = 1;
    await expectLater(fixture.release(path), throwsStateError);
    await fixture.host.close();
    expect(owner.closeAttempts, 2);
    expect(owner.closed, isTrue);
    expect(fixture.api.scope, isNull);
    expect(fixture.dependencies.owners, hasLength(1));
  });

  test('候选关闭首败保留同对象，重试成功才移除记录；同指纹其他路径不受影响', () async {
    final fixture = await _Fixture.open();
    final candidate = fixture.identity('candidate.pem');
    final permanent = fixture.identity('host_identity.pem');
    final client = await fixture.client(candidate);
    final permanentClient = await fixture.client(permanent);
    final owner = fixture.dependencies.owners.first;
    owner.closeFailures = 1;

    await expectLater(fixture.release(candidate), throwsStateError);
    expect(owner.closeAttempts, 1);
    expect(owner.closed, isFalse);
    expect(await fixture.recordedPaths(), contains(candidate));
    await expectLater(
      fixture.client(candidate),
      throwsA(
        isA<ApplicationCommandException>().having(
          (error) => error.code,
          'code',
          'application_host_cleanup_unconfirmed',
        ),
      ),
    );
    expect(fixture.dependencies.owners, hasLength(2));

    await fixture.release(candidate);
    expect(owner.closeAttempts, 2);
    expect(owner.closed, isTrue);
    expect(await fixture.recordedPaths(), [permanent]);
    expect(await fixture.client(permanent), same(permanentClient));
    expect(fixture.dependencies.owners[1].closeAttempts, 0);
    await fixture.release(candidate);
    expect(owner.closeAttempts, 2);
    expect(await fixture.client(candidate), isNot(same(client)));
    expect(fixture.dependencies.owners, hasLength(3));
  });

  test('释放排在迟到创建之后，确认同一个 owner 关闭后才完成', () async {
    final fixture = await _Fixture.open();
    final path = fixture.identity('candidate.pem');
    final preparing = Completer<_Owner>();
    fixture.dependencies.preparing = preparing;
    final creating = fixture.client(path);
    await fixture.dependencies.prepareStarted.future;
    var released = false;
    final releasing = fixture.release(path).then((_) => released = true);
    final owner = _Owner('late', closeGate: Completer<void>());
    preparing.complete(owner);
    await creating;
    await owner.closeStarted.future;
    expect(released, isFalse);
    expect(await fixture.recordedPaths(), [path]);
    owner.closeGate!.complete();
    await releasing;
    expect(owner.closeAttempts, 1);
    expect(owner.closed, isTrue);
    expect(await fixture.recordedPaths(), isEmpty);
  });

  test('关闭成功但记录提交失败仍保留关闭责任，不能再次交付已关闭客户端', () async {
    final fixture = await _Fixture.open();
    final path = fixture.identity('candidate.pem');
    await fixture.client(path);
    final owner = fixture.dependencies.owners.single;
    final record = fixture.recordFile;
    final original = await record.readAsBytes();
    await record.delete();
    await Directory(record.path).create();

    await expectLater(
      fixture.release(path),
      throwsA(isA<FileSystemException>()),
    );
    expect(owner.closed, isTrue);
    expect(owner.closeAttempts, 1);
    await expectLater(
      fixture.client(path),
      throwsA(isA<ApplicationCommandException>()),
    );
    expect(fixture.dependencies.owners, hasLength(1));

    await Directory(record.path).delete();
    await record.writeAsBytes(original, flush: true);
    await fixture.release(path);
    expect(owner.closeAttempts, 2);
    expect(await fixture.recordedPaths(), isEmpty);
  });

  test('错误指纹不关闭同路径其他代客户端，丢失宿主权限也不执行释放', () async {
    final fixture = await _Fixture.open();
    final path = fixture.identity('candidate.pem');
    final client = await fixture.client(path);
    final owner = fixture.dependencies.owners.single;
    await fixture.host.releaseIdentityClient(
      identityPath: path,
      fingerprint: 'another-fingerprint',
    );
    expect(owner.closeAttempts, 0);
    expect(await fixture.client(path), same(client));

    final original = fixture.api.scope!;
    fixture.api.scope = AdbAdmissionScopeInfo(
      scopeKey: original.scopeKey,
      scopeId: 'successor',
      accepting: true,
    );
    await expectLater(
      fixture.release(path),
      throwsA(
        isA<ApplicationCommandException>().having(
          (error) => error.code,
          'code',
          'application_host_stale',
        ),
      ),
    );
    expect(owner.closeAttempts, 0);
    fixture.api.scope = original;
    expect(await fixture.recordedPaths(), [path]);
  });
}

class _Fixture {
  _Fixture(this.directory, this.api, this.dependencies, this.host);
  final Directory directory;
  final _Api api;
  final _Dependencies dependencies;
  final ApplicationHost host;
  static const fingerprint = 'same-key-fingerprint';

  static Future<_Fixture> open() async {
    final temporary = await Directory.systemTemp.createTemp('host-release-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    final api = _Api();
    final dependencies = _Dependencies(api);
    final host = await ApplicationHost.attach(
      dataDirectory: directory.path,
      dependencies: dependencies,
    );
    addTearDown(() async {
      await host.close();
      await directory.delete(recursive: true);
    });
    return _Fixture(directory, api, dependencies, host);
  }

  String identity(String name) {
    final path = p.join(directory.path, name);
    api.fingerprints[path] = fingerprint;
    return path;
  }

  Future<AdbClient> client(String path) =>
      host.clientForIdentity(identityPath: path, fingerprint: fingerprint);
  Future<void> release(String path) =>
      host.releaseIdentityClient(identityPath: path, fingerprint: fingerprint);
  Directory get records => Directory(p.join(directory.path, 'process_hosts'));
  File get recordFile =>
      File(p.join(records.path, 'host-${api.scope!.scopeId}.json'));
  Future<List<String>> recordedPaths() async => [
    for (final identity in (await ApplicationHostRecord.read(
      records,
      api.scope!.scopeId,
    )).identities.values)
      identity.identityPath,
  ];
}

class _Dependencies extends ApplicationHostDependencies {
  _Dependencies(this.api);
  final _Api api;
  final owners = <_Owner>[];
  final prepareStarted = Completer<void>();
  Completer<_Owner>? preparing;
  @override
  bool get desktop => true;
  @override
  Future<NativeAdbApi> bindings() async => api;
  @override
  Future<BundledServerFiles> assets(Directory directory) =>
      BundledServers(bundle: _Bundle()).prepare(directory);
  @override
  Future<ScrcpyClient> createScrcpy(Uint8List bytes) async =>
      ScrcpyClient(_Scrcpy(), nativeOwner: api);
  @override
  Future<AdbHost> prepareServer({
    required Directory directory,
    required String identityPath,
    required NativeAdbApi bindings,
    required AdbAdmissionScopeInfo admissionScope,
    Directory? binaryDirectory,
  }) async {
    if (!prepareStarted.isCompleted) prepareStarted.complete();
    final owner =
        await (preparing?.future ??
            Future.value(_Owner('server-${owners.length}')));
    owners.add(owner);
    return owner;
  }
}

class _Owner implements AdbHost {
  _Owner(this.id, {this.closeGate});
  final String id;
  final Completer<void>? closeGate;
  final closeStarted = Completer<void>();
  int closeFailures = 0, closeAttempts = 0;
  bool closed = false;
  @override
  final AdbClient client = _Client();
  @override
  Map<String, Object?> get nativeConfiguration => {'serverId': id};
  @override
  Future<void> close() async {
    closeAttempts++;
    if (!closeStarted.isCompleted) closeStarted.complete();
    await closeGate?.future;
    if (closeFailures-- > 0) throw StateError('server cleanup unconfirmed');
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements AdbClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Scrcpy implements NativeScrcpyApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api
    implements
        NativeAdbApi,
        NativeAdbAdmissionApi,
        NativeAdbScopedFileScopeApi,
        NativeAdbServerApi,
        NativeAdbScopedServerApi,
        NativeAdbHandshakeApi,
        AdbIdentities {
  AdbAdmissionScopeInfo? scope;
  final fingerprints = <String, String>{};
  @override
  Future<AdbAdmissionScopeInfo?> inspectAdmissionScope(String key) async =>
      scope;
  @override
  Future<AdbAdmissionScopeInfo> attachAdmissionScope(
    String key, {
    String? expectedScopeId,
    int timeoutMs = 7000,
  }) async => scope = AdbAdmissionScopeInfo(
    scopeKey: key,
    scopeId: 'scope-1',
    accepting: true,
  );
  @override
  Future<void> closeAdmissionScope(String id, {int timeoutMs = 7000}) async {
    if (scope?.scopeId == id) scope = null;
  }

  @override
  Future<String> fileScopeAttachScoped(
    String key,
    String admissionScopeId,
  ) async => 'files';
  @override
  Future<void> fileScopeClose(String id) async {}
  @override
  Future<List<AdbServerInfo>> listServers() async => [];
  @override
  Future<AdbIdentityInfo?> inspectIdentity(String path) async {
    final fingerprint = fingerprints[path];
    return fingerprint == null
        ? null
        : AdbIdentityInfo(
            fingerprint: fingerprint,
            fingerprintAlgorithm: 'sha256',
            fingerprintInput: 'canonical',
            bits: 2048,
            exponent: 65537,
          );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bundle extends CachingAssetBundle {
  static final payload = Uint8List.fromList([1, 2, 3]);
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(
      key.endsWith('manifest.json')
          ? utf8.encode(
              jsonEncode({
                'version': 1,
                'artifacts': [
                  for (final id in [
                    'scrcpy',
                    'companion',
                    'arm64-v8a',
                    'armeabi-v7a',
                    'x86_64',
                    'x86',
                  ])
                    {
                      'id': id,
                      'file': '$id.zlib',
                      'size': payload.length,
                      'sha256': sha256.convert(payload).toString(),
                    },
                ],
              }),
            )
          : ZLibEncoder().convert(payload),
    ),
  );
}
