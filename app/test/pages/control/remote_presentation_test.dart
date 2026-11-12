import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/models/video_session_view.dart';
import 'package:scrcpy_connect/core/media/models/recovered_video_session.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';

void main() {
  test('画质的核心就绪与输出 renderer 不同代时保持冻结，旧输出不覆盖已收到的新输出', () {
    final presentation = _started();
    final original = presentation.session!;
    presentation.updateSession(
      original.copyWith(
        session: original.session.copyWith(
          qualityRebuilding: true,
          qualityRebuildTarget: 2,
        ),
        output: null,
      ),
    );
    final ready = _view(capture: 2, renderer: 3, output: null);
    presentation.updateSession(
      ready.copyWith(
        session: ready.session.copyWith(qualityRebuildOutcome: .applied),
      ),
    );
    expect(
      presentation.output(_output(capture: 2, renderer: 4), verified: true),
      isFalse,
    );
    expect(
      presentation.output(_output(capture: 2, renderer: 3), verified: true),
      isFalse,
    );
    expect(presentation.qualityRebuilding, isTrue);
    expect(_canControl(presentation), isFalse);
    final latest = _view(capture: 2, renderer: 4, output: null);
    presentation.updateSession(
      latest.copyWith(
        session: latest.session.copyWith(qualityRebuildOutcome: .applied),
      ),
    );
    expect(presentation.qualityRebuilding, isFalse);
    expect(presentation.session!.output!.generation, 4);
    expect(_canControl(presentation), isTrue);
  });

  for (final outputFirst in [false, true]) {
    test('画质重建${outputFirst ? '输出' : '核心'}先到，必须双回执同代才恢复控制', () {
      final presentation = _started();
      final original = presentation.session!;
      final binding = presentation.binding;
      final rebuilding = original.copyWith(
        session: original.session.copyWith(
          qualityRebuilding: true,
          qualityRebuildTarget: 2,
          qualityRebuildOutcome: .rebuilding,
        ),
        output: null,
      );
      expect(presentation.updateSession(rebuilding), isTrue);
      expect(presentation.binding, isNot(binding));
      expect(_canControl(presentation), isFalse);
      expect(presentation.session!.output, same(original.output));
      final ready = _view(capture: 2, renderer: 2, output: null);
      final next = _output(capture: 2, renderer: 2, width: 200, height: 100);
      final applied = ready.copyWith(
        session: ready.session.copyWith(
          width: 200,
          height: 100,
          qualityRebuildOutcome: .applied,
        ),
      );
      if (outputFirst) {
        expect(presentation.output(next, verified: true), isFalse);
      } else {
        presentation.updateSession(applied);
      }
      expect(presentation.qualityRebuilding, isTrue);
      expect(_canControl(presentation), isFalse);
      expect(presentation.imageWidth, 100);
      if (outputFirst) {
        presentation.updateSession(applied);
      } else {
        expect(presentation.output(next, verified: true), isTrue);
      }
      expect(presentation.qualityRebuilding, isFalse);
      expect(presentation.session!.session.captureGeneration, 2);
      expect(presentation.session!.session.generation, 2);
      expect(presentation.session!.wake, original.wake);
      expect(presentation.imageWidth, 200);
      expect(presentation.imageHeight, 100);
      expect(_canControl(presentation), isTrue);
      expect(presentation.output(_output(), verified: true), isFalse);
      expect(
        presentation.acceptsFailure(captureGeneration: 1, generation: 99),
        isFalse,
      );
      expect(_canControl(presentation), isTrue);
    });
  }

  test('同一捕获的旧 renderer 只保留像素，不能覆盖当前核心代次或建立首帧', () {
    final presentation = RemotePresentation();
    final retained = _view(renderer: 3, output: _output(renderer: 2));
    expect(retained.outputRetained, isTrue);
    _bind(presentation, retained, retained: true);
    expect(presentation.session!.session.generation, 3);
    expect(presentation.session!.output!.generation, 2);
    expect(presentation.awaitingFirstFrame, isTrue);
    expect(presentation.qualityRebuilding, isFalse);
    expect(_canControl(presentation), isFalse);
    expect(
      presentation.acceptsFailure(captureGeneration: 1, generation: 2),
      isFalse,
    );
    final epoch = presentation.beginResume();
    expect(
      presentation.completeResume(
        epoch,
        VideoPlaybackReceipt(
          session: retained.session,
          output: _output(renderer: 3),
        ),
        ownerCurrent: true,
      ),
      RemoteResumeResult.ready,
    );
    expect(presentation.session!.session.generation, 3);
    expect(_canControl(presentation), isTrue);
  });

  test('帧遥测不能建立首帧或替换 renderer，画面尺寸不匹配时禁止输入', () {
    final presentation = RemotePresentation();
    _bind(presentation, _view(output: null));
    expect(presentation.output(_output()), isFalse);
    expect(presentation.awaitingFirstFrame, isTrue);
    expect(presentation.output(_output(), verified: true), isTrue);
    expect(_canControl(presentation), isTrue);
    expect(presentation.output(_output(renderer: 2)), isFalse);
    final previous = presentation.binding;
    final state = presentation.session!.session.copyWith(
      width: 200,
      height: 100,
    );
    expect(
      presentation.updateSession(
        _view().copyWith(session: state, output: null),
      ),
      isTrue,
    );
    expect(presentation.binding, isNot(previous));
    expect(presentation.imageGeometryReady, isFalse);
    expect(_canControl(presentation), isFalse);
    expect(presentation.output(_output(width: 200, height: 100)), isTrue);
    expect(_canControl(presentation), isTrue);
  });

  test('旧捕获及旧 renderer 的失败和输出不能接管当前画面', () {
    final presentation = _started(capture: 2, renderer: 3);
    expect(
      presentation.output(_output(capture: 1, renderer: 99), verified: true),
      isFalse,
    );
    expect(
      presentation.output(_output(capture: 2, renderer: 2), verified: true),
      isFalse,
    );
    expect(
      presentation.output(
        _output(capture: 2, renderer: 3).copyWith(deviceId: 'other'),
        verified: true,
      ),
      isFalse,
    );
    expect(
      presentation.acceptsFailure(captureGeneration: 1, generation: 99),
      isFalse,
    );
    expect(
      presentation.acceptsFailure(captureGeneration: 2, generation: 2),
      isFalse,
    );
    expect(presentation.session!.session.generation, 3);
    expect(_canControl(presentation), isTrue);
  });

  test('画质失败保留旧图像，迟到成功不解除失败；明确重试后才接受新双回执', () {
    final presentation = _started();
    final original = presentation.session!;
    presentation.updateSession(
      original.copyWith(
        session: original.session.copyWith(
          qualityRebuilding: true,
          qualityRebuildTarget: 2,
        ),
        output: null,
      ),
    );
    final failed = _view(capture: 2, renderer: 2, output: null);
    presentation.updateSession(
      failed.copyWith(
        session: failed.session.copyWith(
          status: .failed,
          qualityRetryable: true,
          qualityRebuildOutcome: .failed,
        ),
      ),
    );
    expect(presentation.qualityRetryable, isTrue);
    expect(presentation.session!.output, same(original.output));
    expect(presentation.imageWidth, 100);
    expect(
      presentation.output(_output(capture: 2, renderer: 2), verified: true),
      isFalse,
    );
    expect(_canControl(presentation), isFalse);
    final retry = _view(capture: 2, renderer: 2, output: null);
    presentation.updateSession(
      retry.copyWith(
        session: retry.session.copyWith(
          qualityRebuilding: true,
          qualityRebuildTarget: 3,
        ),
      ),
    );
    final applied = _view(capture: 3, renderer: 3, output: null);
    presentation.updateSession(
      applied.copyWith(
        session: applied.session.copyWith(qualityRebuildOutcome: .applied),
      ),
    );
    expect(
      presentation.output(_output(capture: 3, renderer: 3), verified: true),
      isTrue,
    );
    expect(presentation.qualityRetryable, isFalse);
    expect(_canControl(presentation), isTrue);
  });

  test('后台和遮挡不被帧事件解除，旧恢复回执和换来源回执不能恢复控制', () {
    final presentation = _started();
    final original = presentation.session!;
    final receipt = VideoPlaybackReceipt(
      session: original.session,
      output: original.output!,
    );
    final epoch = presentation.beginResume();
    presentation.beginPause();
    presentation.lifecycleVisibility(false);
    expect(presentation.output(_output(width: 120), verified: true), isTrue);
    expect(presentation.paused, isTrue);
    expect(_canControl(presentation), isFalse);
    expect(
      presentation.completeResume(epoch, receipt, ownerCurrent: true),
      RemoteResumeResult.stale,
    );
    presentation.lifecycleVisibility(true);
    final current = presentation.beginResume();
    expect(
      presentation.completeResume(current, receipt, ownerCurrent: false),
      RemoteResumeResult.stale,
    );
    presentation.cover(true);
    expect(
      presentation.completeResume(current, receipt, ownerCurrent: true),
      RemoteResumeResult.stale,
    );
    presentation.cover(false);
    expect(
      presentation.completeResume(current, receipt, ownerCurrent: true),
      RemoteResumeResult.ready,
    );
    expect(_canControl(presentation), isTrue);
  });

  test('恢复核验只认原会话，快照中的纹理需要新的恢复回执才解锁输入', () {
    final presentation = _started();
    final original = presentation.session!;
    presentation.beginReconciliation();
    final snapshot = RuntimeSnapshot(
      sequence: 1,
      settings: Preferences(),
      sessions: [
        RecoveredVideoSession(
          session: original.session,
          output: original.output,
          keepAwake: original.wake,
        ),
      ],
    );
    expect(
      presentation.reconcile(snapshot, packageName: null, deviceId: 'device'),
      isTrue,
    );
    expect(presentation.stateUnverified, isFalse);
    expect(_canControl(presentation), isFalse);
    expect(
      presentation.reconcile(snapshot, packageName: null, deviceId: 'device'),
      isFalse,
    );
    final epoch = presentation.beginResume();
    expect(
      presentation.completeResume(
        epoch,
        VideoPlaybackReceipt(
          session: original.session,
          output: original.output!,
        ),
        ownerCurrent: true,
      ),
      RemoteResumeResult.ready,
    );
    expect(_canControl(presentation), isTrue);
    presentation.beginReconciliation();
    presentation.reconcile(
      RuntimeSnapshot(sequence: 2, settings: Preferences()),
      packageName: null,
      deviceId: 'device',
    );
    expect(presentation.sessionEnded, isTrue);
    expect(presentation.session!.textureId, isNull);
    expect(_canControl(presentation), isFalse);
  });
}

bool _canControl(RemotePresentation value) =>
    value.canSendInput(foreground: true, ownerCurrent: true);

RemotePresentation _started({int capture = 1, int renderer = 1}) {
  final presentation = RemotePresentation();
  _bind(
    presentation,
    _view(
      capture: capture,
      renderer: renderer,
      output: _output(capture: capture, renderer: renderer),
    ),
  );
  return presentation;
}

void _bind(
  RemotePresentation presentation,
  VideoSessionView view, {
  bool retained = false,
}) => presentation.bindStart(
  view,
  retained: retained,
  recoveringConnection: false,
  submittedAppStart: false,
);

VideoSessionView _view({
  int capture = 1,
  int renderer = 1,
  VideoOutputReceipt? output,
}) => VideoSessionView(
  session: VideoSessionSnapshot(
    sessionId: 'session',
    deviceId: 'device',
    name: 'Phone',
    kind: .screen,
    status: .streaming,
    captureGeneration: capture,
    generation: renderer,
    width: 100,
    height: 200,
  ),
  wake: const KeepAwakeSnapshot(deviceId: 'device', keepActive: true),
  output: output,
);

VideoOutputReceipt _output({
  int capture = 1,
  int renderer = 1,
  int width = 100,
  int height = 200,
}) => VideoOutputReceipt(
  sessionId: 'session',
  deviceId: 'device',
  relayId: 'relay-$capture-$renderer',
  textureId: renderer,
  decodedWidth: width,
  decodedHeight: height,
  codec: 'h264',
  generation: renderer,
  captureGeneration: capture,
  paused: false,
  frameCount: 1,
  decodedReceipts: 1,
  snapshotReceipts: 1,
);
