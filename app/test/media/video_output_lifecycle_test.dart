import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/stores/media/video_output_coordinator.dart';
import 'package:scrcpy_connect/stores/media/video_output_lifecycle.dart';
import 'package:scrcpy_connect/services/media/video_player_port.dart';

final _token = List.filled(64, 'a').join();

VideoJson _stream(String id) => {
  'sessionId': id,
  'deviceId': 'device-A',
  'videoSourceId': _token,
  'codec': 'h264',
};

VideoJson _endpoint(String relay, int generation) => {
  'relayId': relay,
  'generation': generation,
  'sourceId': _token,
  'container': 'packet',
  'kind': 'video',
  'codec': 'h264',
  'attachAddress': 4096,
  'detachAddress': 8192,
};

class _Player implements VideoPlayerPort {
  final changes = StreamController<VideoJson>.broadcast(sync: true);
  Completer<void>? releasing;
  int releases = 0;

  @override
  Stream<VideoJson> get events => changes.stream;

  @override
  Future<VideoTexture> open(VideoJson source) async =>
      const VideoTexture(7, 16, 16);

  @override
  Future<void> setPaused(bool paused) async {}

  @override
  Future<VideoPixels?> snapshot({
    required int width,
    required int height,
  }) async => null;

  @override
  Future<VideoJson> release() async {
    releases++;
    await releasing?.future;
    return {'disposeRequested': true, 'nativeDeleteConfirmed': true};
  }

  void fail() => changes.add({'kind': 'failed', 'reason': 'decoder lost'});
}

class _Harness {
  final receipts = <String, VideoJson>{};
  final events = <VideoJson>[];
  final commands = <(String, VideoJson)>[];
  final players = <_Player>[];
  VideoJson status = {'status': 'streaming'};
  Completer<VideoJson>? statusReading;
  Completer<VideoJson>? stopping;
  int relay = 0;

  late final VideoOutputLifecycle lifecycle = VideoOutputLifecycle(
    outputs: receipts,
    request: request,
    closeOutput: close,
    reattachOutput: (id, endpoint) => outputs.reattach(id, endpoint: endpoint),
    emit: events.add,
    isDisposed: () => false,
  );
  late final VideoOutputCoordinator outputs = VideoOutputCoordinator(
    request: request,
    emit: lifecycle.handle,
    isDisposed: () => false,
    playerFactory: () {
      final player = _Player();
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
    if (command == 'session.frame') return {'received': true};
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
  test('failed renderer replacement retains window for retry', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.start('A');
    h.lifecycle.beginReconfigure('A');
    h.lifecycle.retainFailedOutput('A');
    h.lifecycle.endReconfigure('A');
    h.players.single.fail();
    h.status = {'status': 'closed'};
    await h.lifecycle.poll('A', current: () => true);
    expect(h.stopped, isEmpty);
    expect(h.receipts.keys, ['A']);
    h.lifecycle.beginReconfigure('A');
    await h.outputs.reattach('A', endpoint: _endpoint('relay-2', 2));
    h.lifecycle.endReconfigure('A');
    expect(h.receipts['A']?['generation'], 2);
  });

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
    expect(h.closed, isEmpty);
    expect(h.stopped, ['A']);
  });
}
