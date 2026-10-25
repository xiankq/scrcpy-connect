import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/media/output/audio_player_port.dart';
import 'package:scrcpy_connect/media/output/audio_output_coordinator.dart';

final _token = List.filled(64, 'a').join();
AudioJson _stream(String id, [String device = 'device-A']) => {
  'sourceId': id,
  'deviceId': device,
  'audioSourceId': _token,
};
AudioJson _endpoint(String id) => {
  'relayId': id,
  'kind': 'audio',
  'sourceId': _token,
  'container': 'packet',
  'codec': 'pcm_s16le',
  'generation': 1,
  'attachAddress': 4096,
  'detachAddress': 8192,
};
Matcher _code(String code) =>
    isA<ApplicationCommandException>().having((e) => e.code, 'code', code);

class _Player implements AudioPlayerPort {
  final changes = StreamController<AudioJson>.broadcast(sync: true);
  final calls = <String>[];
  Completer<AudioFormat>? opening;
  Completer<void>? confirmation;
  Completer<AudioJson>? releasing;
  int releaseFailures = 0, observerFailures = 0;
  AudioJson releaseReceipt = {
    'disposeRequested': true,
    'nativeDeleteConfirmed': true,
  };
  AudioFormat format = const AudioFormat('pcm_s16le', 48000, 2);
  bool paused = true, stuckClock = false;
  void Function(bool)? afterState;
  int position = 0, releases = 0;
  bool outputAcceptsBytes = true;
  @override
  AudioJson get outputStatus => {
    'nativeReady': outputAcceptsBytes && position > 0,
    'bytesWritten': outputAcceptsBytes ? position * 192 : 0,
  };
  @override
  Stream<AudioJson> get events => _PlayerEvents(this);
  @override
  Future<AudioFormat> open(AudioJson source) async {
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
    if (releaseFailures > 0) {
      releaseFailures--;
      throw StateError('播放器清理未确认');
    }
    return releasing == null ? releaseReceipt : releasing!.future;
  }
}

class _PlayerEvents extends Stream<AudioJson> {
  _PlayerEvents(this.player);
  final _Player player;

  @override
  StreamSubscription<AudioJson> listen(
    void Function(AudioJson)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _PlayerSubscription(
    player,
    player.changes.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
  );
}

class _PlayerSubscription implements StreamSubscription<AudioJson> {
  _PlayerSubscription(this.player, this.subscription);
  final _Player player;
  final StreamSubscription<AudioJson> subscription;

  @override
  Future<void> cancel() async {
    if (player.observerFailures > 0) {
      player.observerFailures--;
      throw StateError('观察清理未确认');
    }
    await subscription.cancel();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness({
    this.startTimeout = const Duration(seconds: 1),
    this.operationTimeout = const Duration(milliseconds: 150),
  });
  final Duration startTimeout, operationTimeout;
  final players = <_Player>[];
  final calls = <(String, AudioJson)>[], events = <AudioJson>[];
  bool disposed = false, granted = true, backgroundReady = true;
  bool backgroundSupported = true;
  bool focusBusy = false;
  bool reuseNativeEpoch = false;
  int? nativeEpoch;
  int epochs = 0, relays = 0, packets = 3;
  Completer<AudioJson>? focusOpening, focusClosing, mediaOpening;
  bool invalidEndpoint = false;
  late final outputs = AudioOutputCoordinator(
    request: request,
    platform: platform,
    emit: events.add,
    isDisposed: () => disposed,
    startTimeout: startTimeout,
    operationTimeout: operationTimeout,
    pollInterval: const Duration(milliseconds: 3),
    playerFactory: () {
      final player = _Player();
      players.add(player);
      return player;
    },
  );
  Future<void> visible() => outputs.setVisible(true);
  Future<AudioJson> request(String method, AudioJson params) async {
    calls.add((method, {...params}));
    switch (method) {
      case 'media.open':
        if (mediaOpening != null) return mediaOpening!.future;
        return {
          ..._endpoint('relay-${++relays}'),
          if (invalidEndpoint) 'attachAddress': 0,
        };
      case 'media.status':
        return {'status': 'streaming', 'packets': packets};
      default:
        throw StateError('adapter must not own remote capture: $method');
    }
  }

  Future<AudioJson> platform(String method, AudioJson params) async {
    calls.add((method, {...params}));
    switch (method) {
      case 'audio.platform.focus.acquire':
        if (focusBusy) {
          throw const ApplicationCommandException(
            'audio_owner_busy',
            'another owner',
          );
        }
        if (reuseNativeEpoch) {
          nativeEpoch ??= ++epochs;
          return focusOpening == null
              ? {'granted': granted, 'epoch': nativeEpoch}
              : focusOpening!.future;
        }
        return focusOpening == null
            ? {'granted': granted, 'epoch': ++epochs}
            : focusOpening!.future;
      case 'audio.platform.focus.release':
        if (focusClosing != null) await focusClosing!.future;
        if (params['epoch'] == nativeEpoch) nativeEpoch = null;
        return {'released': true};
      case 'audio.platform.background':
        return {
          'supported': backgroundSupported,
          'ready':
              params['enabled'] == true &&
              backgroundSupported &&
              backgroundReady,
        };
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (method, failure) in const [
    ('stop', 'throw'),
    ('stop', 'denied'),
    ('stop', 'unknown'),
    ('stopDevice', 'throw'),
    ('dispose', 'unknown'),
  ]) {
    test('$method 保留 $failure 的实际输出，沿原对象重试清理', () async {
      final h = _Harness();
      await h.visible();
      await h.outputs.start(_stream('A'));
      await h.outputs.start(_stream('B', 'device-B'));
      final player = h.players.first;
      if (failure == 'throw') {
        player.releaseFailures = 1;
      } else {
        player.releaseReceipt = {
          'disposeRequested': true,
          'nativeDeleteConfirmed': failure == 'unknown',
          if (failure == 'unknown') 'cleanupUnconfirmed': true,
        };
      }
      Future<void> stop() async {
        switch (method) {
          case 'stop':
            await h.outputs.stop('A');
          case 'stopDevice':
            await h.outputs.stopDevice('device-A');
          case 'dispose':
            await h.outputs.dispose();
        }
      }

      if (method != 'stop') {
        await expectLater(stop(), throwsA(_code('audio_cleanup_unconfirmed')));
      } else {
        await stop();
        expect(h.outputs.status('B')['playState'], 'playing');
      }
      expect(player.releases, 1);
      expect(h.players.last.releases, method == 'dispose' ? 1 : 0);
      player.releaseReceipt = {
        'disposeRequested': true,
        'nativeDeleteConfirmed': true,
      };
      await stop();
      expect(player.releases, 2);
      expect(h.players.last.releases, method == 'dispose' ? 1 : 0);
      await h.outputs.dispose();
    });
  }

  test('清理等待超时仍复用同一实际操作，停止设备和关闭不能遗弃输出', () async {
    final h = _Harness(operationTimeout: const Duration(milliseconds: 20));
    await h.visible();
    await h.outputs.start(_stream('A'));
    await h.outputs.start(_stream('B', 'device-B'));
    final player = h.players.first;
    final release = Completer<AudioJson>();
    player.releasing = release;
    final first = await h.outputs.stop('A');
    expect((first['cleanup'] as Map)['cleanupUnconfirmed'], true);
    final second = await h.outputs.stop('A');
    expect((second['cleanup'] as Map)['cleanupUnconfirmed'], true);
    await expectLater(
      h.outputs.stopDevice('device-A'),
      throwsA(_code('audio_cleanup_unconfirmed')),
    );
    expect(player.releases, 1);
    expect(h.players.last.releases, 0);
    await expectLater(
      h.outputs.dispose(),
      throwsA(_code('audio_cleanup_unconfirmed')),
    );
    expect(player.releases, 1);
    release.complete({'disposeRequested': true, 'nativeDeleteConfirmed': true});
    await Future<void>.delayed(Duration.zero);
    await h.outputs.dispose();
    expect(player.releases, 1);
    expect(h.players.last.releases, 1);
  });

  test('观察取消失败仍释放播放器，重试只处理未确认的观察责任', () async {
    final h = _Harness();
    await h.visible();
    await h.outputs.start(_stream('A'));
    final player = h.players.single..observerFailures = 1;
    final first = await h.outputs.stop('A');
    expect((first['cleanup'] as Map)['cleanupUnconfirmed'], true);
    expect(player.releases, 1);
    final retry = await h.outputs.stop('A');
    expect((retry['cleanup'] as Map)['nativeDeleteConfirmed'], true);
    expect((retry['cleanup'] as Map)['cleanupUnconfirmed'], isNot(true));
    expect(player.releases, 1);
    await h.outputs.dispose();
  });

  test('未确认释放的输出继续占用数量上限', () async {
    final h = _Harness();
    await h.visible();
    for (var i = 0; i < 16; i++) {
      await h.outputs.start(_stream('source-$i'));
      h.players.last.releaseReceipt = {'nativeDeleteConfirmed': false};
      await h.outputs.stop('source-$i');
    }
    await expectLater(
      h.outputs.start(_stream('overflow')),
      throwsA(_code('resource_busy')),
    );
    expect(h.players, hasLength(16));
    for (final player in h.players) {
      player.releaseReceipt = {'nativeDeleteConfirmed': true};
    }
    await h.outputs.dispose();
    expect(h.players.map((player) => player.releases), everyElement(2));
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
    expect(h.players.single.releases, 1);
    expect(h.named('audio.platform.focus.release'), hasLength(1));
    await h.outputs.dispose();
  });

  test('source packets without an advancing clock are not ready', () async {
    final h = _Harness(startTimeout: const Duration(milliseconds: 40));
    await h.visible();
    final ready = h.outputs.start(_stream('A'));
    h.players.single.stuckClock = true;
    await expectLater(ready, throwsA(_code('audio_timeout')));
    expect(h.players.single.releases, 1);
    await h.outputs.dispose();
  });

  test(
    'source packets and an advancing clock require accepted native bytes',
    () async {
      final h = _Harness(startTimeout: const Duration(milliseconds: 40));
      await h.visible();
      final ready = h.outputs.start(_stream('A'));
      h.players.single.outputAcceptsBytes = false;
      await expectLater(ready, throwsA(_code('audio_timeout')));
      expect(h.players.single.releases, 1);
      await h.outputs.dispose();
    },
  );

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

  test('cancelled acquisition drains its reused native epoch before another acquire', () async {
    final h = _Harness()
      ..reuseNativeEpoch = true
      ..focusOpening = Completer();
    await h.visible();
    final oldFocus = h.focusOpening!;
    final starting = h.outputs.start(_stream('A'));
    final cancelled = expectLater(starting, throwsA(_code('cancelled')));
    await Future<void>.delayed(Duration.zero);
    await h.outputs.stop('A');
    await cancelled;
    h.focusOpening = null;
    final replacement = h.outputs.start(_stream('B', 'device-B'));
    await Future<void>.delayed(Duration.zero);
    // NativeAudioRuntime 向同一所有者返回已有世代。
    // 此处第二次获取会返回 1，使 A 的延迟清理误杀 B。
    expect(h.named('audio.platform.focus.acquire'), hasLength(1));
    h.focusClosing = Completer();
    oldFocus.complete({'granted': true, 'epoch': 1});
    await Future<void>.delayed(Duration.zero);
    expect(h.named('audio.platform.focus.acquire'), hasLength(1));
    expect(h.named('audio.platform.focus.release').single.$2['epoch'], 1);
    h.focusClosing!.complete({'released': true});
    h.focusClosing = null;
    final ready = await replacement;
    expect(ready['focusEpoch'], 2);
    expect(h.named('audio.platform.focus.acquire'), hasLength(2));
    expect(h.nativeEpoch, 2);
    expect(h.outputs.status('B')['playState'], 'playing');
    expect(h.players.last.releases, 0);
    await h.outputs.dispose();
  });

  test('迟到来源描述不能重开已停止输出，也不授予捕获关闭权', () async {
    final h = _Harness()..mediaOpening = Completer();
    await h.visible();
    final starting = h.outputs.start(_stream('A'));
    final cancelled = expectLater(starting, throwsA(_code('cancelled')));
    await Future<void>.delayed(Duration.zero);
    await h.outputs.stop('A');
    await cancelled;
    h.mediaOpening!.complete(_endpoint('late-A'));
    await Future<void>.delayed(Duration.zero);
    expect(h.named('media.close'), isEmpty);
    expect(h.players.single.releases, 1);
    expect(h.players.single.calls, isEmpty);
    await h.outputs.dispose();
  });

  test(
    'a release timeout keeps its native lease barrier until the actual reply',
    () async {
      final h = _Harness()..reuseNativeEpoch = true;
      await h.visible();
      await h.outputs.start(_stream('A'));
      h.focusClosing = Completer();
      await h.outputs.stop(
        'A',
      ); // User cleanup is bounded; native is still pending.
      expect(h.nativeEpoch, 1);
      await expectLater(
        h.outputs.start(_stream('B')),
        throwsA(_code('audio_timeout')),
      );
      expect(h.named('audio.platform.focus.acquire'), hasLength(1));
      expect(h.nativeEpoch, 1);
      h.focusClosing!.complete({'released': true});
      h.focusClosing = null;
      await Future<void>.delayed(Duration.zero);
      final recovered = await h.outputs.start(_stream('C'));
      expect(recovered['focusEpoch'], 2);
      expect(h.nativeEpoch, 2);
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

  test('invalid format and native packet endpoint fail before ready', () async {
    final h = _Harness();
    await h.visible();
    final starting = h.outputs.start(_stream('A'));
    h.players.single.format = const AudioFormat('pcm_s16le', 44100, 1);
    await expectLater(starting, throwsA(_code('audio_format')));
    expect(h.players.single.releases, 1);
    await h.outputs.dispose();
    final other = _Harness()..invalidEndpoint = true;
    await other.visible();
    await expectLater(
      other.outputs.start(_stream('B')),
      throwsA(_code('invalid_endpoint')),
    );
    expect(other.players.single.calls, isEmpty);
    await other.outputs.dispose();
  });

  test(
    'platform cleanup keeps its exact owner ID and a busy owner is retryable',
    () async {
      final first = _Harness();
      await first.visible();
      await first.outputs.start(_stream('A'));
      final second = _Harness()..focusBusy = true;
      await second.visible();
      await expectLater(
        second.outputs.start(_stream('B')),
        throwsA(_code('audio_owner_busy')),
      );
      expect(second.named('media.open'), isEmpty);
      expect(first.outputs.status('A')['playState'], 'playing');
      second.focusBusy = false;
      await second.outputs.start(_stream('C'));
      final firstOwner = first
          .named('audio.platform.focus.acquire')
          .single
          .$2['ownerId'];
      final secondOwner = second
          .named('audio.platform.focus.acquire')
          .last
          .$2['ownerId'];
      expect(firstOwner, isNot(secondOwner));
      await second.outputs.dispose();
      expect(first.players.single.releases, 0);
      await first.outputs.dispose();
      expect(
        first.named('audio.platform.focus.release').single.$2['ownerId'],
        firstOwner,
      );
      expect(
        second.named('audio.platform.focus.release').single.$2['ownerId'],
        secondOwner,
      );
    },
  );

  test('real service loss pauses background audio and ignores another owner events', () async {
    final h = _Harness();
    await h.visible();
    await h.outputs.policy(true);
    await h.outputs.start(_stream('A'));
    await h.outputs.setVisible(false);
    final owner = h.named('audio.platform.focus.acquire').single.$2['ownerId'];
    Future<void> service(String ownerId, bool ready) =>
        h.outputs.handlePlatformEvent({
          'type': 'audio.platform.background',
          'data': {'ownerId': ownerId, 'ready': ready},
        });
    await service('stale-owner', false);
    expect(h.outputs.status('A')['playState'], 'playing');
    await service(owner as String, false);
    expect(h.outputs.status('A')['backgroundPaused'], true);
    await h.outputs.pause('A');
    await service(owner, true);
    expect(h.outputs.status('A')['manualPaused'], true);
    expect(h.outputs.status('A')['playState'], 'paused');
    await h.outputs.resume('A');
    expect(h.outputs.status('A')['playState'], 'playing');
    await h.outputs.dispose();
  });
}
