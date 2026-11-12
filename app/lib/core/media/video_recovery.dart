import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/control/models/video_renderer_receipt.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';

/// 将本地输出观察关联到已提交捕获；候选输出在提交前仍归播放器所有者持有。
class VideoRecovery {
  VideoRecovery({
    required this.outputs,
    required this.sourceStatus,
    required this.stopCapture,
    required this.readyCapture,
    required this.recordFrame,
    required this.closeOutput,
    required this.emit,
    required this.isDisposed,
  });
  final Map<String, VideoOutputReceipt> outputs;
  final Future<ScrcpySourceStatus> Function(String sourceId) sourceStatus;
  final Future<void> Function(String sessionId) stopCapture;
  final Future<void> Function(VideoRendererReceipt) readyCapture;
  final Future<bool> Function(VideoRendererReceipt) recordFrame;
  final Future<void> Function(String, {RequestFailure? failure}) closeOutput;
  final void Function(Map<String, dynamic>) emit;
  final bool Function() isDisposed;

  final _monitors = <String, Timer>{};
  final _polling = <String>{};
  final _reconfigurations = <String, _Reconfiguration>{};
  final _dimensionFrames = <String, ({int generation, int frames})>{};

  void beginReconfigure(String id) =>
      _reconfigurations[id] = _Reconfiguration.changing;
  void retainFailedOutput(String id) =>
      _reconfigurations[id] = _Reconfiguration.failed;
  void forget(String id) {
    _reconfigurations.remove(id);
    _dimensionFrames.remove(id);
  }

  void endReconfigure(String id) {
    if (_reconfigurations[id] == _Reconfiguration.changing) {
      _reconfigurations.remove(id);
    }
  }

  bool _owns(VideoOutputReceipt output) {
    final current = outputs[output.sessionId];
    return !isDisposed() && current != null && output.sameBinding(current);
  }

  void monitor(String id) {
    _monitors.remove(id)?.cancel();
    _monitors[id] = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_polling.add(id)) return;
      unawaited(poll(id).whenComplete(() => _polling.remove(id)));
    });
  }

  /// 先撤销本地绑定与监视，再等待播放器释放；失败清理由原播放器持有并重试。
  Future<void> close(String id, {RequestFailure? failure}) async {
    forget(id);
    if (const bool.fromEnvironment('CONNECT_DIAGNOSTICS')) {
      debugPrint(
        '[connect.video] close session=$id from=${StackTrace.current}',
      );
    }
    _monitors.remove(id)?.cancel();
    outputs.remove(id);
    await closeOutput(id, failure: failure);
  }

  Future<void> poll(String id) async {
    final monitor = _monitors[id];
    bool current() => !isDisposed() && identical(_monitors[id], monitor);
    final output = outputs[id];
    if (_reconfigurations.containsKey(id) ||
        !current() ||
        output == null ||
        !_owns(output)) {
      return;
    }
    try {
      final status = await sourceStatus(output.relayId);
      if (!current() || !_owns(output)) return;
      if (status.status == ScrcpySourceState.closed) {
        await fail(output, '远端视频输入已结束。');
      }
    } catch (error) {
      if (current()) await fail(output, '画面恢复失败，请重新打开：$error');
    }
  }

  Future<void> fail(VideoOutputReceipt output, String reason) async {
    final id = output.sessionId;
    if (_reconfigurations.containsKey(id) || !_owns(output)) return;
    // 同步认领精确输出；迟到失败不能停止替换后的所有者。
    outputs.remove(id);
    _dimensionFrames.remove(id);
    final closing = _close(id);
    emit(
      VideoOutputFailed(
        sessionId: id,
        deviceId: output.deviceId,
        captureGeneration: output.captureGeneration,
        generation: output.generation,
        reason: reason,
      ).toApplicationEvent(),
    );
    await Future.wait([closing, _stop(id)]);
  }

  Future<void> _close(String id) async {
    try {
      await close(id);
    } catch (_) {
      /* 原生释放失败仍保持终态与重试责任。 */
    }
  }

  Future<void> _stop(String id) async {
    try {
      await stopCapture(id);
    } catch (_) {
      /* 并发关闭可能已经停止此精确会话。 */
    }
  }

  void _dimensions(VideoOutputFrame event) {
    final data = event.output, id = event.output.sessionId;
    final output = outputs[id];
    if (output == null ||
        _reconfigurations.containsKey(id) ||
        !_owns(output) ||
        !data.sameBinding(output)) {
      return;
    }
    final frames = data.frameCount, previous = _dimensionFrames[id];
    final lastFrames = previous?.generation == data.generation
        ? previous!.frames
        : 0;
    if (frames == null ||
        frames <= lastFrames ||
        data.decodedWidth < 1 ||
        data.decodedHeight < 1 ||
        data.decodedWidth > 16384 ||
        data.decodedHeight > 16384) {
      return;
    }
    _dimensionFrames[id] = (generation: data.generation, frames: frames);
    outputs[id] = data;
    emit(event.toApplicationEvent());
    unawaited(
      recordFrame(data.rendererReceipt).catchError((Object _) => false),
    );
  }

  void handle(VideoOutputEvent event) {
    if (isDisposed()) return;
    if (event is VideoOutputFrame) {
      _dimensions(event);
      return;
    }
    switch (event) {
      case VideoOutputFailed(
        :final sessionId,
        :final deviceId,
        :final captureGeneration,
        :final generation,
        :final reason,
      ):
        final current = outputs[sessionId];
        if (current != null &&
            current.deviceId == deviceId &&
            current.captureGeneration == captureGeneration &&
            current.generation == generation) {
          unawaited(fail(current, reason));
        }
      case VideoOutputChanged(:final output):
        final current = outputs[output.sessionId];
        if (current == null ||
            current.deviceId != output.deviceId ||
            output.captureGeneration < current.captureGeneration ||
            (output.captureGeneration == current.captureGeneration &&
                output.generation <= current.generation)) {
          return;
        }
        outputs[output.sessionId] = output;
        emit(event.toApplicationEvent());
        unawaited(
          readyCapture(output.rendererReceipt).catchError((Object _) {
            // 迟到回执不能恢复停止窗口。
          }),
        );
      case VideoOutputReady():
        emit(event.toApplicationEvent());
      case VideoOutputFrame():
        break;
    }
  }
}

enum _Reconfiguration { changing, failed }
