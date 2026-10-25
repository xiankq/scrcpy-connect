import '../../support/scrcpy_event_fixture.dart';

import 'dart:async';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/stores/media/device_audio_source_coordinator.dart';

Matcher _code(String code) => isA<ApplicationCommandException>().having(
  (error) => error.code,
  'code',
  code,
);

AudioSourceJson _ready(String device, Object? source, {int revision = 7}) => {
  'deviceId': device,
  'sourceId': source,
  'backend': 'media_codec',
  'nativeReady': true,
  'applied': true,
  'bytesWritten': 4096,
  'revision': revision,
  'playState': 'paused',
  'focusPaused': true,
};

void main() {
  test('没有控制所有者或低版本时不进行任何原生创建', () async {
    final fixture = _Fixture();
    fixture.eligible.remove('a');
    await expectLater(
      Future.sync(() => fixture.owner.start('a')),
      throwsA(_code('session_required')),
    );
    fixture.eligible.add('a');
    fixture.levels['a'] = 29;
    await expectLater(
      Future.sync(() => fixture.owner.start('a')),
      throwsA(_code('unsupported')),
    );
    expect(fixture.native.creations, isEmpty);
    await fixture.owner.close();
  });

  test('独立 output PCM 使用实际原生来源，首包格式不冒充播放确认', () async {
    final startedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final fixture = _Fixture();
    final source = await fixture.owner.start('a');
    final options = fixture.native.creations.single.$2;
    expect(options.video, isFalse);
    expect(options.audio, isTrue);
    expect(options.control, isFalse);
    expect(options.powerOn, isFalse);
    expect(source['status'], 'starting');
    expect(
      source['createdAt'],
      inInclusiveRange(
        startedAt,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
    );
    expect(source['captureReady'], isTrue);
    expect(source['nativeAttached'], isFalse);
    expect(source['playbackVerified'], isFalse);
    expect(source['remoteExitVerified'], isFalse);
    expect(source.containsKey('packets'), isFalse);
    expect(source.containsKey('frames'), isFalse);
    final endpoint = await fixture.owner.openSource(
      source['audioSourceId'] as String,
      generation: 9,
    );
    expect(endpoint['sourceId'], source['audioSourceId']);
    expect(endpoint['generation'], 9);
    expect(endpoint['attachAddress'], 101);
    expect(endpoint['codec'], 'pcm_s16le');
    expect(fixture.native.inspected, [('capture-1', 9)]);
    expect(() => source['status'] = 'playing', throwsUnsupportedError);
    await fixture.owner.close();
  });

  test('准备或播放器尚未确认时重复启动不会创建第二份音源', () async {
    final fixture = _Fixture();
    final first = await fixture.owner.start('a');
    await expectLater(
      Future.sync(() => fixture.owner.start('a')),
      throwsA(_code('audio_source_starting')),
    );
    final ready = await fixture.owner.command(
      'audio.ready',
      _ready('a', first['sourceId']),
    );
    expect(ready['status'], 'paused');
    expect(ready['nativeAttached'], isTrue);
    expect(ready['playbackVerified'], isTrue);
    expect(ready['speakerSamplesVerified'], isFalse);
    expect(ready['audibleContentVerified'], isFalse);
    final existing = await fixture.owner.start('a');
    expect(existing['existing'], isTrue);
    expect(existing['sourceId'], first['sourceId']);
    expect(fixture.native.creations, hasLength(1));
    await fixture.owner.close();
  });

  for (final key in ['nativeReady', 'revision']) {
    test('ready 缺少 $key 不修改播放状态', () async {
      final fixture = _Fixture();
      final source = await fixture.owner.start('a');
      final params = _ready('a', source['sourceId'])..remove(key);
      await expectLater(
        Future.sync(() => fixture.owner.command('audio.ready', params)),
        throwsA(_code('audio_not_ready')),
      );
      expect(fixture.owner.snapshots().single['nativeAttached'], isFalse);
      await fixture.owner.close();
    });
  }

  test('只接纳真实呈现回执且旧 revision 不覆盖新的焦点暂停', () async {
    final fixture = _Fixture();
    final source = await fixture.owner.start('a');
    final id = source['sourceId'];
    await fixture.owner.command('audio.ready', _ready('a', id));
    final paused = await fixture.owner.command('audio.presentation', {
      ..._ready('a', id, revision: 9),
      'reason': 'temporary focus loss',
    });
    expect(paused['nativeRevision'], 9);
    await fixture.owner.command('audio.ready', {
      ..._ready('a', id),
      'playState': 'playing',
      'focusPaused': false,
    });
    expect(fixture.owner.snapshots().single['status'], 'paused');
    expect(fixture.owner.snapshots().single['focusPaused'], isTrue);
    await expectLater(
      Future.sync(
        () => fixture.owner.command('audio.presentation', {
          'deviceId': 'a',
          'sourceId': id,
          'revision': 10,
          'playState': 'playing',
        }),
      ),
      throwsA(_code('audio_not_applied')),
    );
    await fixture.owner.close();
  });

  test('音量和暂停提议不修改事实，应用回执必须绑定精确来源', () async {
    final fixture = _Fixture();
    final source = await fixture.owner.start('a');
    final id = source['sourceId'];
    await fixture.owner.command('audio.ready', _ready('a', id));
    final proposed = await fixture.owner.command('audio.volume', {
      'deviceId': 'a',
      'volume': 0.25,
      'muted': true,
    });
    expect(proposed['nativeApplyRequired'], isTrue);
    expect(fixture.owner.snapshots().single['volume'], 1);
    await expectLater(
      Future.sync(
        () => fixture.owner.command('audio.volume', {
          'deviceId': 'a',
          'volume': 0.25,
          'muted': true,
          'applied': true,
        }),
      ),
      throwsA(_code('source_changed')),
    );
    final applied = await fixture.owner.command('audio.volume', {
      ...proposed,
      'applied': true,
    });
    expect(applied['volume'], 0.25);
    expect(applied['muted'], isTrue);
    final pause = await fixture.owner.command('audio.pause', {'deviceId': 'a'});
    expect(pause['nativeApplyRequired'], isTrue);
    final resumed = await fixture.owner.command('audio.resume', {
      ..._ready('a', id, revision: 10),
      'playState': 'playing',
      'focusPaused': false,
    });
    expect(resumed['status'], 'playing');
    await fixture.owner.close();
  });

  test('最后所有者撤销同步阻止迟到创建，取得句柄后关闭而不启动', () async {
    final fixture = _Fixture();
    final gate = fixture.native.creationGate = Completer<String>();
    final starting = fixture.owner.start('a');
    final failedStart = expectLater(starting, throwsA(_code('cancelled')));
    await fixture.native.created.future;
    fixture.eligible.remove('a');
    var drained = false;
    final draining = fixture.owner
        .eligibilityChanged('a')
        .then((_) => drained = true);
    expect(fixture.owner.snapshots(activeOnly: true), isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    gate.complete('late-capture');
    await draining;
    await failedStart;
    expect(fixture.native.started, isEmpty);
    expect(fixture.native.stopped, ['late-capture']);
    expect(fixture.owner.snapshots(), isEmpty);
    await fixture.owner.close();
  });

  test('质量交接资格保留音源，真正撤销后清理首败可用同来源重试', () async {
    final fixture = _Fixture();
    final source = await fixture.owner.start('a');
    // 原窗口暂时无 capture 时，session 所有者的有界 handoff 仍保留同步资格。
    await fixture.owner.eligibilityChanged('a');
    expect(fixture.native.stopped, isEmpty);
    fixture.native.stopFailures = 1;
    fixture.eligible.remove('a');
    await expectLater(
      fixture.owner.eligibilityChanged('a'),
      throwsA(
        isA<ApplicationCommandException>().having(
          (error) => error.code,
          'code',
          'cleanup_unconfirmed',
        ),
      ),
    );
    expect(fixture.owner.snapshots(activeOnly: true), isEmpty);
    expect(
      fixture.owner.snapshots().single['cleanupError'],
      isA<Map<String, Object?>>(),
    );
    await fixture.owner.stop('a', sourceId: source['sourceId'] as String);
    expect(fixture.native.stopped, ['capture-1', 'capture-1']);
    expect(fixture.owner.snapshots(), isEmpty);
    await fixture.owner.close();
  });

  test('旧来源 stop 和迟到 ready 不能撤销或更新后继', () async {
    final fixture = _Fixture();
    final old = await fixture.owner.start('a');
    await fixture.owner.stop('a', sourceId: old['sourceId'] as String);
    final next = await fixture.owner.start('a');
    expect(next['sourceId'], isNot(old['sourceId']));
    expect(next['generation'], 2);
    await expectLater(
      fixture.owner.stop('a', sourceId: old['sourceId'] as String),
      throwsA(_code('source_changed')),
    );
    await expectLater(
      Future.sync(
        () =>
            fixture.owner.command('audio.ready', _ready('a', old['sourceId'])),
      ),
      throwsA(_code('source_changed')),
    );
    expect(fixture.owner.snapshots().single['sourceId'], next['sourceId']);
    expect(fixture.native.stopped, ['capture-1']);
    await fixture.owner.close();
  });

  test('同设备新音源等待旧关闭，其他设备仍可启动', () async {
    final fixture = _Fixture();
    await fixture.owner.start('a');
    final gate = fixture.native.stopGate = Completer<void>();
    final stopping = fixture.owner.stop('a');
    final replacement = fixture.owner.start('a');
    final other = await fixture.owner.start('b');
    expect(other['deviceId'], 'b');
    expect(fixture.native.creations.map((creation) => creation.$1), [
      'connection-a',
      'connection-b',
    ]);
    gate.complete();
    await stopping;
    final next = await replacement;
    expect(next['deviceId'], 'a');
    expect(fixture.native.creations, hasLength(3));
    await fixture.owner.close();
  });

  test('关闭先撤全部准入，首败保留句柄供下一次 close 重试', () async {
    final fixture = _Fixture();
    await fixture.owner.start('a');
    await fixture.owner.start('b');
    fixture.native.stopFailures = 1;
    await expectLater(
      fixture.owner.close(),
      throwsA(isA<ApplicationCommandException>()),
    );
    expect(fixture.owner.snapshots(activeOnly: true), isEmpty);
    expect(fixture.owner.snapshots(), hasLength(1));
    await expectLater(
      Future.sync(() => fixture.owner.start('b')),
      throwsA(_code('disposed')),
    );
    await fixture.owner.close();
    expect(fixture.owner.snapshots(), isEmpty);
    expect(
      fixture.native.stopped.where((id) => id == 'capture-1'),
      hasLength(2),
    );
    expect(
      fixture.native.stopped.where((id) => id == 'capture-2'),
      hasLength(1),
    );
  });

  test('真正 stopped 事件撤销来源，失败清理不会误报完成', () async {
    final fixture = _Fixture();
    await fixture.owner.start('a');
    fixture.native.stopFailures = 1;
    final emittedFailure = Completer<void>();
    fixture.onEvent = (event) {
      if (event['cleanupError'] != null && !emittedFailure.isCompleted) {
        emittedFailure.complete();
      }
    };
    fixture.native.events['capture-1']!.add(
      const ScrcpyStopped(reason: 'remote_eof'),
    );
    await emittedFailure.future;
    expect(fixture.owner.snapshots(activeOnly: true), isEmpty);
    expect(fixture.owner.snapshots().single['reason'], 'remote_eof');
    await fixture.owner.close();
    expect(fixture.native.stopped, ['capture-1', 'capture-1']);
  });
}

final class _Fixture {
  _Fixture() {
    owner = DeviceAudioSourceCoordinator(
      requireConnection: (device) => connections[device]!,
      scrcpy: ScrcpyClient(native),
      hasAudioOwner: eligible.contains,
      emit: (type, device, data) {
        emissions.add((type, device, data));
        onEvent?.call(data);
      },
      apiLevel: (device) => levels[device],
    );
  }
  final native = _Native();
  final eligible = {'a', 'b'};
  final levels = <String, int>{};
  final connections = {
    for (final device in ['a', 'b'])
      device: DeviceConnection(
        client: _Client(),
        device: AdbDevice(
          id: 'connection-$device',
          serial: device,
          state: 'device',
        ),
      ),
  };
  final emissions = <(String, String, AudioSourceJson)>[];
  void Function(AudioSourceJson)? onEvent;
  late final DeviceAudioSourceCoordinator owner;
}

final class _Client implements AdbClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Native implements NativeScrcpyApi, NativeScrcpySourceStatusApi {
  final creations = <(String, ScrcpyOptions)>[];
  final created = Completer<void>();
  final started = <String>[];
  final stopped = <String>[];
  final inspected = <(String, int)>[];
  final events = <String, StreamController<ScrcpyEvent>>{};
  Completer<String>? creationGate;
  Completer<ScrcpySessionInfo>? startGate;
  final startEntered = Completer<void>();
  Completer<void>? stopGate;
  int stopFailures = 0;
  final statusReads = <(String, String, String)>[];
  ScrcpySourceState sourceState = ScrcpySourceState.streaming;

  @override
  Future<ScrcpySourceStatus> sourceStatus({
    required String connectionId,
    required String captureRef,
    required String sourceId,
  }) async {
    statusReads.add((connectionId, captureRef, sourceId));
    return ScrcpySourceStatus(
      captureRef: captureRef,
      sourceId: sourceId,
      generation: 4,
      kind: ScrcpySourceKind.audio,
      codec: 'pcm_s16le',
      status: sourceState,
      packets: 7,
      bytes: 4096,
    );
  }

  @override
  Future<String> createSession({
    required String connectionId,
    required ScrcpyOptions options,
  }) async {
    creations.add((connectionId, options));
    if (!created.isCompleted) created.complete();
    final id = creationGate == null
        ? 'capture-${creations.length}'
        : await creationGate!.future;
    events[id] = StreamController<ScrcpyEvent>.broadcast();
    return id;
  }

  ScrcpySessionInfo info(String id, {int generation = 1}) => ScrcpySessionInfo(
    id: id,
    deviceName: '设备',
    videoCodec: ScrcpyVideoCodec.h264,
    width: 0,
    height: 0,
    videoEnabled: false,
    audioEnabled: true,
    controlReady: false,
    audioSource: ScrcpyNativeSource(
      sourceId: id.codeUnits
          .map((code) => code.toRadixString(16))
          .join()
          .padRight(64, '0'),
      generation: generation,
      codec: 'pcm_s16le',
      width: 0,
      height: 0,
      attachAddress: 101,
      detachAddress: 102,
    ),
  );

  @override
  Future<ScrcpySessionInfo> startSession(String id) async {
    started.add(id);
    if (!startEntered.isCompleted) startEntered.complete();
    return startGate?.future ?? info(id);
  }

  @override
  Future<ScrcpySessionInfo> inspect(
    String captureRef, {
    int generation = 1,
  }) async {
    inspected.add((captureRef, generation));
    return info(captureRef, generation: generation);
  }

  @override
  Future<void> stopSession(String id) async {
    stopped.add(id);
    if (stopFailures > 0) {
      stopFailures--;
      throw const ScrcpyException('cleanup_unconfirmed');
    }
    await stopGate?.future;
  }

  @override
  ScrcpyEventObserver openEvents(String captureRef) =>
      observeFixtureEvents(events[captureRef]!.stream);

  @override
  Future<ScrcpyControlReceipt> sendControl(
    String id,
    ScrcpyControlMessage message,
  ) => throw UnsupportedError('纯音频不发送控制消息');
}
