import 'dart:async';
import 'dart:io';

enum AdbRecoveryFault { eof, blackhole }

/// 在主控实际 ADB 传输中提供字节透明的故障点。
///
/// 黑洞仅消费并丢弃一对现存连接的应用层数据，
/// 不修改网络接口，也不模拟内核 TCP 半开。
/// 后续连接正常转发，不检查或保留载荷；
/// 正常转发维持背压，丢弃模式持续读取。
class AdbFaultProxy {
  AdbFaultProxy(this.upstreamPort, {this.listenPort = 25557});

  final int upstreamPort;
  final int listenPort;
  final events = <Map<String, Object?>>[];
  final _pairs = <_SocketPair>{};
  final _tasks = <Future<void>>{};
  ServerSocket? _server;
  StreamSubscription<Socket>? _subscription;
  bool _closed = false;
  Future<void>? _closing;
  _SocketPair? _faultPair;
  Map<String, Object?>? _injection;
  AdbRecoveryFault? _fault;
  int accepts = 0;
  int? faultAcceptCount;

  int get port => _server!.port;

  void _event(String kind, [Map<String, Object?> details = const {}]) {
    events.add({
      'kind': kind,
      'at': DateTime.now().toUtc().toIso8601String(),
      'acceptCount': accepts,
      ...details,
    });
  }

  Future<void> start() async {
    _server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      listenPort,
      shared: false,
    ).timeout(const Duration(seconds: 10));
    _event('listening', {'port': port, 'upstreamPort': upstreamPort});
    _subscription = _server!.listen((socket) {
      if (_closed) {
        socket.destroy();
        return;
      }
      final pair = _SocketPair(++accepts, socket);
      _pairs.add(pair);
      _event('accept', {'socketId': pair.id});
      final task = _forward(pair);
      _tasks.add(task);
      unawaited(task.then((_) => _tasks.remove(task)));
    }, onError: (Object error) => _event('listener-error'));
  }

  Future<void> _forward(_SocketPair pair) async {
    try {
      final upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        upstreamPort,
        timeout: const Duration(seconds: 10),
      );
      pair.upstream = upstream;
      if (pair.closed || _closed) {
        upstream.destroy();
        return;
      }
      _event('upstream-connected', {'socketId': pair.id});
      Future<void> pipe(
        Socket source,
        Socket destination,
        String direction,
      ) async {
        pair.reading.add(direction);
        var end = 'eof';
        try {
          await for (final bytes in source) {
            if (pair.blackholed) {
              pair.dropped.update(direction, (count) => count + bytes.length);
            } else {
              destination.add(bytes);
              // 先前 flush 等待背压时注入故障，需解除读取循环；最多只保留已排队块，此后各块均被消费并丢弃。
              //
              //
              final wake = Completer<void>();
              pair.flushWake[direction] = wake;
              try {
                await Future.any<void>([destination.flush(), wake.future]);
              } finally {
                pair.flushWake.remove(direction);
              }
            }
          }
        } catch (_) {
          end = 'error';
          if (!pair.closed) _event('pipe-error', {'socketId': pair.id});
        } finally {
          pair.reading.remove(direction);
          if (pair.closed) end = 'local-close';
          final receipt = <String, Object?>{
            'socketId': pair.id,
            'direction': direction,
            'end': end,
            'acceptCount': accepts,
            'socketCloseOperationsBeforeEnd': pair.socketCloseOperations,
          };
          pair.firstEnd ??= receipt;
          _event('direction-ended', receipt);
          pair.close('$direction-$end');
        }
      }

      await Future.wait([
        pipe(pair.controller, upstream, 'controller-to-upstream'),
        pipe(upstream, pair.controller, 'upstream-to-controller'),
      ]);
    } catch (_) {
      if (!pair.closed) _event('upstream-error', {'socketId': pair.id});
    } finally {
      pair.close('forward-finished');
      _pairs.remove(pair);
      _event('closed', {
        'socketId': pair.id,
        'closeReason': pair.closeReason,
        'socketCloseOperations': pair.socketCloseOperations,
        'droppedBytes': Map<String, int>.of(pair.dropped),
      });
    }
  }

  void injectFault(AdbRecoveryFault fault) {
    if (faultAcceptCount != null) {
      throw StateError('Transport already faulted.');
    }
    final active = _pairs.where((pair) => !pair.closed).toList();
    if (active.length != 1 || active.single.upstream == null) {
      throw StateError('Expected exactly one connected controller ADB socket.');
    }
    final pair = active.single;
    faultAcceptCount = accepts;
    _fault = fault;
    _faultPair = pair;
    final before = pair.socketCloseOperations;
    if (fault == AdbRecoveryFault.blackhole) {
      pair.blackholed = true;
      pair.wakeReads();
    } else {
      pair.close('fault-eof');
    }
    _injection = {
      'socketId': pair.id,
      'fault': fault.name,
      'applicationLevelDiscard': fault == AdbRecoveryFault.blackhole,
      'socketCloseOperationsByInjection': pair.socketCloseOperations - before,
      'controllerReadActive': pair.reading.contains('controller-to-upstream'),
      'upstreamReadActive': pair.reading.contains('upstream-to-controller'),
      'pairClosedAfterInjection': pair.closed,
    };
    _event('fault-injected', _injection!);
  }

  bool get reconnected =>
      faultAcceptCount != null &&
      events.any(
        (event) =>
            event['kind'] == 'upstream-connected' &&
            (event['socketId']! as int) > faultAcceptCount!,
      );

  Map<String, Object?> get faultEvidence => {
    ...?_injection,
    'faultAcceptCount': faultAcceptCount,
    'droppedBytes': _faultPair == null
        ? null
        : Map<String, int>.of(_faultPair!.dropped),
    'firstDirectionEnd': _faultPair?.firstEnd,
    'closeReason': _faultPair?.closeReason,
    'reconnected': reconnected,
  };

  /// 关闭前调用，清理不能充当恢复证据。
  List<String> recoveryEvidenceErrors() {
    final errors = <String>[];
    final pair = _faultPair;
    final injection = _injection;
    if (pair == null || injection == null || _fault == null) {
      return ['No transport fault was injected.'];
    }
    if (!reconnected) errors.add('No new connected ADB transport after fault.');
    if (_fault == AdbRecoveryFault.eof) {
      if (injection['socketCloseOperationsByInjection'] != 2 ||
          injection['pairClosedAfterInjection'] != true) {
        errors.add('EOF injection did not close the original socket pair.');
      }
      return errors;
    }
    if (injection['socketCloseOperationsByInjection'] != 0 ||
        injection['pairClosedAfterInjection'] != false ||
        injection['controllerReadActive'] != true ||
        injection['upstreamReadActive'] != true) {
      errors.add('Blackhole injection did not preserve both active sockets.');
    }
    if (pair.dropped.values.any((count) => count == 0)) {
      errors.add(
        'The original blackhole connection must discard actual bytes in both '
        'directions.',
      );
    }
    final first = pair.firstEnd;
    if (first == null ||
        first['direction'] != 'controller-to-upstream' ||
        first['end'] != 'eof' ||
        first['socketCloseOperationsBeforeEnd'] != 0 ||
        first['acceptCount'] != faultAcceptCount ||
        pair.closeReason != 'controller-to-upstream-eof') {
      errors.add(
        'The controller must end the old connection with EOF before any new '
        'connection and before any local socket close.',
      );
    }
    return errors;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final pair in _pairs.toList()) {
      pair.close('shutdown');
    }
    await _server?.close().timeout(const Duration(seconds: 5));
    await _subscription?.cancel().timeout(const Duration(seconds: 5));
    await Future.wait(_tasks.toList()).timeout(const Duration(seconds: 15));
    _event('stopped');
  }
}

class _SocketPair {
  _SocketPair(this.id, this.controller);

  final int id;
  final Socket controller;
  Socket? upstream;
  bool closed = false;
  bool blackholed = false;
  final flushWake = <String, Completer<void>>{};
  final reading = <String>{};
  final dropped = <String, int>{
    'controller-to-upstream': 0,
    'upstream-to-controller': 0,
  };
  Map<String, Object?>? firstEnd;
  String? closeReason;
  int socketCloseOperations = 0;

  void wakeReads() {
    for (final wake in flushWake.values) {
      if (!wake.isCompleted) wake.complete();
    }
  }

  void close(String reason) {
    if (closed) return;
    closed = true;
    wakeReads();
    closeReason = reason;
    socketCloseOperations++;
    controller.destroy();
    if (upstream != null) {
      socketCloseOperations++;
      upstream!.destroy();
    }
  }
}
