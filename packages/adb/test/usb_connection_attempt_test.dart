import 'dart:async';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _code(String code) =>
    throwsA(isA<AdbException>().having((error) => error.code, 'code', code));

void main() {
  test('预取消仍同步返回可关闭句柄，不创建握手或借用平台 FD', () async {
    final api = _UsbApi();
    final client = NativeAdbClient(api, '/owned/key');
    final attempt = client.beginUsbFdConnection(
      42,
      'usb',
      cancellation: AdbCancellation()..cancel(),
    );
    expect(attempt, isA<NativeAdbConnectionAttempt>());
    await expectLater(attempt.result, _code('cancelled'));
    await attempt.close();
    expect(api.created, isEmpty);
    expect(api.opened, isEmpty);
    await client.close();
  });

  test('close 等待迟到握手登记，原始资源未确认前不提前返回', () async {
    final api = _UsbApi()..creationGate = Completer<void>();
    final client = NativeAdbClient(api, '/owned/key');
    final attempt = client.beginUsbFdConnection(42, 'usb');
    final rejected = expectLater(attempt.result, _code('cancelled'));
    await api.creating.future;
    var finished = false;
    final closing = attempt.close().then((_) => finished = true);
    expect(finished, isFalse);
    api.creationGate!.complete();
    await rejected;
    await closing;
    expect(api.opened, isEmpty);
    expect(api.closed, api.created);
    expect(api.activeHandshakes, isEmpty);
    await client.close();
  });

  test('迟到已分配连接的断开失败可由同一 attempt 重试，不依赖原 result', () async {
    final api = _UsbApi()
      ..usbResult = Completer<AdbDevice>()
      ..disconnectFailures = 2;
    final client = NativeAdbClient(api, '/owned/key');
    final attempt = client.beginUsbFdConnection(42, 'usb');
    final rejected = expectLater(attempt.result, throwsStateError);
    await api.usbOpening.future;
    final closing = attempt.close();
    final failedClose = expectLater(closing, throwsStateError);
    api.usbResult!.complete(
      const AdbDevice(id: 'late-usb', serial: 'usb', state: 'device'),
    );
    await rejected;
    await failedClose;
    expect(api.live, {'late-usb'});
    expect(api.disconnected, ['late-usb', 'late-usb']);
    await attempt.close();
    expect(api.live, isEmpty);
    expect(api.disconnected, ['late-usb', 'late-usb', 'late-usb']);
    await attempt.close();
    expect(api.disconnected, hasLength(3));
    await client.close();
    expect(api.disconnected, hasLength(3));
  });

  test('握手 close 失败保留精确 ID，多次失败后仍可重试且不重复断开连接', () async {
    final api = _UsbApi()..handshakeCloseFailures = 2;
    final client = NativeAdbClient(api, '/owned/key');
    final attempt = client.beginUsbFdConnection(42, 'usb');
    await expectLater(attempt.result, throwsStateError);
    expect(api.disconnected, ['usb-1']);
    await expectLater(attempt.close(), throwsStateError);
    expect(api.activeHandshakes, {'handshake-1'});
    await attempt.close();
    expect(api.closed, ['handshake-1', 'handshake-1', 'handshake-1']);
    expect(api.disconnected, ['usb-1']);
    await client.close();
  });

  test('本次取消仅回收迟到 USB，保留同一客户端的其它实际连接', () async {
    final api = _UsbApi()..usbResult = Completer<AdbDevice>();
    final client = NativeAdbClient(api, '/owned/key');
    final other = await client.connect('other');
    final attempt = client.beginUsbFdConnection(42, 'usb');
    final rejected = expectLater(attempt.result, _code('cancelled'));
    await api.usbOpening.future;
    final closing = attempt.close();
    api.usbResult!.complete(
      const AdbDevice(id: 'late-usb', serial: 'usb', state: 'device'),
    );
    await rejected;
    await closing;
    expect(api.live, {other.id});
    expect((await client.services.connectionFacts(other)).closed, isFalse);
    expect(api.disconnected, ['late-usb']);
    await client.close();
    expect(api.disconnected, ['late-usb', other.id]);
  });

  test('已成功交付后 attempt.close 和外部迟到取消均不能断开接收者连接', () async {
    final api = _UsbApi();
    final owner = Object();
    final client = NativeAdbClient(api, '/owned/key', nativeOwner: owner);
    final stop = AdbCancellation();
    final attempt = client.beginUsbFdConnection(42, 'usb', cancellation: stop);
    final device = await attempt.result;
    expect(identical(device.nativeOwner, owner), isTrue);
    stop.cancel();
    await attempt.close();
    await attempt.close();
    expect(api.disconnected, isEmpty);
    expect(api.cancelled, isEmpty);
    expect(api.live, {device.id});
    await client.disconnect(device);
    expect(api.disconnected, [device.id]);
    await client.close();
    expect(api.disconnected, [device.id]);
  });

  test('已经等待握手退出但尚未交付时 close 仍撤准入并回收分配连接', () async {
    final api = _UsbApi()..handshakeCloseGate = Completer<void>();
    final client = NativeAdbClient(api, '/owned/key');
    final attempt = client.beginUsbFdConnection(42, 'usb');
    final rejected = expectLater(attempt.result, _code('cancelled'));
    await api.closing.future;
    var finished = false;
    final closing = attempt.close().then((_) => finished = true);
    expect(finished, isFalse);
    expect(api.live, {'usb-1'});
    api.handshakeCloseGate!.complete();
    await rejected;
    await closing;
    expect(api.disconnected, ['usb-1']);
    await client.close();
  });

  test('客户端全局关闭仍兜底保留的 attempt 清理责任，两者共享精确回收', () async {
    final api = _UsbApi()..handshakeCloseFailures = 1;
    final client = NativeAdbClient(api, '/owned/key');
    final attempt = client.beginUsbFdConnection(42, 'usb');
    await expectLater(attempt.result, throwsStateError);
    await client.close();
    expect(api.activeHandshakes, isEmpty);
    expect(api.live, isEmpty);
    expect(api.disconnected, ['usb-1']);
    final closes = api.closed.length;
    await attempt.close();
    expect(api.closed.length, closes);
    expect(api.disconnected, ['usb-1']);
  });

  test('纯参数错误先于任何登记，实际握手保留原生选项', () async {
    final api = _UsbApi();
    final client = NativeAdbClient(api, '/owned/key');
    expect(() => client.beginUsbFdConnection(-1, 'usb'), throwsArgumentError);
    expect(
      () => client.beginUsbFdConnection(42, 'usb', timeout: Duration.zero),
      throwsArgumentError,
    );
    expect(api.created, isEmpty);
    const options = AdbConnectOptions(burstMode: true);
    final attempt = client.beginUsbFdConnection(
      42,
      'usb',
      authorize: false,
      timeout: const Duration(milliseconds: 987),
      options: options,
    );
    await attempt.result;
    expect(api.parameters, (42, 'usb', '/owned/key', false, 987, options));
    await attempt.close();
    await client.close();
  });
}

final class _UsbApi implements NativeAdbApi, NativeAdbHandshakeApi {
  final created = <String>[],
      opened = <String>[],
      closed = <String>[],
      cancelled = <String>[];
  final disconnected = <String>[];
  final activeHandshakes = <String>{}, live = <String>{};
  final creating = Completer<void>(),
      usbOpening = Completer<void>(),
      closing = Completer<void>();
  Completer<void>? creationGate, handshakeCloseGate;
  Completer<AdbDevice>? usbResult;
  int handshakeCloseFailures = 0, disconnectFailures = 0;
  (int, String, String, bool, int, AdbConnectOptions)? parameters;

  @override
  Future<String> createHandshake() async {
    final id = 'handshake-${created.length + 1}';
    created.add(id);
    if (!creating.isCompleted) creating.complete();
    await creationGate?.future;
    activeHandshakes.add(id);
    return id;
  }

  @override
  Future<void> cancelHandshake(String id) async => cancelled.add(id);

  @override
  Future<void> closeHandshake(String id) async {
    closed.add(id);
    if (!closing.isCompleted) closing.complete();
    await handshakeCloseGate?.future;
    if (handshakeCloseFailures > 0) {
      handshakeCloseFailures--;
      throw StateError('handshake exit not confirmed');
    }
    activeHandshakes.remove(id);
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
    parameters = (fd, serial, identityPath, authorize, timeoutMs, options);
    opened.add(handshakeId!);
    if (!usbOpening.isCompleted) usbOpening.complete();
    final device =
        await (usbResult?.future ??
            Future.value(
              AdbDevice(
                id: 'usb-${created.length}',
                serial: serial,
                state: 'device',
              ),
            ));
    live.add(device.id);
    return device;
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
  }) async {
    live.add(address);
    return AdbDevice(id: address, serial: address, state: 'device');
  }

  @override
  Future<void> disconnect(String id) async {
    disconnected.add(id);
    if (disconnectFailures > 0) {
      disconnectFailures--;
      throw StateError('allocated driver still active');
    }
    live.remove(id);
  }

  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async =>
      AdbConnectionFacts(
        officialServer: false,
        closed: !live.contains(id),
        features: const [],
        connectionId: id,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
