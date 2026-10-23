import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtime_diagnostics/runtime_diagnostics.dart';
import 'package:device_protocol/device_protocol.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

final _token = List.filled(64, 'a').join();
VideoJson _stream(String id, {String device = 'device-A'}) => {
  'sessionId': id,
  'deviceId': device,
  'videoSourceId': _token,
  'codec': 'h264',
  'width': 1080,
  'height': 2400,
};
VideoJson _endpoint(String id, {int generation = 1}) => {
  'relayId': id,
  'generation': generation,
  'sourceId': _token,
  'container': 'packet',
  'kind': 'video',
  'codec': 'h264',
  'width': 1080,
  'height': 2400,
  'attachAddress': 4096,
  'detachAddress': 8192,
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
  int texture = 7, released = 0;
  @override
  Stream<VideoJson> get events => changes.stream;
  @override
  Future<VideoTexture> open(VideoJson source) async {
    calls.add('open');
    await Future<void>.delayed(Duration.zero);
    if (nullFrame) throw const InteropException('no_frame', 'No decoded frame');
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
  _Harness({
    this.diagnostics,
    this.operationTimeout = const Duration(seconds: 6),
  });
  final Duration operationTimeout;
  final DiagnosticLog? diagnostics;
  final commands = <(String, VideoJson)>[];
  final events = <VideoJson>[];
  final players = <_Player>[];
  Completer<VideoJson>? opening;
  bool disposed = false;
  int relays = 0;
  late final output = PortableVideoOutputs(
    diagnostics: diagnostics,
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
      return opening == null
          ? _endpoint(
              'relay-${++relays}',
              generation: params['generation'] as int? ?? 1,
            )
          : opening!.future;
    }
    if (command == 'media.close') return {'closed': true};
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
  test(
    'remote failure while opening preserves its cause through teardown',
    () async {
      final h = _Harness()..opening = Completer();
      final starting = h.output.start(_stream('A'));
      final failure = expectLater(starting, throwsA(_code('control_closed')));
      await h.output.stop(
        'A',
        failure: const InteropException('control_closed', '控制连接意外结束。'),
      );
      await failure;
      h.opening!.complete(_endpoint('late-A'));
      await Future<void>.delayed(Duration.zero);
      expect(h.closed, ['late-A']);
      expect(h.players.single.released, 1);
      await h.output.dispose();
    },
  );

  test(
    'late native creation failure remains diagnosable after input detaches',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'native-create-log-',
      );
      final log = await DiagnosticLog.open(directory);
      final h = _Harness(diagnostics: log)..opening = Completer();
      try {
        final starting = h.output.start(_stream('A'));
        final player = h.players.single..opening = Completer();
        h.opening!.complete(_endpoint('A'));
        while (!player.calls.contains('open')) {
          await Future<void>.delayed(Duration.zero);
        }
        await Future<void>.delayed(Duration.zero);
        final failed = expectLater(starting, throwsA(_code('cancelled')));
        await h.output.stop('A');
        await failed;
        player.opening!.completeError(
          PlatformException(
            code: 'media_codec_create',
            message: 'private-native-message',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        final cause = log.recent.lastWhere(
          (r) => r.fields['stage'] == 'video_open',
        );
        expect(cause.fields['code'], 'media_codec_create');
        expect(
          utf8.decode(await log.export()),
          isNot(contains('private-native-message')),
        );
      } finally {
        await h.output.dispose();
        await log.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'production observer records decoder changes and ignores disposed output',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'connect-player-log-',
      );
      final log = await DiagnosticLog.open(directory);
      final h = _Harness(diagnostics: log);
      try {
        await h.output.start(_stream('A'));
        h.players.first.changes.add({
          'kind': 'diagnostic',
          'category': 'decoder.video',
          'detail': 'FFmpeg',
          'error': 0,
          'decoderName': 'h264/vaapi',
          'hardwareAccelerated': true,
        });
        expect(
          log.recent
              .where((r) => r.event == 'decoder.selected')
              .single
              .fields['decoder'],
          'h264',
        );
        expect(log.recent.single.fields['decoderBackend'], 'vaapi');
        final output = await h.output.resume('A');
        final session = sessionWithVideoOutput({'sessionId': 'A'}, output);
        expect(session['decoderName'], 'h264/vaapi');
        expect(session['hardwareAccelerated'], true);
        await h.output.dispose();
        h.players.first.changes.add({
          'kind': 'diagnostic',
          'category': 'decoder.video',
          'detail': 'AMediaCodec',
          'error': 0,
        });
        expect(
          log.recent.where((r) => r.event == 'decoder.selected'),
          hasLength(1),
        );
        expect(log.recent.last.event, 'output.released');
      } finally {
        await h.output.dispose();
        await log.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'decoded resize preserves paused state and ignores retired player events',
    () async {
      final h = _Harness();
      addTearDown(h.output.dispose);
      await h.output.start({..._stream('A'), 'captureGeneration': 1});
      await h.output.pause('A');
      final old = h.players.single;
      VideoJson resize(int generation, int texture, int frameCount) => {
        'kind': 'metadata',
        'category': 'video.dimensions',
        'generation': generation,
        'textureId': texture,
        'width': 1280,
        'height': 720,
        'frameCount': frameCount,
      };
      old.changes.add(resize(1, 7, 2));
      final receipt =
          h.events.singleWhere(
                (event) => event['type'] == 'session.frame',
              )['data']
              as VideoJson;
      expect(receipt, containsPair('paused', true));
      expect(receipt, containsPair('captureGeneration', 1));
      expect(receipt, containsPair('decodedWidth', 1280));
      expect(receipt, containsPair('decodedHeight', 720));
      expect(receipt, containsPair('frameCount', 2));
      old.changes.add(resize(1, 7, 3));
      old.changes.add({...resize(1, 7, 1), 'width': 720, 'height': 1280});
      expect(h.events.where((e) => e['type'] == 'session.frame'), hasLength(1));

      final current = await h.output.reattach(
        'A',
        endpoint: _endpoint('relay-1', generation: 2),
      );
      expect(current['paused'], true);
      old.changes.add(resize(1, 7, 99));
      h.players.last.changes.add(resize(1, 8, 2));
      expect(h.events.where((e) => e['type'] == 'session.frame'), hasLength(1));
      h.players.last.changes.add(resize(2, 8, 2));
      final changes = h.events.where((e) => e['type'] == 'session.frame');
      expect(changes, hasLength(2));
      expect(changes.last['data'], containsPair('generation', 2));
      expect(changes.last['data'], containsPair('paused', true));
    },
  );
  test(
    'renderer resize generations stay independent of capture rebuilds',
    () async {
      final h = _Harness();
      addTearDown(h.output.dispose);
      await h.output.start({..._stream('A'), 'captureGeneration': 1});
      final resized = await h.output.reattach(
        'A',
        endpoint: _endpoint('relay-1', generation: 6),
      );
      expect(resized['captureGeneration'], 1);
      final rebuilt = await h.output.reconfigure({
        ..._stream('A'),
        'generation': 2,
        'captureGeneration': 2,
      });
      expect(rebuilt['generation'], 7);
      expect(rebuilt['captureGeneration'], 2);
      final again = await h.output.reattach(
        'A',
        endpoint: _endpoint(rebuilt['relayId'] as String, generation: 8),
      );
      expect(again['generation'], 8);
      expect(again['captureGeneration'], 2);
    },
  );

  test(
    'reconfigure consumes new input and keeps logical paused output',
    () async {
      final h = _Harness();
      addTearDown(h.output.dispose);
      await h.output.start(_stream('A'));
      await h.output.pause('A');
      final rebuilt = await h.output.reconfigure({
        ..._stream('A'),
        'generation': 2,
      });
      expect(rebuilt['generation'], 2);
      expect(rebuilt['sessionId'], 'A');
      expect(h.players.first.released, 1);
      expect(h.players.last.calls, contains('pause'));
      expect(h.commands.where((call) => call.$1 == 'media.open'), hasLength(2));
    },
  );

  test('close beats a late one-use replacement relay', () async {
    final h = _Harness();
    addTearDown(h.output.dispose);
    await h.output.start(_stream('A'));
    h.opening = Completer();
    final replacement = h.output.reconfigure({
      ..._stream('A'),
      'generation': 2,
    });
    final rejected = expectLater(replacement, throwsA(_code('cancelled')));
    await h.output.stop('A');
    h.opening!.complete(_endpoint('late-relay', generation: 2));
    await rejected;
    expect(
      h.commands
          .where((call) => call.$1 == 'media.close')
          .map((call) => call.$2['relayId']),
      contains('late-relay'),
    );
    expect(h.players, hasLength(1));
  });
  test('first receipt requires decoding without a GPU readback or remote dimension changes', () async {
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
    expect(receipt['decodedReceipts'], 1);
    expect(receipt['snapshotReceipts'], 0);
    expect(h.players.single.calls, ['open', 'play']);
    expect(h.events.single['type'], 'session.output.ready');
    expect(
      (h.output.capabilities()['codecs'] as List).first['available'],
      true,
    );
    await h.output.dispose();
  });

  test('failed first decode never becomes ready', () async {
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

  test('pause waits for confirmation and resume verifies decoding without readback', () async {
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
    expect(resumed['decodedReceipts'], 2);
    expect(resumed['snapshotReceipts'], 0);
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
    // Hold the first decoded frame before committing this generation.
    candidate.opening = Completer();
    final failed = expectLater(replacement, throwsA(_code('cancelled')));
    await Future<void>.delayed(Duration.zero);
    await h.output.stop('A');
    await failed;
    expect(h.closed, ['relay-1']);
    expect(h.players.every((player) => player.released == 1), true);
    candidate.opening!.complete(const VideoTexture(8, 720, 1280));
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
      final directory = await Directory.systemTemp.createTemp('snapshot-slot-');
      try {
        await expectLater(
          h.output.screenshot('A', directory: directory.path),
          throwsA(_code('video_timeout')),
        );
        final calls = player.calls.length;
        await expectLater(
          h.output.screenshot('A', directory: directory.path),
          throwsA(_code('renderer_busy')),
        );
        expect(player.calls.length, calls);
        pending.complete(null);
        await Future<void>.delayed(Duration.zero);
        player.pixels = null;
        // Readback ownership has returned; a new request reaches the player.
        // Return null to avoid making PNG encoding speed part of this timeout test.
        player.nullFrame = true;
        await expectLater(
          h.output.screenshot('A', directory: directory.path),
          throwsA(_code('capture_failed')),
        );
        expect(player.calls.length, calls + 1);
      } finally {
        if (!pending.isCompleted) pending.complete(null);
        await h.output.dispose();
        await directory.delete(recursive: true);
      }
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

  test('an invalid native packet endpoint never reaches the player', () async {
    final h = _Harness();
    h.opening = Completer();
    final starting = h.output.start(_stream('A'));
    h.opening!.complete({..._endpoint('bad'), 'attachAddress': 0});
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
