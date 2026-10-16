import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/interop_exception.dart';
import 'package:interop_bridge/src/media/portable_audio.dart';

final _token = List.filled(64, 'a').join();
AudioJson _stream(String id, [String device = 'device-A']) => {
  'sourceId': id,
  'deviceId': device,
  'audioPort': 2345,
  'audioToken': _token,
};
AudioJson _endpoint(String id) => {
  'relayId': id,
  'kind': 'audio',
  'url': 'http://127.0.0.1:1234/$_token',
};
Matcher _code(String code) =>
    isA<InteropException>().having((e) => e.code, 'code', code);

class _Player implements AudioPlayerPort {
  final changes = StreamController<AudioJson>.broadcast(sync: true);
  final calls = <String>[];
  Completer<AudioFormat>? opening;
  Completer<void>? confirmation;
  AudioFormat format = const AudioFormat('pcm_s16le', 48000, 2);
  bool paused = true, stuckClock = false;
  void Function(bool)? afterState;
  int position = 0, releases = 0;
  @override
  Stream<AudioJson> get events => changes.stream;
  @override
  Future<AudioFormat> open(String url) async {
    calls.add('open');
    return opening == null ? format : opening!.future;
  }

  @override
  Future<void> setPaused(bool value) async {
    calls.add(value ? 'pause' : 'play');
    await confirmation?.future;
    paused = value;
    afterState?.call(value);
  }

  @override
  Future<void> volume(double value, bool muted) async {
    calls.add('volume:$value:$muted');
  }

  @override
  int get positionMs {
    if (!paused && !stuckClock) position += 20;
    return position;
  }

  @override
  Future<AudioJson> release() async {
    releases++;
    return {'disposeRequested': true, 'nativeDeleteConfirmed': false};
  }
}

class _Harness {
  _Harness({this.startTimeout = const Duration(seconds: 1)});
  final Duration startTimeout;
  final players = <_Player>[];
  final calls = <(String, AudioJson)>[], events = <AudioJson>[];
  bool disposed = false, granted = true, backgroundReady = true;
  int epochs = 0, relays = 0, packets = 3;
  Completer<AudioJson>? focusOpening, mediaOpening;
  String? endpointUrl;
  late final outputs = PortableAudioOutputs(
    core: core,
    platform: platform,
    emit: events.add,
    isDisposed: () => disposed,
    startTimeout: startTimeout,
    operationTimeout: const Duration(milliseconds: 150),
    pollInterval: const Duration(milliseconds: 3),
    playerFactory: () {
      final player = _Player();
      players.add(player);
      return player;
    },
  );
  Future<void> visible() => outputs.setVisible(true);
  Future<AudioJson> core(String method, AudioJson params) async {
    calls.add((method, {...params}));
    switch (method) {
      case 'media.open':
        if (mediaOpening != null) return mediaOpening!.future;
        return {
          ..._endpoint('relay-${++relays}'),
          if (endpointUrl != null) 'url': endpointUrl,
        };
      case 'media.status':
        return {'status': 'streaming', 'packets': packets};
      case 'media.close':
        return {'closed': true};
      default:
        throw StateError('adapter must not own remote capture: $method');
    }
  }

  Future<AudioJson> platform(String method, AudioJson params) async {
    calls.add((method, {...params}));
    switch (method) {
      case 'audio.platform.focus.acquire':
        return focusOpening == null
            ? {'granted': granted, 'epoch': ++epochs}
            : focusOpening!.future;
      case 'audio.platform.focus.release':
        return {'released': true};
      case 'audio.platform.background':
        return {'ready': params['enabled'] == true && backgroundReady};
      default:
        throw StateError('no native PCM player calls: $method');
    }
  }

  Future<void> focus(String signal, [int? epoch]) =>
      outputs.handlePlatformEvent({
        'type': 'audio.platform.focus',
        'data': {'epoch': epoch ?? epochs, 'signal': signal},
      });
  List<(String, AudioJson)> named(String name) =>
      calls.where((c) => c.$1 == name).toList();
  List<String> get closed =>
      named('media.close').map((c) => c.$2['relayId'] as String).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('ready combines source PCM and advancing native playback clock without inventing speaker bytes', () async {
    final h = _Harness();
    await h.visible();
    final ready = await h.outputs.start(_stream('A'));
    for (final key in [
      'mediaInfoReady',
      'playingConfirmed',
      'sourcePcmReceived',
      'playbackClockAdvanced',
      'applied',
    ]) {
      expect(ready[key], true, reason: key);
    }
    expect(ready['playState'], 'playing');
    expect(ready['clockEndMs'], greaterThan(ready['clockStartMs'] as int));
    expect(ready['speakerSamplesVerified'], false);
    expect(ready['audibleContentVerified'], false);
    expect(ready.containsKey('bytesWritten'), false);
    expect(
      h
          .named('audio.platform.background')
          .every((c) => c.$2['enabled'] == false),
      true,
    );
    await h.outputs.dispose();
  });

  test('two simultaneous sources share one OS lease and stopping one preserves the other', () async {
    final h = _Harness();
    await h.visible();
    await Future.wait([
      h.outputs.start(_stream('A')),
      h.outputs.start(_stream('B', 'device-B')),
    ]);
    expect(h.named('audio.platform.focus.acquire'), hasLength(1));
    await h.outputs.stop('A');
    expect(h.named('audio.platform.focus.release'), isEmpty);
    expect(h.players.last.releases, 0);
    expect(h.outputs.status('B')['playState'], 'playing');
    await h.outputs.stop('B');
    expect(h.named('audio.platform.focus.release').single.$2['epoch'], 1);
    await h.outputs.dispose();
  });

  test('manual pause survives transient loss and gain while the other source resumes', () async {
    final h = _Harness();
    await h.visible();
    await h.outputs.start(_stream('A'));
    await h.outputs.start(_stream('B', 'device-B'));
    await h.outputs.pause('A');
    await h.focus('transientLoss');
    expect(h.outputs.status('B')['focusPaused'], true);
    await h.focus('granted');
    expect(h.outputs.status('A')['playState'], 'paused');
    expect(h.outputs.status('A')['manualPaused'], true);
    expect(h.outputs.status('B')['playState'], 'playing');
    expect(h.named('audio.platform.focus.acquire'), hasLength(1));
    expect((await h.outputs.resume('A'))['playState'], 'playing');
    await h.outputs.dispose();
  });

  test(
    'permanent loss requires a new user lease and never revives another source',
    () async {
      final h = _Harness();
      await h.visible();
      await h.outputs.start(_stream('A'));
      await h.outputs.start(_stream('B', 'device-B'));
      await h.focus('permanentLoss');
      await h.focus('granted', 1); // old queued gain is not an authorization.
      expect(h.outputs.status('A')['playState'], 'paused');
      expect(h.outputs.status('A')['requiresUserResume'], true);
      expect(h.named('audio.platform.focus.acquire'), hasLength(1));
      expect((await h.outputs.resume('A'))['playState'], 'playing');
      expect(h.named('audio.platform.focus.acquire'), hasLength(2));
      expect(h.outputs.status('B')['playState'], 'paused');
      expect(h.outputs.status('B')['requiresUserResume'], true);
      await h.focus('granted', 2);
      expect(h.outputs.status('B')['playState'], 'paused');
      await h.outputs.dispose();
    },
  );

  test(
    'noisy event requires explicit resume and ignores stale epoch callbacks',
    () async {
      final h = _Harness();
      await h.visible();
      await h.outputs.start(_stream('A'));
      await h.focus('noisy');
      expect(h.outputs.status('A')['requiresUserResume'], true);
      await h.outputs.resume('A');
      await h.focus('permanentLoss', 1);
      expect(h.outputs.status('A')['playState'], 'playing');
      await h.outputs.dispose();
    },
  );

  test('background authorization alone is insufficient without actual FGS readiness', () async {
    final h = _Harness();
    await h.visible();
    await h.outputs.start(_stream('A'));
    await h.outputs.setVisible(false);
    expect(h.outputs.status('A')['backgroundPaused'], true);
    h.backgroundReady = false;
    await expectLater(
      h.outputs.policy(true),
      throwsA(_code('audio_background_unavailable')),
    );
    expect(h.outputs.status('A')['playState'], 'paused');
    expect(h.outputs.status()['backgroundAllowed'], false);
    h.backgroundReady = true;
    await h.outputs.policy(true);
    expect(h.outputs.status('A')['playState'], 'playing');
    await h.outputs.pause('A');
    await h.outputs.setVisible(true);
    await h.outputs.policy(false);
    expect(h.outputs.status('A')['manualPaused'], true);
    expect(h.outputs.status('A')['playState'], 'paused');
    await h.outputs.dispose();
  });

  test('ready preserves genuine first playback when visibility pauses before the late receipt', () async {
    final h = _Harness();
    await h.visible();
    final starting = h.outputs.start(_stream('A'));
    final player = h.players.single;
    var plays = 0;
    player.afterState = (paused) {
      if (!paused && ++plays == 2) {
        player.afterState = null;
        unawaited(h.outputs.setVisible(false));
      }
    };
    final ready = await starting;
    expect(ready['playState'], 'paused');
    expect(ready['backgroundPaused'], true);
    expect(ready['playingConfirmed'], true);
    expect(ready['playbackClockAdvanced'], true);
    expect(ready['sourcePcmReceived'], true);
    expect(ready['revision'], greaterThan(1));
    await h.outputs.dispose();
  });

  test('a late pause confirmation cannot override a newer user resume or retry forever', () async {
    final h = _Harness();
    await h.visible();
    await h.outputs.start(_stream('A'));
    final player = h.players.single;
    player.confirmation = Completer();
    final pausing = h.outputs.pause('A');
    final cancelled = expectLater(pausing, throwsA(_code('cancelled')));
    await Future<void>.delayed(Duration.zero);
    final resuming = h.outputs.resume('A');
    player.confirmation!.complete();
    await cancelled;
    expect((await resuming)['playState'], 'playing');
    expect(h.outputs.status('A')['manualPaused'], false);
    await h.outputs.dispose();
  });

  test('denied focus does not open or play a media source', () async {
    final h = _Harness()..granted = false;
    await h.visible();
    await expectLater(
      h.outputs.start(_stream('A')),
      throwsA(_code('audio_focus_denied')),
    );
    expect(h.named('media.open'), isEmpty);
    expect(h.players.single.calls, isEmpty);
    expect(h.players.single.releases, 1);
    await h.outputs.dispose();
  });

  test('hidden start never silently treats visibility as granted', () async {
    final h = _Harness(startTimeout: const Duration(milliseconds: 35));
    await expectLater(
      h.outputs.start(_stream('A')),
      throwsA(_code('audio_timeout')),
    );
    expect(h.named('audio.platform.focus.acquire'), isEmpty);
    expect(h.named('media.open'), isEmpty);
    await h.outputs.dispose();
  });

  test('an advancing clock without source PCM is not ready', () async {
    final h = _Harness(startTimeout: const Duration(milliseconds: 40))
      ..packets = 0;
    await h.visible();
    await expectLater(
      h.outputs.start(_stream('A')),
      throwsA(_code('audio_timeout')),
    );
    expect(h.closed, ['relay-1']);
    expect(h.named('audio.platform.focus.release'), hasLength(1));
    await h.outputs.dispose();
  });

  test('source packets without an advancing clock are not ready', () async {
    final h = _Harness(startTimeout: const Duration(milliseconds: 40));
    await h.visible();
    final ready = h.outputs.start(_stream('A'));
    h.players.single.stuckClock = true;
    await expectLater(ready, throwsA(_code('audio_timeout')));
    expect(h.closed, ['relay-1']);
    await h.outputs.dispose();
  });

  test(
    'stop cancels a pending lease and releases its exact late epoch',
    () async {
      final h = _Harness()..focusOpening = Completer();
      await h.visible();
      final starting = h.outputs.start(_stream('A'));
      final cancelled = expectLater(starting, throwsA(_code('cancelled')));
      await Future<void>.delayed(Duration.zero);
      await h.outputs.stop('A');
      await cancelled;
      h.focusOpening!.complete({'granted': true, 'epoch': 41});
      await Future<void>.delayed(Duration.zero);
      expect(h.named('audio.platform.focus.release').single.$2['epoch'], 41);
      expect(h.named('media.open'), isEmpty);
      await h.outputs.dispose();
    },
  );

  test(
    'a cancelled acquisition cannot abandon a newly started source lease',
    () async {
      final h = _Harness()..focusOpening = Completer();
      await h.visible();
      final oldFocus = h.focusOpening!;
      final starting = h.outputs.start(_stream('A'));
      final cancelled = expectLater(starting, throwsA(_code('cancelled')));
      await Future<void>.delayed(Duration.zero);
      await h.outputs.stop('A');
      await cancelled;
      h
        ..focusOpening = null
        ..epochs = 1;
      final ready = await h.outputs.start(_stream('B', 'device-B'));
      expect(ready['focusEpoch'], 2);
      oldFocus.complete({'granted': true, 'epoch': 1});
      await Future<void>.delayed(Duration.zero);
      expect(h.named('audio.platform.focus.release').single.$2['epoch'], 1);
      expect(h.outputs.status('B')['playState'], 'playing');
      expect(h.players.last.releases, 0);
      await h.outputs.dispose();
    },
  );

  test(
    'late media open cannot reopen a stopped source or leak its relay',
    () async {
      final h = _Harness()..mediaOpening = Completer();
      await h.visible();
      final starting = h.outputs.start(_stream('A'));
      final cancelled = expectLater(starting, throwsA(_code('cancelled')));
      await Future<void>.delayed(Duration.zero);
      await h.outputs.stop('A');
      await cancelled;
      h.mediaOpening!.complete(_endpoint('late-A'));
      await Future<void>.delayed(Duration.zero);
      expect(h.closed, ['late-A']);
      expect(h.players.single.calls, isEmpty);
      await h.outputs.dispose();
    },
  );

  test(
    'late player completion cannot affect another device or publish ready',
    () async {
      final h = _Harness()..mediaOpening = Completer();
      await h.visible();
      final starting = h.outputs.start(_stream('A'));
      h.players.single.opening = Completer();
      final old = h.players.single;
      h.mediaOpening!.complete(_endpoint('A'));
      await Future<void>.delayed(Duration.zero);
      final cancelled = expectLater(starting, throwsA(_code('cancelled')));
      await h.outputs.stop('A');
      await cancelled;
      h.mediaOpening = null;
      await h.outputs.start(_stream('B', 'device-B'));
      old.opening!.complete(const AudioFormat('pcm_s16le', 48000, 2));
      await Future<void>.delayed(Duration.zero);
      expect(h.players.last.releases, 0);
      expect(old.calls.where((call) => call == 'play'), isEmpty);
      expect(
        h.events.where((e) => (e['data'] as Map)['sourceId'] == 'A'),
        isEmpty,
      );
      await h.outputs.dispose();
    },
  );

  test(
    'stopDevice and player failure close only exact source ownership',
    () async {
      final h = _Harness();
      await h.visible();
      await h.outputs.start(_stream('A'));
      await h.outputs.start(_stream('B', 'device-B'));
      await h.outputs.stopDevice('device-A');
      expect(h.players.first.releases, 1);
      expect(h.players.last.releases, 0);
      h.players.first.changes.add({'kind': 'failed'});
      expect(
        h.events.where((e) => e['type'] == 'audio.output.failed'),
        isEmpty,
      );
      h.players.last.changes.add({'kind': 'failed'});
      await Future<void>.delayed(Duration.zero);
      expect(h.events.last['type'], 'audio.output.failed');
      expect((h.events.last['data'] as Map)['sourceId'], 'B');
      await h.outputs.dispose();
    },
  );

  test('volume config never claims audible hardware verification or resumes paused audio', () async {
    final h = _Harness();
    await h.visible();
    await h.outputs.start(_stream('A'));
    await h.outputs.pause('A');
    final receipt = await h.outputs.volume('A', volume: .25, muted: true);
    expect(receipt['volumeConfigured'], true);
    expect(receipt['volumeOutputVerified'], false);
    expect(receipt['playState'], 'paused');
    expect(h.players.single.calls.last, 'volume:0.25:true');
    await expectLater(
      h.outputs.volume('A', volume: double.nan, muted: false),
      throwsA(_code('invalid_argument')),
    );
    await h.outputs.dispose();
  });

  test('invalid format and non-loopback endpoint fail before ready', () async {
    final h = _Harness();
    await h.visible();
    final starting = h.outputs.start(_stream('A'));
    h.players.single.format = const AudioFormat('pcm_s16le', 44100, 1);
    await expectLater(starting, throwsA(_code('audio_format')));
    expect(h.closed, ['relay-1']);
    await h.outputs.dispose();
    final other = _Harness()..endpointUrl = 'https://example.com/$_token';
    await other.visible();
    await expectLater(
      other.outputs.start(_stream('B')),
      throwsA(_code('invalid_endpoint')),
    );
    expect(other.players.single.calls, isEmpty);
    await other.outputs.dispose();
  });
}
