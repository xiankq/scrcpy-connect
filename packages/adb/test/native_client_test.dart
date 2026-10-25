import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

const device = AdbDevice(id: 'connection', serial: 'target', state: 'device');

void main() {
  test('共享准入域的借用客户端只关闭自身资源，另一身份仍可发起连接', () async {
    final api = _ScopedApi();
    final scope = api.current!;
    final first = NativeAdbClient(
      api,
      '/first',
      admissionScope: scope,
      ownsAdmissionScope: false,
    );
    final second = NativeAdbClient(
      api,
      '/second',
      admissionScope: scope,
      ownsAdmissionScope: false,
    );
    await first.close();
    expect(api.scopeClosed, isEmpty);
    expect(api.current?.scopeId, scope.scopeId);
    expect((await second.connect('target')).id, 'handshake-1');
    await second.close();
    expect(api.scopeClosed, isEmpty);
    expect(api.disconnected, ['handshake-1']);
    await api.closeAdmissionScope(scope.scopeId);
    expect(api.current, isNull);
  });
  test('稳定准入域在迟到握手登记前关闭，既不启动连接也不丢回收责任', () async {
    final api = _ScopedApi()..creating = Completer<String>();
    final client = NativeAdbClient(api, '/owned', admissionScope: api.current);
    final rejected = expectLater(
      client.connect('target'),
      throwsA(_code('cancelled')),
    );
    var closed = false;
    final closing = client.close().then((_) => closed = true);
    await api.scopeClosing.future;
    expect(closed, isFalse);
    expect(api.opened, isEmpty);
    api.creating!.complete('late-reservation');
    await rejected;
    await closing;
    expect(api.closedHandshakes, ['late-reservation']);
    expect(api.current, isNull);
  });
  test('新准入域撤销旧连接结果，迟到句柄先登记再精确回收', () async {
    final api = _ScopedApi();
    final result = Completer<AdbDevice>();
    api.open = (_) => result.future;
    final old = api.current!;
    final client = NativeAdbClient(api, '/owned', admissionScope: old);
    final rejected = expectLater(
      client.connect('target'),
      throwsA(_code('adb_admission_scope_stale')),
    );
    await api.connectionStarted.future;
    final next = await api.attachAdmissionScope(
      old.scopeKey,
      expectedScopeId: old.scopeId,
    );
    result.complete(
      const AdbDevice(id: 'late-result', serial: 'target', state: 'device'),
    );
    await rejected;
    expect(api.disconnected, ['late-result']);
    await client.close();
    expect(api.current?.scopeId, next.scopeId, reason: '旧客户端关闭不能删除后继准入域');
  });
  test('确认连接后等待握手收尾时换代，交付前仍拒绝旧结果', () async {
    final api = _ScopedApi();
    final entered = Completer<void>(), release = Completer<void>();
    api.closeAction = (_) async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    final old = api.current!;
    final client = NativeAdbClient(api, '/owned', admissionScope: old);
    final rejected = expectLater(
      client.connect('target'),
      throwsA(_code('adb_admission_scope_stale')),
    );
    await entered.future;
    expect(api.confirmed, ['handshake-1']);
    await api.attachAdmissionScope(old.scopeKey, expectedScopeId: old.scopeId);
    release.complete();
    await rejected;
    expect(api.disconnected, ['handshake-1']);
    await client.close();
  });
  test('准入域关闭失败保留精确权限供重试，客户端始终拒绝新操作', () async {
    final api = _ScopedApi()..scopeCloseFailures = 1;
    final old = api.current!;
    final client = NativeAdbClient(api, '/owned', admissionScope: old);
    await expectLater(client.close(), throwsStateError);
    expect(api.current?.scopeId, old.scopeId);
    expect(api.current?.accepting, isFalse);
    expect(() => client.connect('new'), throwsA(_code('closed')));
    await client.close();
    expect(api.scopeClosed, [old.scopeId, old.scopeId]);
    expect(api.current, isNull);
  });
  test('同域认领使用受控握手并确认新操作句柄，不绕过准入', () async {
    final api = _ScopedApi();
    final client = NativeAdbClient(api, '/owned', admissionScope: api.current);
    final claimed = await client.claimConnection(device);
    expect(claimed.id, 'claimed-connection');
    expect(api.claims, [('connection', 'handshake-1')]);
    expect(api.confirmed, ['claimed-connection']);
    await client.close();
    expect(api.disconnected, ['claimed-connection']);
  });
  test('认领更换精确句柄但不重新连接，旧所有者关闭不伤及新所有者', () async {
    final api = _ClaimApi();
    final previous = NativeAdbClient(api, '/owned');
    final successor = NativeAdbClient(api, '/owned');
    final old = await previous.connect('target');
    final claimed = await successor.claimConnection(old);
    expect(claimed.id, isNot(old.id));
    expect(claimed.serial, old.serial);
    expect(identical(claimed.nativeOwner, successor.nativeOwner), isTrue);
    expect(api.connectCount, 1);
    await previous.close();
    expect(api.active, {claimed.id});
    await successor.shell(claimed, 'echo live').drain<void>();
    await successor.close();
    expect(api.active, isEmpty);
    expect(api.disconnected, [old.id, claimed.id]);
  });
  test('认领在调用原生前拒绝外来宿主、已关闭客户端和不支持的适配器', () async {
    final api = _ClaimApi();
    final client = NativeAdbClient(api, '/owned');
    expect(client, isA<AdbConnectionClaims>());
    expect(
      () => client.claimConnection(
        AdbDevice(
          id: 'foreign',
          serial: 'target',
          state: 'device',
          nativeOwner: Object(),
        ),
      ),
      throwsA(_code('foreign_native_host')),
    );
    expect(api.claimCount, 0);
    await client.close();
    expect(() => client.claimConnection(device), throwsA(_code('closed')));
    expect(api.claimCount, 0);
    final unsupported = NativeAdbClient(_Api(), '/owned');
    expect(
      () => unsupported.claimConnection(device),
      throwsA(_code('connection_claim_unavailable')),
    );
    await unsupported.close();
  });
  test('关闭等待迟到认领和新精确句柄的实际回收', () async {
    final api = _ClaimApi()
      ..claiming = Completer<AdbDevice>()
      ..disconnecting = Completer<void>();
    final client = NativeAdbClient(api, '/owned');
    var claimFinished = false, closeFinished = false;
    final rejected = expectLater(
      client.claimConnection(device).whenComplete(() {
        claimFinished = true;
      }),
      throwsA(_code('closed')),
    );
    final closing = client.close().then((_) {
      closeFinished = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closeFinished, isFalse);
    api.claiming!.complete(
      const AdbDevice(id: 'late-claim', serial: 'target', state: 'device'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(claimFinished, isFalse);
    expect(closeFinished, isFalse);
    expect(api.active, {'late-claim'});
    api.disconnecting!.complete();
    await rejected;
    await closing;
    expect(api.disconnected, ['late-claim']);
    expect(api.active, isEmpty);
  });
  test('迟到认领回收失败保留同一精确句柄供关闭重试且准入保持撤销', () async {
    final api = _ClaimApi()
      ..claiming = Completer<AdbDevice>()
      ..disconnectFailures = 2;
    final client = NativeAdbClient(api, '/owned');
    final rejected = expectLater(
      client.claimConnection(device),
      throwsStateError,
    );
    final failedClose = expectLater(client.close(), throwsStateError);
    api.claiming!.complete(
      const AdbDevice(id: 'retained-claim', serial: 'target', state: 'device'),
    );
    await rejected;
    await failedClose;
    expect(api.active, {'retained-claim'});
    expect(() => client.claimConnection(device), throwsA(_code('closed')));
    expect(api.claimCount, 1);
    await client.close();
    expect(api.active, isEmpty);
    expect(api.disconnected, List.filled(3, 'retained-claim'));
  });
  test('重复旧句柄认领失败不获得或回收已经交付的新所有者', () async {
    final api = _ClaimApi();
    final oldOwner = NativeAdbClient(api, '/owned');
    final newOwner = NativeAdbClient(api, '/owned');
    final old = await oldOwner.connect('target');
    final claimed = await newOwner.claimConnection(old);
    final failedOwner = NativeAdbClient(api, '/owned');
    await expectLater(
      failedOwner.claimConnection(old),
      throwsA(_code('stale_connection')),
    );
    await failedOwner.close();
    expect(api.disconnected, isEmpty);
    expect(api.active, {claimed.id});
    await oldOwner.close();
    expect(api.active, {claimed.id});
    await newOwner.close();
  });
  test('原生认领失败不会捏造清理句柄或影响原所有者', () async {
    final api = _ClaimApi()
      ..claimFailure = StateError('claim cleanup incomplete');
    final oldOwner = NativeAdbClient(api, '/owned');
    final newOwner = NativeAdbClient(api, '/owned');
    final old = await oldOwner.connect('target');
    await expectLater(newOwner.claimConnection(old), throwsStateError);
    await newOwner.close();
    expect(api.disconnected, isEmpty);
    expect(api.active, {old.id});
    await oldOwner.close();
  });
  test('预取消与非法期限均不登记握手或接触传输', () async {
    final api = _HandshakeApi();
    final client = NativeAdbClient(api, '/owned');
    final stop = AdbCancellation()..cancel();
    expect(
      () => client.connect('target', cancellation: stop),
      throwsA(_cancelled),
    );
    expect(
      () => client.pair('target', 'code', cancellation: stop),
      throwsA(_cancelled),
    );
    expect(
      () => client.connectUsbFd(1, 'usb', cancellation: stop),
      throwsA(_cancelled),
    );
    expect(
      () => client.connect('target', timeout: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => client.pair('target', 'code', timeout: Duration.zero),
      throwsArgumentError,
    );
    expect(api.created, 0);
    await client.close();
  });
  test('关闭等待迟到握手登记并撤销准入，不启动实际连接', () async {
    final api = _HandshakeApi()..creating = Completer<String>();
    final client = NativeAdbClient(api, '/owned');
    final opening = client.connect('target');
    final rejected = expectLater(opening, throwsA(_cancelled));
    var closed = false;
    final closing = client.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    api.creating!.complete('late-admission');
    await rejected;
    await closing;
    expect(api.opened, isEmpty);
    expect(api.cancelledHandshakes, ['late-admission']);
    expect(api.closedHandshakes, ['late-admission']);
  });
  test('TCP 与 USB 取消通知实际握手，返回前等待原 worker 排空', () async {
    for (final usb in [false, true]) {
      final api = _HandshakeApi();
      final started = Completer<void>(),
          cancelled = Completer<void>(),
          cleanup = Completer<void>();
      api.open = (id) async {
        started.complete();
        await cancelled.future;
        await cleanup.future;
        throw StateError('native handshake stopped');
      };
      api.signal = (_) => cancelled.complete();
      final client = NativeAdbClient(api, '/owned');
      final stop = AdbCancellation();
      final opening = usb
          ? client.connectUsbFd(42, 'usb', cancellation: stop)
          : client.connect('target', cancellation: stop);
      var finished = false;
      final rejected = expectLater(
        opening.whenComplete(() => finished = true),
        throwsA(_cancelled),
      );
      await started.future;
      stop.cancel();
      await cancelled.future;
      expect(finished, isFalse);
      expect(api.closedHandshakes, isEmpty);
      cleanup.complete();
      await rejected;
      expect(api.closedHandshakes, ['handshake-1']);
      await client.close();
    }
  });
  test('取消竞争仍认领并精确断开迟到成功连接', () async {
    final api = _HandshakeApi();
    final started = Completer<void>(),
        cancelled = Completer<void>(),
        late = Completer<AdbDevice>();
    api.open = (id) {
      started.complete();
      return late.future;
    };
    api.signal = (_) => cancelled.complete();
    final client = NativeAdbClient(api, '/owned');
    final stop = AdbCancellation();
    final rejected = expectLater(
      client.connect('target', cancellation: stop),
      throwsA(_cancelled),
    );
    await started.future;
    stop.cancel();
    await cancelled.future;
    late.complete(
      const AdbDevice(
        id: 'late-original',
        serial: 'same-serial',
        state: 'device',
      ),
    );
    await rejected;
    expect(api.disconnected, ['late-original']);
    expect(api.closedHandshakes, ['handshake-1']);
    await client.close();
  });
  test('结束握手失败保留登记重试，并回收尚未交给调用方的成功连接', () async {
    final api = _HandshakeApi()..handshakeCloseFailures = 1;
    final client = NativeAdbClient(api, '/owned');
    await expectLater(client.connect('target'), throwsStateError);
    expect(api.disconnected, ['handshake-1']);
    expect(api.closedHandshakes, ['handshake-1']);
    await client.close();
    expect(api.closedHandshakes, ['handshake-1', 'handshake-1']);
  });
  test('配对取消等待实际退出，已经提交的真实成功不会伪装成撤销', () async {
    for (final succeeded in [false, true]) {
      final api = _HandshakeApi();
      final started = Completer<void>(),
          cancelled = Completer<void>(),
          cleanup = Completer<void>();
      api.pairAction = (id) async {
        started.complete();
        await cancelled.future;
        await cleanup.future;
        if (!succeeded) {
          throw StateError('pair interrupted after possible peer commit');
        }
        return 'actual-peer-guid';
      };
      api.signal = (_) => cancelled.complete();
      final client = NativeAdbClient(api, '/owned');
      final stop = AdbCancellation();
      final pairing = client.pair('target', 'code', cancellation: stop);
      final result = succeeded
          ? expectLater(pairing, completion('actual-peer-guid'))
          : expectLater(
              pairing,
              throwsA(
                isA<AdbException>()
                    .having((e) => e.code, 'code', 'cancelled')
                    .having((e) => e.message, 'message', contains('可能已保存信任')),
              ),
            );
      await started.future;
      stop.cancel();
      await cancelled.future;
      expect(api.closedHandshakes, isEmpty);
      cleanup.complete();
      await result;
      await client.close();
    }
  });
  for (final code in ['pairing_result_unknown', 'adb_cleanup_unconfirmed']) {
    test('配对已取消后仍保留原生 $code，并等待精确握手清理', () async {
      final api = _HandshakeApi();
      final started = Completer<void>(), cancelled = Completer<void>();
      final cleaning = Completer<void>(), cleaned = Completer<void>();
      final nativeResult = Completer<String>();
      final failure = AdbException(code, '原生结果仍需调用方核验。');
      api.pairAction = (_) {
        started.complete();
        return nativeResult.future;
      };
      api.signal = (_) => cancelled.complete();
      api.closeAction = (_) async {
        cleaning.complete();
        await cleaned.future;
      };
      final client = NativeAdbClient(api, '/owned');
      final stop = AdbCancellation();
      var finished = false;
      final result = expectLater(
        client.pair('target', 'code', cancellation: stop).whenComplete(() {
          finished = true;
        }),
        throwsA(same(failure)),
      );
      await started.future;
      stop.cancel();
      await cancelled.future;
      expect(api.closedHandshakes, isEmpty);
      nativeResult.completeError(failure);
      await cleaning.future;
      expect(finished, isFalse, reason: '结果未知不能使原生握手清理脱离所有者');
      cleaned.complete();
      await result;
      expect(api.cancelledHandshakes, ['handshake-1']);
      expect(api.closedHandshakes, ['handshake-1']);
      expect(api.disconnected, isEmpty);
      await client.close();
      expect(api.closedHandshakes, ['handshake-1']);
    });
  }
  for (final usb in [false, true]) {
    test('${usb ? 'USB' : 'TCP'} 已取消后原生清理未确认仍保留原错误', () async {
      final api = _HandshakeApi();
      final started = Completer<void>(), cancelled = Completer<void>();
      final nativeResult = Completer<AdbDevice>();
      const failure = AdbException('adb_cleanup_unconfirmed', '驱动仍在排空。');
      api.open = (_) {
        started.complete();
        return nativeResult.future;
      };
      api.signal = (_) => cancelled.complete();
      final client = NativeAdbClient(api, '/owned');
      final stop = AdbCancellation();
      final opening = usb
          ? client.connectUsbFd(42, 'usb', cancellation: stop)
          : client.connect('target', cancellation: stop);
      final result = expectLater(opening, throwsA(same(failure)));
      await started.future;
      stop.cancel();
      await cancelled.future;
      nativeResult.completeError(failure);
      await result;
      expect(api.cancelledHandshakes, ['handshake-1']);
      expect(api.closedHandshakes, ['handshake-1']);
      expect(api.disconnected, isEmpty, reason: '未交付实际连接时不能捏造断开句柄');
      await client.close();
    });
  }
  test('登记清理等待期间的取消和关闭阻止成功连接继续交付', () async {
    for (final closeClient in [false, true]) {
      final api = _HandshakeApi();
      final cleaning = Completer<void>(), cleaned = Completer<void>();
      api.closeAction = (_) async {
        cleaning.complete();
        await cleaned.future;
      };
      final client = NativeAdbClient(api, '/owned');
      final stop = AdbCancellation();
      final opening = client.connect('target', cancellation: stop);
      final rejected = expectLater(opening, throwsA(isA<AdbException>()));
      await cleaning.future;
      Future<void>? closing;
      if (closeClient) {
        closing = client.close();
      } else {
        stop.cancel();
      }
      cleaned.complete();
      await rejected;
      if (closing != null) await closing;
      expect(api.disconnected, ['handshake-1']);
      await client.close();
    }
  });
  test('配对真实成功不被登记清理错误覆盖，关闭仍重试同一握手', () async {
    final api = _HandshakeApi()..handshakeCloseFailures = 1;
    api.pairAction = (_) async => 'actual-peer-guid';
    final client = NativeAdbClient(api, '/owned');
    expect(await client.pair('target', 'code'), 'actual-peer-guid');
    expect(api.closedHandshakes, ['handshake-1']);
    await client.close();
    expect(api.closedHandshakes, ['handshake-1', 'handshake-1']);
  });
  test('取消观察者抛错仍通知真实握手，重复取消不会重复执行监听', () async {
    final api = _HandshakeApi();
    final started = Completer<void>(), cancelled = Completer<void>();
    api.open = (_) async {
      started.complete();
      await cancelled.future;
      throw StateError('handshake stopped');
    };
    api.signal = (_) => cancelled.complete();
    final stop = AdbCancellation();
    var failingCalls = 0;
    stop.onCancel(() {
      failingCalls++;
      throw StateError('observer failed');
    });
    final client = NativeAdbClient(api, '/owned');
    final rejected = expectLater(
      client.connect('target', cancellation: stop),
      throwsA(_cancelled),
    );
    await started.future;
    expect(stop.cancel, throwsStateError);
    await rejected;
    stop.cancel();
    expect(failingCalls, 1);
    expect(api.cancelledHandshakes, ['handshake-1']);
    await client.close();
  });
  test('同库不同 Client 的关闭只取消自己的握手', () async {
    final api = _HandshakeApi();
    final started = <String, Completer<void>>{};
    final stops = <String, Completer<void>>{};
    api.open = (id) async {
      final stop = stops[id] = Completer<void>();
      started[id]!.complete();
      await stop.future;
      throw StateError('stopped');
    };
    api.signal = (id) => stops[id]!.complete();
    final first = NativeAdbClient(api, '/first'),
        second = NativeAdbClient(api, '/second');
    started['handshake-1'] = Completer<void>();
    final firstResult = expectLater(first.connect('A'), throwsA(_cancelled));
    await started['handshake-1']!.future;
    started['handshake-2'] = Completer<void>();
    final secondResult = expectLater(second.connect('B'), throwsA(_cancelled));
    await started['handshake-2']!.future;
    await first.close();
    await firstResult;
    expect(api.cancelledHandshakes, ['handshake-1']);
    expect(stops['handshake-2']!.isCompleted, isFalse);
    await second.close();
    await secondResult;
    expect(api.cancelledHandshakes, ['handshake-1', 'handshake-2']);
  });
  test('无效选项在建立连接前拒绝，不截断毫秒或按字符数放过超长公钥注释', () async {
    final api = _Api();
    final client = NativeAdbClient(api, '/owned/key');
    addTearDown(client.close);
    final invalid = [
      AdbConnectOptions(publicKeyComment: '中' * 342),
      const AdbConnectOptions(publicKeyComment: 'name\nother'),
      const AdbConnectOptions(
        tcp: AdbTcpOptions(userTimeout: Duration(microseconds: 1500)),
      ),
      const AdbConnectOptions(
        tcp: AdbTcpOptions(userTimeout: Duration(milliseconds: 0x80000000)),
      ),
      const AdbConnectOptions(
        tcp: AdbTcpOptions(
          keepalive: AdbKeepaliveOptions(
            idle: Duration(milliseconds: 999),
            interval: Duration(seconds: 1),
            retries: 1,
          ),
        ),
      ),
      const AdbConnectOptions(
        tcp: AdbTcpOptions(
          keepalive: AdbKeepaliveOptions(
            idle: Duration(seconds: 1),
            interval: Duration(seconds: 1),
            retries: 128,
          ),
        ),
      ),
    ];
    for (final options in invalid) {
      expect(
        () => client.connect('tcp', directOptions: options),
        throwsArgumentError,
      );
      expect(
        () => client.connectUsbFd(42, 'usb', options: options),
        throwsArgumentError,
      );
    }
    expect(api.lastConnectOptions, isNull);
    expect(api.lastUsbOptions, isNull);
  });

  test(
    'close drains an in-flight bounded pairing without claiming cancellation',
    () async {
      final api = _Api()..pairing = Completer<String>();
      final client = NativeAdbClient(api, '/owned');
      final pairing = client.pair('endpoint', 'code');
      var closed = false;
      final closing = client.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      expect(() => client.pair('other', 'code'), throwsA(isA<AdbException>()));
      api.pairing!.complete('actual-peer-guid');
      expect(await pairing, 'actual-peer-guid');
      await closing;
    },
  );
  test('foreign host handles are rejected before dispatch', () async {
    final api = _Api();
    final client = NativeAdbClient(api, '/owned');
    final foreign = AdbDevice(
      id: device.id,
      serial: device.serial,
      state: device.state,
      nativeOwner: Object(),
    );
    final error = isA<AdbException>().having(
      (error) => error.code,
      'code',
      'foreign_native_host',
    );
    expect(() => client.disconnect(foreign), throwsA(error));
    await expectLater(client.shell(foreign, 'command').first, throwsA(error));
    await expectLater(client.services.connectionFacts(foreign), throwsA(error));
    expect(api.reads, 0);
    expect(api.disconnected, isEmpty);
    await client.close();
  });
  test('failed disconnect retains the exact handle for client close', () async {
    final api = _Api()..disconnectFailures = 1;
    final client = NativeAdbClient(api, '/owned');
    final connected = await client.connect('owned');
    await expectLater(client.disconnect(connected), throwsStateError);
    await expectLater(
      client.shell(connected, 'new command').drain<void>(),
      throwsA(
        isA<AdbException>().having(
          (e) => e.code,
          'code',
          'connection_retiring',
        ),
      ),
    );
    expect(api.reads, 0);
    await client.close();
    expect(api.disconnected, ['owned', 'owned']);
  });
  test('listing a handle alone does not claim its cleanup', () async {
    final api = _Api();
    final client = NativeAdbClient(api, '/owned');
    await client.devices();
    await client.close();
    expect(api.disconnected, isEmpty);
  });
  test(
    'late connection cleanup failure is retained for a close retry',
    () async {
      final api = _Api()
        ..opening = Completer<AdbDevice>()
        ..disconnectFailures = 2;
      final client = NativeAdbClient(api, '/owned');
      final rejected = expectLater(client.connect('late'), throwsStateError);
      final closing = client.close();
      final failedClose = expectLater(closing, throwsStateError);
      api.opening!.complete(
        const AdbDevice(id: 'late', serial: 'late', state: 'device'),
      );
      await rejected;
      await failedClose;
      await client.close();
      expect(api.disconnected, ['late', 'late', 'late']);
    },
  );
  test(
    'missing bundled desktop binary fails without a PATH fallback',
    () async {
      if (Platform.isAndroid || Platform.isIOS) return;
      final root = await Directory.systemTemp.createTemp(
        'flutter-adb-missing-',
      );
      addTearDown(() => root.delete(recursive: true));
      await expectLater(
        AdbHost.prepare(
          dataDirectory: root,
          binaryDirectory: root,
          bindings: await createNativeAdbApi(),
        ),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}

class _Api implements NativeAdbApi {
  int reads = 0, closes = 0;
  int disconnectFailures = 0;
  final disconnected = <String>[];
  Completer<AdbDevice>? opening;
  Completer<String>? pairing;
  AdbConnectOptions? lastConnectOptions, lastUsbOptions;
  @override
  Future<List<AdbDevice>> devices() async => [device];
  @override
  Future<AdbDevice> connect(
    String address,
    String identityPath,
    bool requireTls,
    bool authorize,
    int timeoutMs, {
    AdbConnectOptions options = const AdbConnectOptions(),
    String? handshakeId,
  }) async {
    lastConnectOptions = options;
    return opening == null
        ? AdbDevice(id: address, serial: address, state: 'device')
        : opening!.future;
  }

  @override
  Future<AdbDevice> connectUsbFd(
    int fd,
    String serial,
    String identityPath,
    bool authorize,
    int timeoutMs, {
    AdbConnectOptions options = const AdbConnectOptions(),
    String? handshakeId,
  }) async {
    lastUsbOptions = options;
    return AdbDevice(id: serial, serial: serial, state: 'device');
  }

  @override
  Future<void> disconnect(String id) async {
    disconnected.add(id);
    if (disconnectFailures > 0) {
      disconnectFailures--;
      throw StateError('disconnect was not confirmed');
    }
  }

  @override
  Future<String> pair(
    String address,
    String password,
    String identityPath,
    int timeoutMs, {
    String? handshakeId,
  }) => pairing?.future ?? Future.value('peer');

  final cancelled = <String>[];
  @override
  Future<String> shell(String id, String command, int timeoutMs) async =>
      'operation';
  @override
  Future<NativeAdbEvent?> next(String id) async {
    reads++;
    return switch (reads) {
      1 => NativeAdbEvent(
        kind: 'stdout',
        bytes: Uint8List.fromList([0, 255]),
        done: false,
      ),
      2 => NativeAdbEvent(
        kind: 'stderr',
        bytes: Uint8List.fromList([101]),
        done: false,
      ),
      3 => NativeAdbEvent(
        kind: 'exit',
        bytes: Uint8List(0),
        done: true,
        exitCode: 7,
      ),
      _ => null,
    };
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
  }

  @override
  Future<void> close() async {
    closes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _cancelled = isA<AdbException>().having(
  (e) => e.code,
  'code',
  'cancelled',
);

class _HandshakeApi extends _Api implements NativeAdbHandshakeApi {
  int created = 0, handshakeCloseFailures = 0;
  Completer<String>? creating;
  final opened = <String>[];
  final cancelledHandshakes = <String>[];
  final closedHandshakes = <String>[];
  Future<AdbDevice> Function(String)? open;
  Future<String> Function(String)? pairAction;
  void Function(String)? signal;
  Future<void> Function(String)? closeAction;
  @override
  Future<String> createHandshake() async {
    created++;
    return creating?.future ?? 'handshake-$created';
  }

  @override
  Future<void> cancelHandshake(String id) async {
    cancelledHandshakes.add(id);
    signal?.call(id);
  }

  @override
  Future<void> closeHandshake(String id) async {
    closedHandshakes.add(id);
    await closeAction?.call(id);
    if (handshakeCloseFailures > 0) {
      handshakeCloseFailures--;
      throw StateError('handshake cleanup unconfirmed');
    }
  }

  Future<AdbDevice> _open(String? handshakeId) async {
    final id = handshakeId!;
    opened.add(id);
    return open?.call(id) ??
        AdbDevice(id: id, serial: 'target', state: 'device');
  }

  @override
  Future<AdbDevice> connect(
    String address,
    String identityPath,
    bool requireTls,
    bool authorize,
    int timeoutMs, {
    AdbConnectOptions options = const AdbConnectOptions(),
    String? handshakeId,
  }) => _open(handshakeId);
  @override
  Future<AdbDevice> connectUsbFd(
    int fd,
    String serial,
    String identityPath,
    bool authorize,
    int timeoutMs, {
    AdbConnectOptions options = const AdbConnectOptions(),
    String? handshakeId,
  }) => _open(handshakeId);
  @override
  Future<String> pair(
    String address,
    String password,
    String identityPath,
    int timeoutMs, {
    String? handshakeId,
  }) => pairAction?.call(handshakeId!) ?? Future.value('peer');
}

final class _ScopedApi extends _HandshakeApi implements NativeAdbAdmissionApi {
  AdbAdmissionScopeInfo? current = const AdbAdmissionScopeInfo(
    scopeKey: '/technical/admission',
    scopeId: 'scope-1',
    accepting: true,
  );
  final scopeClosing = Completer<void>(), connectionStarted = Completer<void>();
  int generation = 1, scopeCloseFailures = 0;
  final scopeClosed = <String>[];
  final confirmed = <String>[];
  final claims = <(String, String)>[];
  final scopes = <String, String>{};
  @override
  Future<AdbAdmissionScopeInfo?> inspectAdmissionScope(String key) async =>
      current?.scopeKey == key ? current : null;
  @override
  Future<AdbAdmissionScopeInfo> attachAdmissionScope(
    String key, {
    String? expectedScopeId,
    int timeoutMs = 7000,
  }) async {
    if (current?.scopeId != expectedScopeId) {
      throw const AdbException('adb_admission_scope_stale');
    }
    return current = AdbAdmissionScopeInfo(
      scopeKey: key,
      scopeId: 'scope-${++generation}',
      accepting: true,
    );
  }

  @override
  Future<void> closeAdmissionScope(String id, {int timeoutMs = 7000}) async {
    scopeClosed.add(id);
    if (!scopeClosing.isCompleted) scopeClosing.complete();
    if (current?.scopeId != id) return;
    current = AdbAdmissionScopeInfo(
      scopeKey: current!.scopeKey,
      scopeId: id,
      accepting: false,
    );
    if (scopeCloseFailures-- > 0) throw StateError('scope cleanup unconfirmed');
    current = null;
  }

  @override
  Future<String> createScopedHandshake(String scope) async {
    if (current?.scopeId != scope || current?.accepting != true) {
      throw const AdbException('adb_admission_scope_stale');
    }
    final id = await createHandshake();
    scopes[id] = scope;
    return id;
  }

  @override
  Future<AdbDevice> connect(
    String address,
    String identityPath,
    bool requireTls,
    bool authorize,
    int timeoutMs, {
    AdbConnectOptions options = const AdbConnectOptions(),
    String? handshakeId,
  }) {
    if (!connectionStarted.isCompleted) connectionStarted.complete();
    return super.connect(
      address,
      identityPath,
      requireTls,
      authorize,
      timeoutMs,
      options: options,
      handshakeId: handshakeId,
    );
  }

  @override
  Future<void> confirmHandshakeConnection(
    String handshake,
    String connection,
  ) async {
    if (current?.scopeId != scopes[handshake] || current?.accepting != true) {
      throw const AdbException('adb_admission_scope_stale');
    }
    confirmed.add(connection);
  }

  @override
  Future<AdbDevice> claimScopedConnection(
    String connection,
    String handshake,
  ) async {
    claims.add((connection, handshake));
    return AdbDevice(
      id: 'claimed-$connection',
      serial: 'target',
      state: 'device',
    );
  }
}

final class _ClaimApi extends _Api implements NativeAdbConnectionApi {
  int connectCount = 0, claimCount = 0;
  final active = <String>{};
  Completer<AdbDevice>? claiming;
  Completer<void>? disconnecting;
  Object? claimFailure;

  @override
  Future<AdbDevice> connect(
    String address,
    String identityPath,
    bool requireTls,
    bool authorize,
    int timeoutMs, {
    AdbConnectOptions options = const AdbConnectOptions(),
    String? handshakeId,
  }) async {
    connectCount++;
    final result = await super.connect(
      address,
      identityPath,
      requireTls,
      authorize,
      timeoutMs,
      options: options,
      handshakeId: handshakeId,
    );
    active.add(result.id);
    return result;
  }

  @override
  Future<AdbDevice> claimConnection(String id) async {
    claimCount++;
    if (claimFailure case final failure?) throw failure;
    if (claiming == null && !active.contains(id)) {
      throw const AdbException('stale_connection');
    }
    final result = claiming == null
        ? AdbDevice(
            id: 'claimed-$claimCount',
            serial: 'target',
            state: 'device',
          )
        : await claiming!.future;
    active.remove(id);
    active.add(result.id);
    return result;
  }

  @override
  Future<void> disconnect(String id) async {
    await disconnecting?.future;
    await super.disconnect(id);
    active.remove(id);
  }

  @override
  Future<String> shell(String id, String command, int timeoutMs) async {
    if (!active.contains(id)) throw const AdbException('stale_connection');
    return super.shell(id, command, timeoutMs);
  }
}

Matcher _code(String code) =>
    isA<AdbException>().having((e) => e.code, 'code', code);
