import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_codec/media_codec.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/audio_focus_service.dart';
import 'package:scrcpy_connect/core/media/audio_output_service.dart';
import 'package:scrcpy_connect/core/media/audio_platform.dart';
import 'package:scrcpy_connect/core/media/audio_player.dart';
import 'package:scrcpy_connect/core/media/models/audio_format.dart';
import 'package:scrcpy_connect/core/media/platform_audio.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';

void main() {
  test('本机混音租约按 owner 和原代次释放，旧回执不能撤销新租约', () async {
    final AudioPlatform platform = AudioFocusService(
      backgroundPlaybackSupported: false,
    );
    final first = await platform.acquireFocus('first');
    final other = await platform.acquireFocus('other');
    expect(first.granted, isTrue);
    expect((await platform.acquireFocus('first')).epoch, first.epoch);
    expect(await platform.releaseFocus('other', first.epoch!), isFalse);
    expect(await platform.releaseFocus('first', first.epoch!), isTrue);
    final next = await platform.acquireFocus('first');
    expect(next.epoch, greaterThan(other.epoch!));
    expect(await platform.releaseFocus('first', first.epoch!), isFalse);
    expect((await platform.acquireFocus('first')).epoch, next.epoch);
    expect((await platform.setBackground('first', true)).supported, isFalse);
    expect((await platform.setBackground('first', true)).ready, isFalse);
    expect((await platform.setBackground('first', false)).ready, isTrue);
  });

  test('系统适配独立解析回执并保留原 owner 与代次；无效代次保持未核验', () async {
    final calls = <({String command, Map<String, dynamic> params})>[];
    final raw = <String, dynamic>{'granted': true, 'epoch': 41};
    final platform = PlatformAudio(
      request: (command, params) async {
        calls.add((command: command, params: params));
        return switch (command) {
          'audio.platform.focus.acquire' => raw,
          'audio.platform.focus.release' => {'released': true},
          'audio.platform.background' => {'mediaPlaybackReady': true},
          'audio.platform.state' => {'visible': true},
          _ => throw StateError(command),
        };
      },
    );
    final result = await platform.acquireFocus('owner');
    raw['epoch'] = 'invalid';
    expect(result.epoch, 41);
    expect((await platform.acquireFocus('owner')).epoch, isNull);
    expect(await platform.releaseFocus('owner', result.epoch!), isTrue);
    expect(calls.last.params, {'ownerId': 'owner', 'epoch': 41});
    final background = await platform.setBackground('owner', true);
    expect(background.ready, isTrue);
    expect(background.supported, isTrue);
    expect(calls.last.params, {'ownerId': 'owner', 'enabled': true});
    expect(await platform.readVisible(), isTrue);
  });

  test('系统异常在适配处转换，内部调用保留可操作原因', () async {
    final platform = PlatformAudio(
      request: (_, _) async => throw PlatformException(
        code: 'audio_owner_busy',
        message: '原所有者仍在关闭。',
      ),
    );
    await expectLater(
      platform.acquireFocus('owner'),
      throwsA(_failure('audio_owner_busy')),
    );
  });

  test('声音平台事件只交付完整事实，未知消息不进入业务状态', () {
    final raw = <String, dynamic>{
      'type': 'audio.platform.focus',
      'data': <String, dynamic>{'epoch': 3, 'signal': 'noisy'},
    };
    final focus = decodeAudioPlatformEvent(raw) as AudioFocusChanged;
    (raw['data'] as Map)['epoch'] = 9;
    expect(focus.epoch, 3);
    expect(focus.signal, AudioFocusSignal.noisy);
    expect(
      (decodeAudioPlatformEvent({
        'type': 'audio.platform.visibility',
        'data': {'visible': false},
      }) as AudioVisibilityChanged).visible,
      isFalse,
    );
    final background = decodeAudioPlatformEvent({
      'type': 'audio.platform.background',
      'data': {'ownerId': 'original', 'ready': true},
    }) as AudioBackgroundChanged;
    expect(background.ownerId, 'original');
    expect(background.ready, isTrue);
    for (final data in <Map<String, dynamic>>[
      {'epoch': 3, 'signal': 'unknown'},
      {'epoch': -1, 'signal': 'granted'},
      {'epoch': '3', 'signal': 'granted'},
      {'signal': 'granted'},
    ]) {
      expect(
        decodeAudioPlatformEvent({
          'type': 'audio.platform.focus',
          'data': data,
        }),
        isNull,
      );
    }
    expect(
      decodeAudioPlatformEvent({
        'type': 'audio.platform.background',
        'data': {'ready': true},
      }),
      isNull,
    );
    expect(
      decodeAudioPlatformEvent({
        'type': 'audio.platform.visibility',
        'data': {'visible': 'false'},
      }),
      isNull,
    );
    expect(
      decodeAudioPlatformEvent({
        'type': 'unknown',
        'data': {1: 'invalid'},
      }),
      isNull,
    );
  });

  test('输出关闭等待迟到焦点及其原释放回执，不因播放器已删除而提前成功', () async {
    final fixture = _Output();
    final focus = Completer<Map<String, dynamic>>();
    final released = Completer<Map<String, dynamic>>();
    final acquired = Completer<void>();
    final releasing = Completer<void>();
    fixture.reply = (call) {
      if (call.command == 'audio.platform.focus.acquire') {
        acquired.complete();
        return focus.future;
      }
      if (call.command == 'audio.platform.focus.release') {
        releasing.complete();
        return released.future;
      }
      return fixture.defaults(call);
    };
    await fixture.output.setVisible(true);
    final starting = expectLater(
      fixture.output.start(_source),
      throwsA(isA<RequestFailure>()),
    );
    await acquired.future;
    var closed = false;
    final closing = fixture.output.dispose().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    focus.complete({'granted': true, 'epoch': 7});
    await releasing.future;
    expect(closed, isFalse);
    expect(fixture.calls.last.params['epoch'], 7);
    expect(
      fixture.calls.last.params['ownerId'],
      fixture.calls.first.params['ownerId'],
    );
    released.complete({'released': true});
    await closing;
    await starting;
    expect(fixture.player.releases, 1);
  });

  test('原焦点申请超时后关闭保持失败，回执到达后重试同一所有者', () async {
    final fixture = _Output(timeout: const Duration(milliseconds: 35));
    final focus = Completer<Map<String, dynamic>>();
    final acquired = Completer<void>();
    fixture.reply = (call) {
      if (call.command == 'audio.platform.focus.acquire') {
        acquired.complete();
        return focus.future;
      }
      return fixture.defaults(call);
    };
    await fixture.output.setVisible(true);
    final starting = expectLater(
      fixture.output.start(_source),
      throwsA(isA<RequestFailure>()),
    );
    await acquired.future;
    await expectLater(
      fixture.output.dispose(),
      throwsA(_failure('audio_focus_cleanup_unconfirmed')),
    );
    focus.complete({'granted': true, 'epoch': 7});
    await fixture.output.dispose();
    await starting;
    expect(
      fixture.calls.where((call) => call.command.endsWith('acquire')),
      hasLength(1),
    );
    expect(
      fixture.calls
          .where((call) => call.command.endsWith('release'))
          .single
          .params['epoch'],
      7,
    );
    expect(fixture.player.releases, 1);
  });

  test('焦点释放失败保留原代次，关闭重试不重新创建播放器或租约', () async {
    final fixture = _Output();
    var fail = true;
    fixture.reply = (call) {
      if (call.command == 'audio.platform.focus.release' && fail) {
        throw PlatformException(code: 'io_error');
      }
      return fixture.defaults(call);
    };
    await fixture.output.setVisible(true);
    final receipt = await fixture.output.start(_source);
    expect(receipt.focusEpoch, 7);
    await expectLater(
      fixture.output.dispose(),
      throwsA(_failure('audio_focus_cleanup_unconfirmed')),
    );
    fail = false;
    await fixture.output.dispose();
    final releases = fixture.calls.where(
      (call) => call.command.endsWith('release'),
    );
    expect(releases.length, greaterThanOrEqualTo(2));
    expect(
      releases.every(
        (call) =>
            call.params['epoch'] == 7 &&
            call.params['ownerId'] == fixture.calls.first.params['ownerId'],
      ),
      isTrue,
    );
    expect(
      fixture.calls.where((call) => call.command.endsWith('acquire')),
      hasLength(1),
    );
    expect(fixture.player.releases, 1);
  });

  test('关闭等待迟到的后台启用并在同一所有者上禁用，不留下游离回调', () async {
    final fixture = _Output();
    final enable = Completer<Map<String, dynamic>>();
    final disable = Completer<Map<String, dynamic>>();
    final enabling = Completer<void>();
    final disabling = Completer<void>();
    var enabled = false;
    fixture.reply = (call) {
      if (call.command == 'audio.platform.background') {
        if (call.params['enabled'] == true) {
          enabled = true;
          enabling.complete();
          return enable.future;
        }
        if (enabled) {
          disabling.complete();
          return disable.future;
        }
      }
      return fixture.defaults(call);
    };
    await fixture.output.setVisible(true);
    await fixture.output.policy(true);
    final starting = expectLater(
      fixture.output.start(_source),
      throwsA(isA<RequestFailure>()),
    );
    await enabling.future;
    var closed = false;
    final closing = fixture.output.dispose().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    enable.complete({'ready': true});
    await disabling.future;
    expect(closed, isFalse);
    disable.complete({'ready': false});
    await closing;
    await starting;
    expect(fixture.calls.map((call) => call.params['enabled']), [
      false,
      true,
      false,
    ]);
    expect(
      fixture.calls.map((call) => call.params['ownerId']).toSet(),
      hasLength(1),
    );
    expect(fixture.player.releases, 1);
  });

  test('后台申请超时及迟到禁用失败保留原操作，关闭可在原所有者重试', () async {
    final fixture = _Output(timeout: const Duration(milliseconds: 35));
    final enable = Completer<Map<String, dynamic>>();
    final enabling = Completer<void>();
    final failedDisable = Completer<void>();
    var enabled = false;
    var failDisable = true;
    fixture.reply = (call) {
      if (call.command == 'audio.platform.background') {
        if (call.params['enabled'] == true) {
          enabled = true;
          enabling.complete();
          return enable.future;
        }
        if (enabled && failDisable) {
          if (!failedDisable.isCompleted) failedDisable.complete();
          throw PlatformException(code: 'io_error');
        }
      }
      return fixture.defaults(call);
    };
    await fixture.output.setVisible(true);
    await fixture.output.policy(true);
    final starting = expectLater(
      fixture.output.start(_source),
      throwsA(isA<RequestFailure>()),
    );
    await enabling.future;
    await expectLater(
      fixture.output.dispose(),
      throwsA(_failure('audio_background_cleanup_unconfirmed')),
    );
    enable.complete({'ready': true});
    await failedDisable.future;
    await starting;
    failDisable = false;
    await fixture.output.dispose();
    expect(
      fixture.calls.where((call) => call.command.endsWith('acquire')),
      isEmpty,
    );
    final backgrounds = fixture.calls.where(
      (call) => call.command == 'audio.platform.background',
    );
    expect(backgrounds.map((call) => call.params['enabled']).take(3), [
      false,
      true,
      false,
    ]);
    expect(backgrounds.last.params['enabled'], isFalse);
    expect(backgrounds.length, greaterThanOrEqualTo(4));
    expect(
      backgrounds.map((call) => call.params['ownerId']).toSet(),
      hasLength(1),
    );
    expect(fixture.player.releases, 1);
  });

  test('未使用声音输出的退出不创建平台请求或播放器', () async {
    final fixture = _Output();
    await fixture.output.dispose();
    expect(fixture.calls, isEmpty);
    expect(fixture.player.releases, 0);
  });
}

typedef _Call = ({String command, Map<String, dynamic> params});

class _Output {
  _Output({this.timeout = const Duration(milliseconds: 500)}) {
    addTearDown(() async {
      await output.dispose();
      await player.eventsController.close();
    });
  }
  final Duration timeout;
  final calls = <_Call>[];
  final player = _Player();
  late Future<Map<String, dynamic>> Function(_Call) reply = defaults;
  late final output = AudioOutputService(
    platform: PlatformAudio(
      request: (command, params) {
        final call = (command: command, params: params);
        calls.add(call);
        return reply(call);
      },
    ),
    openSource: (id, generation) async => MediaCodecSource(
      sourceId: id,
      generation: generation,
      codec: 'pcm_s16le',
      attachAddress: 1,
      detachAddress: 2,
    ),
    sourceStatus: (id) async => ScrcpySourceStatus(
      captureRef: 'capture',
      sourceId: id,
      generation: 1,
      kind: .audio,
      codec: 'pcm_s16le',
      status: .streaming,
      packets: 2,
      bytes: 4096,
    ),
    playerFactory: () => player,
    emit: (_) {},
    isDisposed: () => false,
    operationTimeout: timeout,
    pollInterval: const Duration(milliseconds: 1),
  );
  Future<Map<String, dynamic>> defaults(_Call call) async =>
      switch (call.command) {
        'audio.platform.focus.acquire' => {'granted': true, 'epoch': 7},
        'audio.platform.focus.release' => {'released': true},
        'audio.platform.background' => {'supported': false, 'ready': false},
        _ => throw StateError(call.command),
      };
}

class _Player implements AudioPlayer {
  final eventsController = StreamController<MediaPlayerEvent>.broadcast(
    sync: true,
  );
  var releases = 0, position = 0;
  @override
  Stream<MediaPlayerEvent> get events => eventsController.stream;
  @override
  int get positionMs => position += 20;
  @override
  AudioPlayerStatus get outputStatus =>
      const AudioPlayerStatus(nativeReady: true, bytesWritten: 4096);
  @override
  Future<AudioFormat> open(MediaCodecSource source) async =>
      const AudioFormat('pcm_s16le', 48000, 2);
  @override
  Future<void> setPaused(bool paused) async {}
  @override
  Future<void> volume(double value, bool muted) async {}
  @override
  Future<MediaOutputRelease> release() async {
    releases++;
    await eventsController.close();
    return const MediaOutputRelease(nativeDeleteConfirmed: true);
  }
}

Matcher _failure(String code) =>
    isA<RequestFailure>().having((failure) => failure.code, 'code', code);
const _source = DeviceAudioSnapshot(
  sourceId: 'source',
  deviceId: 'device',
  generation: 1,
  name: 'Phone',
  status: .starting,
  createdAt: 1,
  audioSourceId:
      '0000000000000000000000000000000000000000000000000000000000000001',
  captureReady: true,
  mediaReady: true,
);
