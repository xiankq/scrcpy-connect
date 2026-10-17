import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/interop_exception.dart';
import 'package:interop_bridge/src/media/portable_video.dart';

final _token = List.filled(64, 'a').join();
VideoJson _stream(String id, {String device = 'device-A'}) => {
  'sessionId': id,
  'deviceId': device,
  'videoPort': 2345,
  'videoToken': _token,
  'codec': 'h264',
  'width': 1080,
  'height': 2400,
};
VideoJson _endpoint(String id, {int generation = 1}) => {
  'relayId': id,
  'generation': generation,
  'url': 'http://127.0.0.1:1234/$_token',
};
Matcher _code(String code) =>
    isA<InteropException>().having((e) => e.code, 'code', code);

class _Player implements VideoPlayerPort {
  final changes = StreamController<VideoJson>.broadcast(sync: true);
  final calls = <String>[];
  Completer<VideoTexture>? opening;
  Completer<void>? presentation;
  Completer<VideoPixels?>? pixels;
  bool nullFrame = false;
  bool startupDiagnostics = false;
  int texture = 7, released = 0;
  @override
  Stream<VideoJson> get events => changes.stream;
  @override
  Future<VideoTexture> open(String url) async {
    calls.add('open');
    if (startupDiagnostics) {
      changes.add({
        'kind': 'diagnostic',
        'category': 'video.prepare',
        'elapsedMs': 12,
      });
      changes.add({
        'kind': 'diagnostic',
        'category': 'video.texture',
        'elapsedMs': 17,
      });
      // Other diagnostics may have absent or nonnumeric elapsed values.
      changes.add({
        'kind': 'diagnostic',
        'category': 'video.prepare',
        'elapsedMs': 'unknown',
      });
    }
    return opening == null ? VideoTexture(texture, 720, 1280) : opening!.future;
  }

  @override
  Future<void> setPaused(bool paused) async {
    calls.add(paused ? 'pause' : 'play');
    await presentation?.future;
  }

  @override
  Future<VideoPixels?> snapshot({
    required int width,
    required int height,
  }) async {
    calls.add('snapshot:$width:$height');
    if (pixels != null) return pixels!.future;
    return nullFrame
        ? null
        : VideoPixels(
            width,
            height,
            Uint8List.fromList(List.filled(width * height * 4, 255)),
          );
  }

  @override
  Future<VideoJson> release() async {
    released++;
    calls.add('release');
    return {'disposeRequested': true, 'nativeDeleteConfirmed': false};
  }
}

class _Harness {
  _Harness({this.operationTimeout = const Duration(seconds: 6)});
  final Duration operationTimeout;
  final commands = <(String, VideoJson)>[];
  final events = <VideoJson>[];
  final players = <_Player>[];
  Completer<VideoJson>? opening;
  bool disposed = false;
  int relays = 0;
  late final output = PortableVideoOutputs(
    core: request,
    emit: events.add,
    isDisposed: () => disposed,
    operationTimeout: operationTimeout,
    playerFactory: () {
      final p = _Player()..texture = 7 + players.length;
      players.add(p);
      return p;
    },
  );
  Future<VideoJson> request(String command, VideoJson params) async {
    commands.add((command, {...params}));
    if (command == 'media.open') {
      return opening == null ? _endpoint('relay-${++relays}') : opening!.future;
    }
    if (command == 'media.close') return {'closed': true};
    if (command == 'session.refresh') return {'refreshRequested': true};
    throw StateError(
      'adapter must not create or stop a remote session: $command',
    );
  }

  List<String> get closed => commands
      .where((c) => c.$1 == 'media.close')
      .map((c) => c.$2['relayId'] as String)
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('startup timings preserve bounded player observations and actual frame verification', () async {
    final h = _Harness()..opening = Completer();
    final pending = h.output.start(_stream('timed'));
    h.players.single.startupDiagnostics = true;
    h.opening!.complete(_endpoint('timed'));
    final receipt = await pending;
    final timing = receipt['outputStartupTimingMs'] as Map;
    expect(timing['video.prepare'], 12);
    expect(timing['video.texture'], 17);
    expect(
      timing['verifiedFrameMs'],
      greaterThanOrEqualTo(timing['playingMs'] as int),
    );
    expect(h.players.single.calls.last, 'snapshot:32:32');
    expect(receipt['presentedToWidget'], false);
    await h.output.dispose();
  });
  test('first receipt requires actual pixels and never overwrites remote touch dimensions', () async {
    final h = _Harness();
    expect(
      (h.output.capabilities()['codecs'] as List).every(
        (dynamic e) => (e as Map)['available'] == null,
      ),
      true,
    );
    final receipt = await h.output.start(_stream('A'));
    expect(receipt['textureId'], 7);
    expect(receipt['decodedWidth'], 720);
    expect(receipt.containsKey('width'), false);
    expect(receipt.containsKey('height'), false);
    expect(receipt['firstFrameDecoded'], true);
    expect(receipt['presentedToWidget'], false);
    expect(receipt.containsKey('framesDecoded'), false);
    expect(h.players.single.calls, ['open', 'play', 'snapshot:32:32']);
    expect(h.events.single['type'], 'session.output.ready');
    expect(
      (h.output.capabilities()['codecs'] as List).first['available'],
      true,
    );
    await h.output.dispose();
  });

  test('a texture without a snapshot never becomes ready', () async {
    final h = _Harness();
    h.opening = Completer();
    final result = h.output.start(_stream('A'));
    h.players.single.nullFrame = true;
    h.opening!.complete(_endpoint('bad'));
    await expectLater(result, throwsA(_code('no_frame')));
    expect(h.events, isEmpty);
    expect(h.closed, ['bad']);
    expect(h.players.single.released, 1);
    await h.output.dispose();
  });

  test(
    'stop cancels an in-flight core open and closes only its late relay',
    () async {
      final h = _Harness();
      h.opening = Completer();
      final starting = h.output.start(_stream('A'));
      final failed = expectLater(starting, throwsA(_code('cancelled')));
      await h.output.stop('A');
      await failed;
      h.opening!.complete(_endpoint('late-A'));
      await Future<void>.delayed(Duration.zero);
      expect(h.closed, ['late-A']);
      expect(h.players.single.calls, ['release']);
      expect(h.events, isEmpty);
      await expectLater(
        h.output.start(_stream('A')),
        throwsA(_code('cancelled')),
      );
      await h.output.dispose();
    },
  );

  test('late player completion cannot publish a stopped texture or affect another session', () async {
    final h = _Harness();
    h.opening = Completer();
    final starting = h.output.start(_stream('A'));
    final old = h.players.single;
    old.opening = Completer();
    h.opening!.complete(_endpoint('A'));
    await Future<void>.delayed(Duration.zero);
    final failed = expectLater(starting, throwsA(_code('cancelled')));
    await h.output.stop('A');
    await failed;
    h.opening = null;
    await h.output.start(_stream('B', device: 'device-B'));
    old.opening!.complete(const VideoTexture(99, 720, 1280));
    await Future<void>.delayed(Duration.zero);
    expect(
      h.events.where((e) => (e['data'] as Map)['sessionId'] == 'A'),
      isEmpty,
    );
    expect(h.players.last.released, 0);
    expect(old.released, 1);
    await h.output.dispose();
  });

  test('duplicate attachment reuses the same entry and does not consume a new token', () async {
    final h = _Harness();
    final first = await h.output.start(_stream('A'));
    final second = await h.output.start(_stream('A'));
    expect(second, first);
    expect(h.players.length, 1);
    expect(h.commands.where((c) => c.$1 == 'media.open').length, 1);
    await h.output.dispose();
  });

  test('failed reconfiguration preserves old output and closes only candidate relay', () async {
    final h = _Harness();
    final first = await h.output.start(_stream('A'));
    final replacing = h.output.reattach(
      'A',
      endpoint: _endpoint('candidate', generation: 2),
    );
    h.players.last.nullFrame = true;
    await expectLater(replacing, throwsA(_code('no_frame')));
    expect(h.players.first.released, 0);
    expect(h.players.last.released, 1);
    expect(h.closed, ['candidate']);
    expect(await h.output.start(_stream('A')), first);
    await h.output.dispose();
  });

  test('successful reconfiguration preserves session ID and commits only verified replacement', () async {
    final h = _Harness();
    await h.output.start(_stream('A'));
    final replacing = h.output.reattach(
      'A',
      endpoint: {..._endpoint('candidate', generation: 2), 'codec': 'h265'},
    );
    h.players.last.texture = 8;
    final receipt = await replacing;
    expect(receipt['sessionId'], 'A');
    expect(receipt['generation'], 2);
    expect(receipt['textureId'], 8);
    expect(receipt['codec'], 'h265');
    expect(h.players.first.released, 1);
    expect(h.players.last.released, 0);
    expect(h.events.last['type'], 'session.output.changed');
    expect(h.closed, ['relay-1']);
    await expectLater(
      h.output.reattach('A', endpoint: _endpoint('older', generation: 1)),
      throwsA(_code('generation_changed')),
    );
    await h.output.dispose();
  });

  test('pause waits for confirmation and resume verifies a snapshot without fabricating frame events', () async {
    final h = _Harness();
    await h.output.start(_stream('A'));
    final player = h.players.single;
    player.presentation = Completer();
    var completed = false;
    final pausing = h.output.pause('A').then((r) {
      completed = true;
      return r;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    player.presentation!.complete();
    expect((await pausing)['applied'], true);
    player.presentation = null;
    final resumed = await h.output.resume('A');
    expect(resumed['snapshotReceipts'], 2);
    expect(h.events.any((event) => event['type'] == 'session.frame'), false);
    await h.output.dispose();
  });

  test('same relay survives failed generation and closes exactly once after commit', () async {
    final h = _Harness();
    await h.output.start(_stream('A'));
    final failed = h.output.reattach(
      'A',
      endpoint: _endpoint('relay-1', generation: 2),
    );
    h.players.last.nullFrame = true;
    await expectLater(failed, throwsA(_code('no_frame')));
    expect(h.closed, isEmpty);
    expect(h.players.first.released, 0);
    final replacement = await h.output.reattach(
      'A',
      endpoint: _endpoint('relay-1', generation: 3),
    );
    expect(replacement['generation'], 3);
    expect(h.closed, isEmpty);
    expect(h.players.first.released, 1);
    await h.output.stop('A');
    expect(h.closed, ['relay-1']);
    await h.output.dispose();
    expect(h.closed, ['relay-1']);
  });

  test('resume follows a replacement generation without pausing it or cancelling the session', () async {
    final h = _Harness();
    await h.output.start(_stream('A'));
    await h.output.pause('A');
    final old = h.players.single;
    old.presentation = Completer();
    final resuming = h.output.resume('A');
    // Attach a handler before replacement retires the in-flight old player.
    final resumed = expectLater(
      resuming,
      completion(containsPair('generation', 2)),
    );
    await Future<void>.delayed(Duration.zero);
    await h.output.reattach('A', endpoint: _endpoint('relay-1', generation: 2));
    await resumed;
    expect((await resuming)['paused'], false);
    expect(h.players.last.calls, isNot(contains('pause')));
    expect(h.closed, isEmpty);
    expect(old.released, 1);
    old.presentation!.complete();
    await h.output.dispose();
  });

  test(
    'pause follows replacement and a queued resume uses the surviving player',
    () async {
      final h = _Harness();
      await h.output.start(_stream('A'));
      final old = h.players.single;
      old.presentation = Completer();
      final pausing = h.output.pause('A');
      final paused = expectLater(
        pausing,
        completion(containsPair('generation', 2)),
      );
      await Future<void>.delayed(Duration.zero);
      final resuming = h.output.resume('A');
      final resumed = expectLater(
        resuming,
        completion(containsPair('paused', false)),
      );
      await h.output.reattach(
        'A',
        endpoint: _endpoint('relay-1', generation: 2),
      );
      await paused;
      await resumed;
      expect((await pausing)['paused'], true);
      expect(h.players.last.calls, contains('pause'));
      expect(h.closed, isEmpty);
      old.presentation!.complete();
      await h.output.dispose();
    },
  );

  test('stopping a pending shared relay generation cancels both players without double close', () async {
    final h = _Harness();
    await h.output.start(_stream('A'));
    final replacement = h.output.reattach(
      'A',
      endpoint: _endpoint('relay-1', generation: 2),
    );
    final candidate = h.players.last;
    // open has already been invoked, so hold the snapshot instead.
    candidate.pixels = Completer();
    final failed = expectLater(replacement, throwsA(_code('cancelled')));
    await Future<void>.delayed(Duration.zero);
    await h.output.stop('A');
    await failed;
    expect(h.closed, ['relay-1']);
    expect(h.players.every((player) => player.released == 1), true);
    candidate.pixels!.complete(null);
    await Future<void>.delayed(Duration.zero);
    expect(
      h.events.where((event) => event['type'] == 'session.output.changed'),
      isEmpty,
    );
    await h.output.dispose();
  });

  test(
    'timed out snapshot keeps its native slot occupied until actual completion',
    () async {
      final h = _Harness(operationTimeout: const Duration(milliseconds: 20));
      await h.output.start(_stream('A'));
      final player = h.players.single;
      final pending = Completer<VideoPixels?>();
      player.pixels = pending;
      await expectLater(h.output.resume('A'), throwsA(_code('video_timeout')));
      final calls = player.calls.length;
      await expectLater(h.output.resume('A'), throwsA(_code('renderer_busy')));
      expect(player.calls.skip(calls), ['play']);
      pending.complete(null);
      await Future<void>.delayed(Duration.zero);
      player.pixels = null;
      expect((await h.output.resume('A'))['snapshotReceipts'], 2);
      await h.output.dispose();
    },
  );

  test(
    'malformed late endpoint is rejected without an unhandled cleanup error',
    () async {
      final h = _Harness();
      h.opening = Completer();
      final starting = h.output.start(_stream('A'));
      final failure = expectLater(starting, throwsA(_code('cancelled')));
      await h.output.stop('A');
      await failure;
      h.opening!.complete({'relayId': 42});
      await Future<void>.delayed(Duration.zero);
      expect(h.closed, isEmpty);
      await h.output.dispose();
    },
  );

  test('stopDevice affects only exact device ownership and stale failure events are ignored', () async {
    final h = _Harness();
    await h.output.start(_stream('A'));
    await h.output.start(_stream('B', device: 'device-B'));
    await h.output.stopDevice('device-A');
    expect(h.players.first.released, 1);
    expect(h.players.last.released, 0);
    h.players.first.changes.add({'kind': 'failed', 'reason': 'late'});
    expect(
      h.events.where((event) => event['type'] == 'session.output.failed'),
      isEmpty,
    );
    await h.output.dispose();
  });

  test(
    'owner disposal and bounded startup timeouts prevent late publication',
    () async {
      final pending = Completer<VideoJson>();
      final closed = <String>[];
      final player = _Player();
      final output = PortableVideoOutputs(
        core: (command, params) async {
          if (command == 'media.open') return pending.future;
          closed.add(params['relayId'] as String);
          return {};
        },
        emit: (_) => fail('timed out output emitted ready'),
        isDisposed: () => false,
        playerFactory: () => player,
        startTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        output.start(_stream('A')),
        throwsA(_code('video_timeout')),
      );
      pending.complete(_endpoint('late-timeout'));
      await Future<void>.delayed(Duration.zero);
      expect(closed, ['late-timeout']);
      expect(player.released, 1);
      await output.dispose();
    },
  );

  test('only a loopback capability URL may reach the player', () async {
    final h = _Harness();
    h.opening = Completer();
    final starting = h.output.start(_stream('A'));
    h.opening!.complete({
      ..._endpoint('bad'),
      'url': 'https://example.com/$_token',
    });
    await expectLater(starting, throwsA(_code('invalid_endpoint')));
    expect(h.players.single.calls, ['release']);
    expect(h.closed, ['bad']);
    await h.output.dispose();
  });

  test('screenshot is an actual PNG in a fresh owned directory and preserves existing files', () async {
    final h = _Harness();
    await h.output.start(_stream('A'));
    final root = await Directory.systemTemp.createTemp('portable-video-test-');
    try {
      final keep = File('${root.path}/frame.png');
      await keep.writeAsString('existing');
      final receipt = await h.output.screenshot('A', directory: root.path);
      final file = File(receipt['localPath'] as String);
      final bytes = await file.readAsBytes();
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(receipt['sessionId'], 'A');
      expect(receipt['width'], 720);
      expect(await keep.readAsString(), 'existing');
    } finally {
      await h.output.dispose();
      await root.delete(recursive: true);
    }
  });
}
