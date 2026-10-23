import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

/// Loopback proxy with independent delay, bandwidth and bounded backpressure in
/// each direction. Closing it cancels even a stalled write or long rate wait.
class WeakNetworkProxy {
  WeakNetworkProxy._(
    this._server,
    this._host,
    this._port,
    this._upload,
    this._download,
    this._log,
  );

  static Future<WeakNetworkProxy> start({
    required String upstreamHost,
    required int upstreamPort,
    int listenPort = 0,
    Duration uploadDelay = Duration.zero,
    Duration downloadDelay = Duration.zero,
    int uploadBytesPerSecond = 0,
    int downloadBytesPerSecond = 0,
    void Function(String)? log,
  }) async {
    if (uploadDelay.isNegative ||
        downloadDelay.isNegative ||
        uploadBytesPerSecond < 0 ||
        downloadBytesPerSecond < 0) {
      throw ArgumentError('Delay and bandwidth must be non-negative');
    }
    final proxy = WeakNetworkProxy._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, listenPort),
      upstreamHost,
      upstreamPort,
      _Direction(
        label: 'upload',
        delay: uploadDelay,
        rate: uploadBytesPerSecond,
      ),
      _Direction(
        label: 'download',
        delay: downloadDelay,
        rate: downloadBytesPerSecond,
      ),
      log,
    );
    proxy._subscription = proxy._server.listen(
      proxy._accept,
      onError: (Object error) {
        log?.call('weak-network proxy listener failed: $error');
        unawaited(proxy.close());
      },
    );
    log?.call(
      'weak-network proxy listening=${proxy.port} upstream=$upstreamHost:$upstreamPort upload=${proxy._upload.describe()} download=${proxy._download.describe()}',
    );
    return proxy;
  }

  final ServerSocket _server;
  final String _host;
  final int _port;
  final _Direction _upload, _download;
  final void Function(String)? _log;
  final _connections = <_Cancellation, Future<void>>{};
  final _done = Completer<void>();
  late final StreamSubscription<Socket> _subscription;
  Future<void>? _closing;
  int _nextConnection = 0;

  int get port => _server.port;
  Future<void> get done => _done.future;

  void _accept(Socket client) {
    if (_closing != null) {
      client.destroy();
      return;
    }
    final cancellation = _Cancellation();
    final task = _serve(client, cancellation, ++_nextConnection);
    _connections[cancellation] = task;
    unawaited(task.then((_) => _connections.remove(cancellation)));
  }

  Future<void> _serve(
    Socket client,
    _Cancellation cancellation,
    int connection,
  ) async {
    Socket? upstream;
    final pumps = <Future<void>>[];
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
      final connecting =
          Socket.connect(
            _host,
            _port,
            timeout: const Duration(seconds: 10),
          ).then((socket) {
            // A connect already in progress can complete after local shutdown.
            if (cancellation.stopped) socket.destroy();
            return socket;
          });
      upstream = await Future.any<Socket?>([
        connecting,
        cancellation.done.future.then((_) => null),
      ]);
      if (cancellation.stopped || upstream == null) return;
      upstream.setOption(SocketOption.tcpNoDelay, true);
      pumps.addAll([
        _pump(client, upstream, _upload, cancellation),
        _pump(upstream, client, _download, cancellation),
      ]);
      // Normal EOF only closes one TCP direction. The peer can still send a
      // response after consuming that EOF; errors abort the pair immediately.
      await Future.wait(pumps, eagerError: true);
    } catch (error) {
      if (!cancellation.stopped) {
        _log?.call('weak-network proxy connection=$connection failed: $error');
      }
    } finally {
      cancellation.cancel();
      client.destroy();
      upstream?.destroy();
      // A failed direction does not stop its peer. Wait until both reads,
      // output flushes and rate/delay waits have all observed cancellation.
      await Future.wait(pumps.map((pump) => pump.catchError((Object _) {})));
      _log?.call('weak-network proxy connection=$connection closed');
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    for (final cancellation in _connections.keys.toList()) {
      cancellation.cancel();
    }
    await _server.close();
    await _subscription.cancel();
    await Future.wait(_connections.values.toList());
    if (!_done.isCompleted) _done.complete();
  }
}

Future<void> _pump(
  Socket source,
  Socket sink,
  _Direction direction,
  _Cancellation cancellation,
) async {
  final queue = Queue<_Chunk>();
  final available = _Signal();
  final rate = _TokenBucket(direction.rate);
  final clock = Stopwatch()..start();
  late final StreamSubscription<List<int>> subscription;
  var pending = 0;
  var paused = false;
  var done = false;
  Object? readError;
  subscription = source.listen(
    (bytes) {
      if (bytes.isEmpty || cancellation.stopped) return;
      queue.add(
        _Chunk(
          bytes,
          clock.elapsedMicroseconds + direction.delay.inMicroseconds,
        ),
      );
      pending += bytes.length;
      if (!paused && pending >= _Direction.highWaterBytes) {
        paused = true;
        subscription.pause();
      }
      available.signal();
    },
    onError: (Object error) {
      readError = error;
      done = true;
      available.signal();
    },
    onDone: () {
      done = true;
      available.signal();
    },
    cancelOnError: true,
  );
  try {
    while (!cancellation.stopped && (!done || queue.isNotEmpty)) {
      if (queue.isEmpty) {
        await cancellation.wait(available.next);
        continue;
      }
      final chunk = queue.first;
      final remaining = chunk.dueUs - clock.elapsedMicroseconds;
      if (remaining > 0) {
        await cancellation.delay(Duration(microseconds: remaining));
      }
      if (cancellation.stopped) break;
      await rate.take(chunk.bytes.length, cancellation);
      if (cancellation.stopped) break;
      sink.add(chunk.bytes);
      await cancellation.wait(sink.flush());
      if (cancellation.stopped) break;
      // Count the in-flight chunk until the socket actually accepts it. Reading
      // must not resume just because bytes moved to an unbounded IOSink buffer.
      queue.removeFirst();
      pending -= chunk.bytes.length;
      if (paused && pending <= _Direction.lowWaterBytes) {
        paused = false;
        subscription.resume();
      }
    }
    if (readError != null && !cancellation.stopped) throw readError!;
    if (!cancellation.stopped) await cancellation.wait(sink.close());
  } finally {
    await subscription.cancel();
    queue.clear();
  }
}

class _Cancellation {
  final done = Completer<void>();
  final _waiters = <Completer<void>>{};
  bool get stopped => done.isCompleted;
  void cancel() {
    if (stopped) return;
    done.complete();
    for (final waiter in _waiters.toList()) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Future<void> wait(Future<void> operation) async {
    if (stopped) return;
    final ready = Completer<void>();
    _waiters.add(ready);
    operation.then(
      (_) {
        if (!ready.isCompleted) ready.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    try {
      await ready.future;
    } finally {
      _waiters.remove(ready);
    }
  }

  Future<void> delay(Duration duration) async {
    if (stopped) return;
    final elapsed = Completer<void>();
    final timer = Timer(duration, elapsed.complete);
    try {
      await wait(elapsed.future);
    } finally {
      timer.cancel();
    }
  }
}

Future<void> main(List<String> arguments) async {
  final proxy = await WeakNetworkProxy.start(
    listenPort: _positiveEnv('CONNECT_PROXY_LISTEN_PORT', 15557),
    upstreamHost:
        Platform.environment['CONNECT_PROXY_UPSTREAM_HOST'] ?? '127.0.0.1',
    upstreamPort: _positiveEnv('CONNECT_PROXY_UPSTREAM_PORT', 15556),
    uploadDelay: Duration(
      milliseconds: _nonNegativeEnv('CONNECT_PROXY_UP_DELAY_MS', 0),
    ),
    downloadDelay: Duration(
      milliseconds: _nonNegativeEnv('CONNECT_PROXY_DOWN_DELAY_MS', 0),
    ),
    uploadBytesPerSecond: _nonNegativeEnv('CONNECT_PROXY_UP_BPS', 0),
    downloadBytesPerSecond: _nonNegativeEnv('CONNECT_PROXY_DOWN_BPS', 0),
    log: stdout.writeln,
  );
  final signals = [
    ProcessSignal.sigint.watch().listen((_) => unawaited(proxy.close())),
    if (!Platform.isWindows)
      ProcessSignal.sigterm.watch().listen((_) => unawaited(proxy.close())),
  ];
  try {
    await proxy.done;
  } finally {
    await proxy.close();
    await Future.wait(signals.map((subscription) => subscription.cancel()));
  }
}

final class _Direction {
  const _Direction({
    required this.label,
    required this.delay,
    required this.rate,
  });

  static const highWaterBytes = 256 * 1024;
  static const lowWaterBytes = 64 * 1024;

  final String label;
  final Duration delay;
  final int rate;

  String describe() =>
      'delay=${delay.inMilliseconds}ms rate=${rate == 0 ? 'unlimited' : '$rate bps'}';
}

final class _Chunk {
  const _Chunk(this.bytes, this.dueUs);
  final List<int> bytes;
  final int dueUs;
}

final class _TokenBucket {
  _TokenBucket(this.bytesPerSecond);

  final int bytesPerSecond;
  final _clock = Stopwatch()..start();
  double _tokens = 0;
  int _lastUs = 0;

  Future<void> take(int bytes, _Cancellation cancellation) async {
    if (bytesPerSecond == 0) return;
    final capacity = math.max(
      bytes.toDouble(),
      math.max(4096.0, bytesPerSecond * .05),
    );
    while (!cancellation.stopped) {
      final now = _clock.elapsedMicroseconds;
      final elapsed = now - _lastUs;
      _lastUs = now;
      _tokens = math.min(
        capacity,
        _tokens + elapsed * bytesPerSecond / Duration.microsecondsPerSecond,
      );
      if (_tokens >= bytes) {
        _tokens -= bytes;
        return;
      }
      final micros =
          ((bytes - _tokens) * Duration.microsecondsPerSecond / bytesPerSecond)
              .ceil();
      await cancellation.delay(Duration(microseconds: math.max(100, micros)));
    }
  }
}

final class _Signal {
  Completer<void>? _pending;

  Future<void> get next {
    final pending = _pending;
    if (pending != null) return pending.future;
    final created = Completer<void>();
    _pending = created;
    return created.future;
  }

  void signal() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }
}

int _positiveEnv(String name, int fallback) {
  final value = _nonNegativeEnv(name, fallback);
  if (value == 0) throw ArgumentError.value(value, name, 'must be positive');
  return value;
}

int _nonNegativeEnv(String name, int fallback) {
  final text = Platform.environment[name];
  if (text == null || text.isEmpty) return fallback;
  final value = int.tryParse(text);
  if (value == null || value < 0) {
    throw ArgumentError.value(text, name, 'must be a non-negative integer');
  }
  return value;
}
