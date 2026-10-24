import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('真实 FRB scope 接管比较旧权限，旧关闭不影响后继与其他 scope', () async {
    final api = await createNativeAdbApi() as NativeAdbAdmissionApi;
    final first = await api.attachAdmissionScope('scope-cas');
    addTearDown(() => api.closeAdmissionScope(first.scopeId));
    final other = await api.attachAdmissionScope('scope-independent');
    addTearDown(() => api.closeAdmissionScope(other.scopeId));
    await expectLater(
      api.attachAdmissionScope(first.scopeKey),
      throwsA(isA<AdbException>()),
    );
    final next = await api.attachAdmissionScope(
      first.scopeKey,
      expectedScopeId: first.scopeId,
    );
    addTearDown(() => api.closeAdmissionScope(next.scopeId));
    expect(next.scopeId, isNot(first.scopeId));
    await api.closeAdmissionScope(first.scopeId);
    expect((await api.inspectAdmissionScope(next.scopeKey))!.accepting, isTrue);
    expect(
      (await api.inspectAdmissionScope(other.scopeKey))!.scopeId,
      other.scopeId,
    );
    await expectLater(
      api.createScopedHandshake(first.scopeId),
      throwsA(isA<AdbException>()),
    );
    await expectLater(
      api.attachAdmissionScope(first.scopeKey, expectedScopeId: first.scopeId),
      throwsA(isA<AdbException>()),
    );
    expect(
      (await api.inspectAdmissionScope(next.scopeKey))!.scopeId,
      next.scopeId,
    );
  });

  test('真实 FRB 移动准入 scope 不能绕过官方服务器的握手所有权', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final accepting = server.listen(sockets.add);
    addTearDown(() async {
      await accepting.cancel();
      await server.close();
      for (final socket in sockets) {
        socket.destroy();
      }
    });
    final bindings = await createNativeAdbApi();
    final api = bindings as NativeAdbAdmissionApi;
    final scope = await api.attachAdmissionScope('scope-direct-only');
    addTearDown(() => api.closeAdmissionScope(scope.scopeId));
    final handshake = await api.createScopedHandshake(scope.scopeId);
    await expectLater(
      bindings.connectServer(
        '127.0.0.1:${server.port}',
        'scope-rejected',
        5000,
        handshakeId: handshake,
      ),
      throwsA(
        isA<AdbException>().having(
          (error) => error.message,
          'message',
          contains('adb_scoped_handshake_direct_only'),
        ),
      ),
    );
    expect(sockets, isEmpty);
    await (bindings as NativeAdbHandshakeApi).closeHandshake(handshake);
  });

  test('真实 FRB 文件域归属当前准入，旧交接和关闭均不撤销后继', () async {
    final fixture = await _SmartSocket.open();
    addTearDown(fixture.close);
    final directory = await Directory.systemTemp.createTemp('scoped-file-frb-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/source').writeAsString('facts');
    final bindings = await createNativeAdbApi();
    final api = bindings as NativeAdbAdmissionApi;
    final scopes = bindings as NativeAdbScopedFileScopeApi;
    final files = bindings as NativeAdbFileApi;
    final device = await bindings.connectServer(
      fixture.endpoint,
      'scope-files',
      5000,
    );
    addTearDown(() => bindings.disconnect(device.id));
    final first = await api.attachAdmissionScope('scope-file-owner');
    addTearDown(() => api.closeAdmissionScope(first.scopeId));
    final oldFiles = await scopes.fileScopeAttachScoped(
      'scope-file-work',
      first.scopeId,
    );
    Future<void> stat(String scopeId) async {
      final operation = await files.fileExecute(
        device.id,
        AdbFileExecutionRequest(
          kind: AdbFileExecutionKind.stat,
          path: utf8.encode(file.path),
          local: true,
          scopeId: scopeId,
        ),
        5000,
      );
      try {
        final result = await files.fileNext(operation);
        expect(result?.kind, 'stat');
        expect(result?.stamp?.size, 5);
        expect((await files.fileNext(operation))?.kind, 'done');
      } finally {
        await files.fileCancel(operation);
      }
    }

    await stat(oldFiles);
    final next = await api.attachAdmissionScope(
      first.scopeKey,
      expectedScopeId: first.scopeId,
    );
    addTearDown(() => api.closeAdmissionScope(next.scopeId));
    await expectLater(stat(oldFiles), throwsA(isA<AdbException>()));
    final currentFiles = await scopes.fileScopeAttachScoped(
      'scope-file-work',
      next.scopeId,
    );
    await expectLater(
      scopes.fileScopeAttachScoped('scope-file-work', first.scopeId),
      throwsA(isA<AdbException>()),
    );
    await scopes.fileScopeClose(oldFiles);
    await api.closeAdmissionScope(first.scopeId);
    await stat(currentFiles);
    await api.closeAdmissionScope(next.scopeId);
    await expectLater(stat(currentFiles), throwsA(isA<AdbException>()));
  });

  test('真实 FRB scope 接管只清理未交付结果，确认的 Client 可按原身份认领', () async {
    final fixture = await _SmartSocket.open();
    addTearDown(fixture.close);
    final bindings = await createNativeAdbApi();
    final api = bindings as NativeAdbAdmissionApi;
    final handshakes = bindings as NativeAdbHandshakeApi;
    final first = await api.attachAdmissionScope('scope-results');
    addTearDown(() => api.closeAdmissionScope(first.scopeId));
    Future<(String, AdbDevice)> connect(String serial) async {
      final original = await bindings.connectServer(
        fixture.endpoint,
        serial,
        5000,
      );
      addTearDown(() => bindings.disconnect(original.id));
      final handshake = await api.createScopedHandshake(first.scopeId);
      final claimed = await api.claimScopedConnection(original.id, handshake);
      addTearDown(() => bindings.disconnect(claimed.id));
      return (handshake, claimed);
    }

    final (pendingHandshake, pending) = await connect('scope-pending');
    final (deliveredHandshake, delivered) = await connect('scope-delivered');
    await api.confirmHandshakeConnection(deliveredHandshake, delivered.id);
    await handshakes.closeHandshake(deliveredHandshake);
    final before = await bindings.connectionFacts(delivered.id);
    expect(before.admissionScopeKey, first.scopeKey);
    final next = await api.attachAdmissionScope(
      first.scopeKey,
      expectedScopeId: first.scopeId,
    );
    final successor = NativeAdbClient(
      bindings,
      '/unused-identity',
      admissionScope: next,
    );
    addTearDown(successor.close);
    expect(
      (await bindings.devices()).any((device) => device.id == pending.id),
      isFalse,
    );
    expect(
      (await bindings.devices()).any((device) => device.id == delivered.id),
      isTrue,
    );
    await handshakes.closeHandshake(pendingHandshake);
    final claimed = await successor.claimConnection(delivered);
    expect(claimed.id, isNot(delivered.id));
    await bindings.disconnect(delivered.id);
    final after = await successor.services.connectionFacts(claimed);
    expect(after.connectionId, before.connectionId);
    expect(after.admissionScopeKey, next.scopeKey);
    expect(after.closed, isFalse);
    await successor.close();
    expect(await api.inspectAdmissionScope(first.scopeKey), isNull);
  });
}

/// 仅实现连接选择与特性查询，不准备密钥或启动系统 adb-server。
final class _SmartSocket {
  _SmartSocket(this.server);
  final ServerSocket server;
  final sockets = <Socket>[];
  final tasks = <Future<void>>[];
  late StreamSubscription<Socket> accepting;
  int transportId = 40;
  String get endpoint => '127.0.0.1:${server.port}';

  static Future<_SmartSocket> open() async {
    final fixture = _SmartSocket(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.accepting = fixture.server.listen((socket) {
      fixture.sockets.add(socket);
      fixture.tasks.add(fixture.respond(socket));
    });
    return fixture;
  }

  Future<void> respond(Socket socket) async {
    final reader = StreamIterator<Uint8List>(socket);
    final bytes = <int>[];
    try {
      while (await reader.moveNext()) {
        bytes.addAll(reader.current);
        if (bytes.length < 4) continue;
        final count = int.parse(
          ascii.decode(bytes.take(4).toList()),
          radix: 16,
        );
        if (bytes.length < 4 + count) continue;
        final service = ascii.decode(bytes.sublist(4, 4 + count));
        if (service.startsWith('host:tport:serial:scope-')) {
          final id = ByteData(8)..setUint64(0, transportId++, Endian.little);
          socket.add([...ascii.encode('OKAY'), ...id.buffer.asUint8List()]);
        } else {
          expect(service, matches(r'^host-transport-id:\d+:features$'));
          socket.add(ascii.encode('OKAY0000'));
        }
        await socket.flush();
        return;
      }
      throw StateError('连接选择命令提前结束。');
    } finally {
      await reader.cancel();
      socket.destroy();
    }
  }

  Future<void> close() async {
    await accepting.cancel();
    await server.close();
    for (final socket in sockets) {
      socket.destroy();
    }
    await Future.wait(tasks);
  }
}
