import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/control/models/video_renderer_receipt.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/video_recovery.dart';

void main() {
  test('旧捕获、旧 renderer 和其他设备的失败不发布，也不停止当前输出', () async {
    final fixture = _Recovery(_output(capture: 2, renderer: 3));
    for (final old in [
      _failure(capture: 1, renderer: 3),
      _failure(capture: 2, renderer: 2),
      _failure(capture: 2, renderer: 3, device: 'other'),
    ]) {
      fixture.recovery.handle(old);
    }
    await Future<void>.delayed(Duration.zero);
    expect(fixture.outputs['session']!.captureGeneration, 2);
    expect(fixture.outputs['session']!.generation, 3);
    expect(fixture.events, isEmpty);
    expect(fixture.closed, isEmpty);
    expect(fixture.stopped, isEmpty);
  });

  test('当前失败只发布一次完整类型事实，同步撤销输出并等待原捕获停止', () async {
    final fixture = _Recovery(_output(capture: 2, renderer: 3));
    final stopped = Completer<void>();
    fixture.stopping = stopped.future;
    var complete = false;
    final failing = fixture.recovery
        .fail(fixture.outputs['session']!, 'ended')
        .then((_) => complete = true);
    expect(fixture.outputs, isEmpty);
    final failure = fixture.events.single['data'] as VideoOutputFailed;
    expect(failure.sessionId, 'session');
    expect(failure.deviceId, 'device');
    expect(failure.captureGeneration, 2);
    expect(failure.generation, 3);
    expect(fixture.closed, ['session']);
    expect(fixture.stopped, ['session']);
    fixture.recovery.handle(_failure(capture: 2, renderer: 3));
    expect(fixture.events, hasLength(1));
    await Future<void>.delayed(Duration.zero);
    expect(complete, isFalse);
    stopped.complete();
    await failing;
    expect(complete, isTrue);
  });

  test('画质切换期间旧输出失败不终止窗口，提交后只接受新绑定失败', () async {
    final fixture = _Recovery(_output());
    fixture.recovery.beginReconfigure('session');
    fixture.recovery.handle(_failure());
    expect(fixture.events, isEmpty);
    expect(fixture.closed, isEmpty);
    final replacement = _output(capture: 2, renderer: 2);
    fixture.recovery.handle(VideoOutputChanged(replacement));
    expect(fixture.outputs['session'], same(replacement));
    expect(fixture.events.single['data'], isA<VideoOutputChanged>());
    expect(fixture.ready.single.captureGeneration, 2);
    fixture.recovery.endReconfigure('session');
    fixture.recovery.handle(_failure());
    expect(fixture.events, hasLength(1));
    fixture.recovery.handle(_failure(capture: 2, renderer: 2));
    await Future<void>.delayed(Duration.zero);
    expect(fixture.events, hasLength(2));
    expect(fixture.closed, ['session']);
    expect(fixture.stopped, ['session']);
  });

  test('旧捕获即使 renderer 数值更大也不能发布变更或覆盖新输出', () {
    final fixture = _Recovery(_output(capture: 2, renderer: 2));
    fixture.recovery.handle(
      VideoOutputChanged(_output(capture: 1, renderer: 99)),
    );
    fixture.recovery.handle(
      VideoOutputChanged(_output(capture: 2, renderer: 1)),
    );
    fixture.recovery.handle(
      VideoOutputChanged(
        _output(capture: 2, renderer: 3).copyWith(deviceId: 'other'),
      ),
    );
    expect(fixture.events, isEmpty);
    expect(fixture.ready, isEmpty);
    expect(fixture.outputs['session']!.generation, 2);
    final next = _output(capture: 2, renderer: 3);
    fixture.recovery.handle(VideoOutputChanged(next));
    expect(fixture.events.single['data'], isA<VideoOutputChanged>());
    expect(fixture.outputs['session'], same(next));
    expect(fixture.ready.single.generation, 3);
  });

  test('帧尺寸只接受当前精确绑定的单调回执，旧纹理不能重新发布', () {
    final fixture = _Recovery(_output(capture: 2, renderer: 3));
    fixture.recovery.handle(
      VideoOutputFrame(_output(capture: 1, renderer: 99)),
    );
    fixture.recovery.handle(
      VideoOutputFrame(
        _output(capture: 2, renderer: 3).copyWith(textureId: 99, frameCount: 2),
      ),
    );
    expect(fixture.events, isEmpty);
    final frame = fixture.outputs['session']!.copyWith(
      frameCount: 2,
      decodedWidth: 200,
      decodedHeight: 100,
    );
    fixture.recovery.handle(VideoOutputFrame(frame));
    fixture.recovery.handle(VideoOutputFrame(frame));
    fixture.recovery.handle(VideoOutputFrame(frame.copyWith(frameCount: 1)));
    expect(fixture.events, hasLength(1));
    expect(fixture.events.single['data'], isA<VideoOutputFrame>());
    expect(fixture.frames.single.decodedWidth, 200);
    expect(fixture.outputs['session'], same(frame));
  });

  test('新捕获复用 renderer 代次时，帧计数从新绑定重新核验', () {
    final fixture = _Recovery(_output(capture: 2, renderer: 3));
    fixture.recovery.handle(
      VideoOutputFrame(
        _output(capture: 2, renderer: 3).copyWith(frameCount: 20),
      ),
    );
    final replacement = _output(capture: 3, renderer: 3);
    fixture.recovery.handle(VideoOutputChanged(replacement));
    final first = replacement.copyWith(
      frameCount: 1,
      decodedWidth: 300,
      decodedHeight: 200,
    );
    fixture.recovery.handle(VideoOutputFrame(first));
    expect(fixture.outputs['session'], same(first));
    expect(fixture.frames, hasLength(2));
    expect(fixture.frames.last.captureGeneration, 3);
    expect(
      (fixture.events.last['data'] as VideoOutputFrame).output,
      same(first),
    );
    fixture.recovery.handle(VideoOutputFrame(first.copyWith(frameCount: 0)));
    fixture.recovery.handle(
      VideoOutputFrame(
        _output(capture: 2, renderer: 3).copyWith(frameCount: 21),
      ),
    );
    expect(fixture.frames, hasLength(2));
  });

  test('源状态迟到失败不能结束读取期间替换的新输出', () async {
    final fixture = _Recovery(_output());
    final status = Completer<ScrcpySourceStatus>();
    fixture.status = status.future;
    final polling = fixture.recovery.poll('session');
    final replacement = _output(capture: 2, renderer: 2);
    fixture.recovery.handle(VideoOutputChanged(replacement));
    status.completeError(StateError('old source closed'));
    await polling;
    expect(fixture.outputs['session'], same(replacement));
    expect(fixture.closed, isEmpty);
    expect(fixture.stopped, isEmpty);
    expect(fixture.events.single['data'], isA<VideoOutputChanged>());
  });
}

class _Recovery {
  _Recovery(VideoOutputReceipt initial) {
    outputs[initial.sessionId] = initial;
    recovery = VideoRecovery(
      outputs: outputs,
      sourceStatus: (_) => status,
      stopCapture: (id) async {
        stopped.add(id);
        await stopping;
      },
      readyCapture: (receipt) async => ready.add(receipt),
      recordFrame: (receipt) async {
        frames.add(receipt);
        return true;
      },
      closeOutput: (id, {failure}) async => closed.add(id),
      emit: (event) {
        if (event['data'] case VideoOutputChanged(:final output)) {
          expect(outputs[output.sessionId], same(output));
        }
        events.add(event);
      },
      isDisposed: () => false,
    );
  }
  late final VideoRecovery recovery;
  final outputs = <String, VideoOutputReceipt>{};
  final events = <Map<String, dynamic>>[];
  final ready = <VideoRendererReceipt>[], frames = <VideoRendererReceipt>[];
  final closed = <String>[], stopped = <String>[];
  Future<void> stopping = Future.value();
  Future<ScrcpySourceStatus> status = Future.value(
    const ScrcpySourceStatus(
      captureRef: 'capture',
      sourceId: 'source',
      generation: 1,
      kind: .video,
      codec: 'h264',
      status: .streaming,
      packets: 1,
      bytes: 1,
    ),
  );
}

VideoOutputFailed _failure({
  int capture = 1,
  int renderer = 1,
  String device = 'device',
}) => VideoOutputFailed(
  sessionId: 'session',
  deviceId: device,
  reason: 'ended',
  captureGeneration: capture,
  generation: renderer,
);

VideoOutputReceipt _output({int capture = 1, int renderer = 1}) =>
    VideoOutputReceipt(
      sessionId: 'session',
      deviceId: 'device',
      relayId: 'relay-$capture-$renderer',
      textureId: renderer,
      decodedWidth: 100,
      decodedHeight: 200,
      codec: 'h264',
      generation: renderer,
      captureGeneration: capture,
      paused: false,
      frameCount: 1,
      decodedReceipts: 1,
      snapshotReceipts: 1,
    );
