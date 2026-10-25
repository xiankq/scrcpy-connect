import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';

void main() {
  for (final factory in <String, Future<NativeAdbApi> Function()>{
    'adb': () => createNativeAdbApi(),
    'scrcpy': () => createNativeScrcpyAdbApi(),
  }.entries) {
    for (final outcome in [
      AdbOpenProbeOutcome.rejected,
      AdbOpenProbeOutcome.cancelled,
    ]) {
      test('${factory.key} 真实 FRB OPEN ${outcome.name} 保留分层事实并精确回收', () async {
        final fixture = await _Server.open(outcome);
        addTearDown(fixture.close);
        final observed = expectLater(fixture.finished, completes);
        final api = await factory.value();
        final device = await api.connectServer(fixture.endpoint, 'probe', 5000);
        addTearDown(() => api.disconnect(device.id));
        final services = NativeAdbClient(api, '').services;
        addTearDown(services.close);
        final before = await services.connectionFacts(device);
        expect(before.inboundActivity, isNotNull);
        final token = AdbCancellation();
        final probe = await services.createOpenProbe(
          device,
          service: 'sync:',
          timeout: Duration(
            seconds: outcome == AdbOpenProbeOutcome.timedOut ? 1 : 5,
          ),
          cancellation: token,
        );
        await fixture.firstRequested.future;
        if (outcome == AdbOpenProbeOutcome.cancelled) token.cancel();
        final facts = await probe.result;
        expect(facts.layer, AdbOpenProbeLayer.officialServer);
        expect(facts.openWritten, isTrue);
        expect(facts.outcome, outcome);
        expect(facts.inboundActivity, isNotEmpty);
        await probe.close();
        await fixture.firstClosed.future;
        expect((await services.connectionFacts(device)).closed, isFalse);

        // 首个探针取消或失败后，第二次真实 OPEN 仍可使用同一 Client。
        final next = await services.createOpenProbe(
          device,
          service: 'sync:',
          timeout: const Duration(seconds: 5),
        );
        expect((await next.result).outcome, AdbOpenProbeOutcome.okay);
        await next.close();
        await observed;
        final after = await services.connectionFacts(device);
        expect(after.connectionId, before.connectionId);
        expect(after.inboundActivity, isNot(before.inboundActivity));
      });
    }

    test('${factory.key} 真实 FRB 探针非法连接保留 typed admission 错误', () async {
      final api = await factory.value();
      final services = NativeAdbClient(api, '').services;
      addTearDown(services.close);
      await expectLater(
        services.createOpenProbe(
          const AdbDevice(
            id: 'missing-open-probe-connection',
            serial: 'probe',
            state: 'device',
          ),
          service: 'sync:',
          timeout: const Duration(seconds: 1),
        ),
        throwsA(
          isA<AdbException>().having(
            (error) => error.code,
            'code',
            'adb_admission_rejected',
          ),
        ),
      );
    });
  }
}

/// 只监听独立环回端口，按长度前缀读取真实 smart-socket 请求。
/// 两个探针都等待对端真实 EOF，不将 Dart Future 完成当作 socket 已回收。
final class _Server {
  _Server(this._server, AdbOpenProbeOutcome outcome) {
    _incoming = StreamIterator(_server);
    finished = _serve(outcome);
  }
  static Future<_Server> open(AdbOpenProbeOutcome outcome) async => _Server(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    outcome,
  );
  final ServerSocket _server;
  late final StreamIterator<Socket> _incoming;
  final _sockets = <Socket>[];
  final _readers = <_Reader>[];
  late final Future<void> finished;
  final firstRequested = Completer<void>();
  final firstClosed = Completer<void>();
  String get endpoint => '127.0.0.1:${_server.port}';

  Future<_Reader> _accept() async {
    if (!await _incoming.moveNext()) throw StateError('监听意外结束。');
    final socket = _incoming.current;
    _sockets.add(socket);
    final reader = _Reader(socket);
    _readers.add(reader);
    return reader;
  }

  Future<void> _serve(AdbOpenProbeOutcome outcome) async {
    final transport = await _accept();
    expect(await transport.command(), 'host:tport:serial:probe');
    final id = ByteData(8)..setUint64(0, 7, Endian.little);
    await transport.send([...ascii.encode('OKAY'), ...id.buffer.asUint8List()]);
    await transport.finish();
    final features = await _accept();
    expect(await features.command(), 'host-transport-id:7:features');
    await features.send(ascii.encode('OKAY0000'));
    await features.finish();
    for (var index = 0; index < 2; index++) {
      final service = await _accept();
      expect(await service.command(), 'host:transport-id:7');
      await service.send(ascii.encode('OKAY'));
      expect(await service.command(), 'sync:');
      if (index == 0) firstRequested.complete();
      if (index == 1 || outcome == AdbOpenProbeOutcome.okay) {
        await service.send(ascii.encode('OKAY'));
      } else if (outcome == AdbOpenProbeOutcome.rejected) {
        await service.send(ascii.encode('FAIL'));
      }
      expect(await service.peerClosed(), isTrue);
      if (index == 0) firstClosed.complete();
      await service.finish();
    }
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    for (final reader in _readers) {
      await reader.cancel();
    }
    await _incoming.cancel();
    await _server.close();
  }
}

final class _Reader {
  _Reader(this.socket) : _chunks = StreamIterator(socket);
  final Socket socket;
  final StreamIterator<Uint8List> _chunks;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;
  Future<List<int>> _read(int count) async {
    final result = <int>[];
    while (result.length < count) {
      if (_offset == _buffer.length) {
        if (!await _chunks.moveNext()) throw StateError('请求提前结束。');
        _buffer = _chunks.current;
        _offset = 0;
      }
      final wanted = count - result.length;
      final available = _buffer.length - _offset;
      final length = wanted < available ? wanted : available;
      result.addAll(_buffer.sublist(_offset, _offset + length));
      _offset += length;
    }
    return result;
  }

  Future<String> command() async => ascii.decode(
    await _read(int.parse(ascii.decode(await _read(4)), radix: 16)),
  );
  Future<void> send(List<int> bytes) async {
    socket.add(bytes);
    await socket.flush();
  }

  Future<bool> peerClosed() async =>
      _offset == _buffer.length && !await _chunks.moveNext();
  Future<void> finish() async {
    await socket.close();
    await cancel();
  }

  Future<void> cancel() => _chunks.cancel();
}
