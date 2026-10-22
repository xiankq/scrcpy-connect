import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

/// Deterministic loopback proxy for ADB/media weak-network experiments.
///
/// It accepts ordinary TCP, applies an independent one-way delay and token
/// bucket to each direction, and stops reading a source while its pending
/// queue is high. The latter preserves real TCP backpressure instead of
/// silently accumulating an unbounded proxy queue.
Future<void> main(List<String> arguments) async {
  final listenPort = _positiveEnv('CONNECT_PROXY_LISTEN_PORT', 15557);
  final upstreamHost =
      Platform.environment['CONNECT_PROXY_UPSTREAM_HOST'] ?? '127.0.0.1';
  final upstreamPort = _positiveEnv('CONNECT_PROXY_UPSTREAM_PORT', 15556);
  final upload = _Direction(
    label: 'upload',
    delay: Duration(
      milliseconds: _nonNegativeEnv('CONNECT_PROXY_UP_DELAY_MS', 0),
    ),
    rate: _nonNegativeEnv('CONNECT_PROXY_UP_BPS', 0),
  );
  final download = _Direction(
    label: 'download',
    delay: Duration(
      milliseconds: _nonNegativeEnv('CONNECT_PROXY_DOWN_DELAY_MS', 0),
    ),
    rate: _nonNegativeEnv('CONNECT_PROXY_DOWN_BPS', 0),
  );
  final server = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    listenPort,
  );
  stdout.writeln(
    'weak-network proxy listening=$listenPort upstream=$upstreamHost:$upstreamPort '
    'upload=${upload.describe()} download=${download.describe()}',
  );
  var connection = 0;
  await for (final client in server) {
    connection++;
    unawaited(
      _serve(client, upstreamHost, upstreamPort, upload, download, connection),
    );
  }
}

Future<void> _serve(
  Socket client,
  String upstreamHost,
  int upstreamPort,
  _Direction upload,
  _Direction download,
  int connection,
) async {
  Socket? upstream;
  final started = Stopwatch()..start();
  try {
    client.setOption(SocketOption.tcpNoDelay, true);
    upstream = await Socket.connect(upstreamHost, upstreamPort);
    upstream.setOption(SocketOption.tcpNoDelay, true);
    await Future.any([
      _pump(client, upstream, upload),
      _pump(upstream, client, download),
    ]);
  } catch (error) {
    stderr.writeln('weak-network proxy connection=$connection failed: $error');
  } finally {
    client.destroy();
    upstream?.destroy();
    stdout.writeln(
      'weak-network proxy connection=$connection closed '
      'afterMs=${started.elapsedMilliseconds}',
    );
  }
}

Future<void> _pump(Socket source, Socket sink, _Direction direction) async {
  final queue = Queue<_Chunk>();
  final available = _Signal();
  final rate = _TokenBucket(direction.rate);
  late final StreamSubscription<List<int>> subscription;
  var pending = 0;
  var paused = false;
  var done = false;

  subscription = source.listen(
    (bytes) {
      if (bytes.isEmpty) return;
      queue.add(
        _Chunk(
          bytes,
          DateTime.now().add(direction.delay).microsecondsSinceEpoch,
        ),
      );
      pending += bytes.length;
      if (!paused && pending >= _Direction.highWaterBytes) {
        paused = true;
        subscription.pause();
      }
      available.signal();
    },
    onError: (Object error, StackTrace stack) {
      done = true;
      available.signal();
      stderr.writeln('weak-network proxy ${direction.label} read: $error');
    },
    onDone: () {
      done = true;
      available.signal();
    },
    cancelOnError: true,
  );

  try {
    while (!done || queue.isNotEmpty) {
      if (queue.isEmpty) {
        await available.next;
        continue;
      }
      final chunk = queue.first;
      final now = DateTime.now().microsecondsSinceEpoch;
      if (chunk.dueUs > now) {
        await Future<void>.delayed(
          Duration(microseconds: math.min(chunk.dueUs - now, 20000)),
        );
        continue;
      }
      await rate.take(chunk.bytes.length);
      sink.add(chunk.bytes);
      queue.removeFirst();
      pending -= chunk.bytes.length;
      if (paused && pending <= _Direction.lowWaterBytes) {
        paused = false;
        subscription.resume();
      }
      available.signal();
    }
  } finally {
    await subscription.cancel();
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

  Future<void> take(int bytes) async {
    if (bytesPerSecond == 0) return;
    final capacity = math.max(
      bytes.toDouble(),
      math.max(4096.0, bytesPerSecond * .05),
    );
    while (true) {
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
      await Future<void>.delayed(Duration(microseconds: math.max(100, micros)));
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
