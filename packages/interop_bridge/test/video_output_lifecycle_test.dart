import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/media/portable_video.dart';
import 'package:interop_bridge/src/media/video_output_lifecycle.dart';

final _token = List.filled(64, 'a').join();

VideoJson _stream(String id) => {
  'sessionId': id,
  'deviceId': 'device-A',
  'videoPort': 2345,
  'videoToken': _token,
  'codec': 'h264',
};

VideoJson _endpoint(String relay, int generation) => {
  'relayId': relay,
  'generation': generation,
  'url': 'http://127.0.0.1:1234/$_token',
};

class _Player implements VideoPlayerPort {
  final changes = StreamController<VideoJson>.broadcast(sync: true);
  final playing = Completer<void>();
  Completer<void>? presentation, releasing;
  int releases = 0;

  @override
  Stream<VideoJson> get events => changes.stream;

  @override
  Future<VideoTexture> open(String url) async => const VideoTexture(7, 16, 16);

  @override
  Future<void> setPaused(
    bool paused, {
    Future<void> Function()? onRequested,
  }) async {
    if (!playing.isCompleted) playing.complete();
    await onRequested?.call();
    await presentation?.future;
  }

  @override
  Future<VideoPixels?> snapshot({
    required int width,
    required int height,
  }) async => VideoPixels(
    width,
    height,
    Uint8List.fromList(List.filled(width * height * 4, 255)),
  );

  @override
  Future<VideoJson> release() async {
    releases++;
    await releasing?.future;
    return {'disposeRequested': true, 'nativeDeleteConfirmed': false};
  }

  void fail() => changes.add({'kind': 'failed', 'reason': 'decoder lost'});
}

class _Harness {
  final receipts = <String, VideoJson>{};
  final events = <VideoJson>[];
  final commands = <(String, VideoJson)>[];
  final players = <_Player>[];
  final held = <VideoJson>[];
  bool holdFailures = false;
  VideoJson status = {'status': 'streaming'};
  Completer<VideoJson>? statusReading;
  Completer<VideoJson>? stopping;
  Completer<void>? nextPresentation;
  int relay = 0;

  late final VideoOutputLifecycle lifecycle = VideoOutputLifecycle(
    outputs: receipts,
    core: request,
    closeOutput: close,
    reattachOutput: (id, endpoint) => outputs.reattach(id, endpoint: endpoint),
    emit: events.add,
    isDisposed: () => false,
  );
  late final PortableVideoOutputs outputs = PortableVideoOutputs(
    core: request,
    emit: (event) {
      if (holdFailures && event['type'] == 'session.output.failed') {
        held.add(event);
      } else {
        lifecycle.handle(event);
      }
    },
    isDisposed: () => false,
    playerFactory: () {
      final player = _Player()..presentation = nextPresentation;
      nextPresentation = null;
      players.add(player);
      return player;
    },
  );

  Future<VideoJson> request(String command, VideoJson params) async {
    commands.add((command, {...params}));
    if (command == 'media.open') return _endpoint('relay-${++relay}', 1);
    if (command == 'media.status') {
      return statusReading == null ? status : statusReading!.future;
    }
    if (command == 'session.stop') {
      return stopping == null ? {'stopped': true} : stopping!.future;
    }
    if (command == 'session.ready') return {'status': 'connected'};
    if (command == 'media.close') return {'closed': true};
    throw StateError('Unexpected command: $command');
  }

  Future<void> start(String id) async {
    receipts[id] = await outputs.start(_stream(id));
  }

  Future<void> close(String id) async {
    receipts.remove(id);
    await outputs.stop(id);
  }

  List<VideoJson> get failures =>
      events.where((e) => e['type'] == 'session.failed').toList();
  List<String> get stopped => commands
      .where((c) => c.$1 == 'session.stop')
      .map((c) => c.$2['sessionId'] as String)
      .toList();
  List<String> get closed => commands
      .where((c) => c.$1 == 'media.close')
      .map((c) => c.$2['relayId'] as String)
      .toList();

  Future<void> dispose() async {
    if (stopping case final pending? when !pending.isCompleted) {
      pending.complete({'stopped': true});
    }
    for (final player in players) {
      if (player.releasing case final pending? when !pending.isCompleted) {
        pending.complete();
      }
    }
    await outputs.dispose();
    for (final player in players) {
      await player.changes.close();
    }
  }
}

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'opened player failure stops the committed session even while HTTP streams',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.start('A');
      expect(
        (await h.request('media.status', {'relayId': 'relay-1'}))['status'],
        'streaming',
      );

      h.players.single.fail();
      await _flush();

      expect(h.failures, hasLength(1));
      expect(h.failures.single['deviceId'], 'device-A');
      expect(h.failures.single['data'], containsPair('reason', 'decoder lost'));
      expect(h.stopped, ['A']);
      expect(h.receipts, isEmpty);
      expect(h.players.single.releases, 1);
      expect(h.closed, ['relay-1']);
    },
  );

  test('an uncommitted candidate failure preserves the prior output', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.start('A');
    final prior = h.receipts['A'];
    final old = h.players.single;
    final presenting = Completer<void>();
    h.nextPresentation = presenting;
    final replacement = h.outputs.reattach(
      'A',
      endpoint: _endpoint('relay-2', 2),
    );
    final failed = expectLater(replacement, throwsA(anything));
    final candidate = h.players.last;
    await candidate.playing.future;

    candidate.fail();
    await _flush();
    expect(
      h.events.where((e) => e['type'] == 'session.output.failed'),
      hasLength(1),
    );
    expect(h.failures, isEmpty);
    expect(h.stopped, isEmpty);
    expect(h.receipts['A'], same(prior));
    expect(old.releases, 0);

    presenting.completeError(StateError('candidate failed'));
    await failed;
    expect(candidate.releases, 1);
    expect(h.closed, ['relay-2']);
  });

  test(
    'a delayed old generation failure cannot stop its committed replacement',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.start('A');
      h.holdFailures = true;
      h.players.single.fail();
      expect(h.held, hasLength(1));

      await h.outputs.reattach('A', endpoint: _endpoint('relay-2', 2));
      expect(h.receipts['A']?['generation'], 2);
      h.lifecycle.handle(h.held.single);
      await _flush();

      expect(h.failures, isEmpty);
      expect(h.stopped, isEmpty);
      expect(h.players.last.releases, 0);
      expect(h.receipts['A']?['generation'], 2);
    },
  );

  test('a stale relay failure cannot close a committed replacement', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.start('A');
    h.statusReading = Completer();
    final polling = h.lifecycle.poll('A', current: () => true);
    await h.outputs.reattach('A', endpoint: _endpoint('relay-2', 2));

    h.statusReading!.complete({
      'status': 'closed',
      'reason': 'old relay closed',
    });
    await polling;

    expect(h.failures, isEmpty);
    expect(h.stopped, isEmpty);
    expect(h.players.last.releases, 0);
    expect(h.receipts['A']?['relayId'], 'relay-2');
  });

  test('a merged receipt retains ownership of its relay failure', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.start('A');
    final polled = h.receipts['A']!;
    h.receipts['A'] = {...polled, 'status': 'paused'};

    await h.lifecycle.fail(polled, 'relay closed');

    expect(h.failures, hasLength(1));
    expect(h.stopped, ['A']);
    expect(h.players.single.releases, 1);
  });

  test(
    'overlapping relay failure reports stop and release their output once',
    () async {
      final h = _Harness()..stopping = Completer();
      addTearDown(h.dispose);
      await h.start('A');
      final polled = h.receipts['A']!;
      final first = h.lifecycle.fail(polled, 'relay closed');
      final second = h.lifecycle.fail({...polled}, 'relay closed');

      expect(h.stopped, ['A']);
      expect(h.failures, hasLength(1));
      h.stopping!.complete({'stopped': true});
      await Future.wait([first, second]);
      expect(h.players.single.releases, 1);
    },
  );

  test('failure retires its output before stop completes and leaves a reopened session alone', () async {
    final h = _Harness()..stopping = Completer();
    addTearDown(h.dispose);
    await h.start('A');
    final old = h.players.single..releasing = Completer<void>();

    old.fail();
    old.fail();
    await _flush();
    expect(h.stopped, ['A']);
    expect(h.failures, hasLength(1));
    expect(old.releases, 1);
    expect(h.receipts.containsKey('A'), false);

    await h.start('B');
    h.stopping!.complete({'stopped': true});
    old.releasing!.complete();
    await _flush();
    expect(h.receipts.keys, ['B']);
    expect(h.players.last.releases, 0);
    expect(h.closed, ['relay-1']);
    expect(h.stopped, ['A']);
  });
}
