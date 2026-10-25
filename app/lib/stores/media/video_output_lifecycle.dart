import 'package:scrcpy_connect/services/media/video_output_snapshot.dart';

import 'dart:async';

import 'package:scrcpy_connect/services/media/video_player_port.dart';

/// 将本地输出观察关联到已提交核心会话；候选输出在变更回执到达前仍归 VideoOutputCoordinator 持有。
class VideoOutputLifecycle {
  VideoOutputLifecycle({
    required this.outputs,
    required this.request,
    required this.closeOutput,
    required this.reattachOutput,
    required this.emit,
    required this.isDisposed,
  });

  final Map<String, VideoJson> outputs;
  final VideoRequest request;

  /// 第一次异步等待前回收本地输出及监视器，允许后续会话在旧原生清理期间打开。
  final Future<void> Function(String) closeOutput;
  final Future<VideoJson> Function(String, VideoJson) reattachOutput;
  final void Function(VideoJson) emit;
  final bool Function() isDisposed;

  final _reconfiguring = <String>{};
  final _retained = <String>{};
  final _dimensionFrames = <String, (int, int)>{};
  void beginReconfigure(String id) {
    _retained.remove(id);
    _reconfiguring.add(id);
  }

  void retainFailedOutput(String id) => _retained.add(id);
  void forget(String id) {
    _retained.remove(id);
    _reconfiguring.remove(id);
    _dimensionFrames.remove(id);
  }

  void endReconfigure(String id) => _reconfiguring.remove(id);

  bool _owns(VideoJson output) {
    final current = outputs[output['sessionId']];
    return !isDisposed() &&
        current != null &&
        const [
          'deviceId',
          'generation',
          'relayId',
          'textureId',
        ].every((key) => output[key] != null && output[key] == current[key]);
  }

  Future<void> poll(String id, {required bool Function() current}) async {
    final output = outputs[id];
    if ((_reconfiguring.contains(id) || _retained.contains(id)) ||
        !current() ||
        output == null ||
        !_owns(output)) {
      return;
    }
    try {
      final status = await request('media.status', {
        'relayId': output['relayId'],
      });
      if (!current() || !_owns(output)) return;
      if (status['endpoint'] is Map<Object?, Object?>) {
        final endpoint = VideoJson.from(status['endpoint'] as Map);
        if ((endpoint['generation'] as num? ?? 0) >
            (output['generation'] as num? ?? 0)) {
          await reattachOutput(id, endpoint);
          return;
        }
      }
      if (['closed', 'failed'].contains(status['status'])) {
        await fail(output, status['reason']?.toString() ?? '远端视频输入已结束。');
      }
    } catch (error) {
      if (current()) await fail(output, '画面恢复失败，请重新打开：$error');
    }
  }

  Future<void> fail(VideoJson output, String reason) async {
    final id = output['sessionId'];
    if (id is! String ||
        (_reconfiguring.contains(id) || _retained.contains(id)) ||
        !_owns(output)) {
      return;
    }
    // 同步认领精确的已提交输出，防止重复失败或迟到轮询二次停止。
    // 等待远程停止回执后，清理过程也不再查找新所有者。
    outputs.remove(id);
    _dimensionFrames.remove(id);
    final closing = _close(id);
    emit({
      'type': 'session.failed',
      'deviceId': output['deviceId'],
      'data': {'sessionId': id, 'reason': reason},
    });
    await Future.wait([closing, _stop(id)]);
  }

  Future<void> _close(String id) async {
    try {
      await closeOutput(id);
    } catch (_) {
      // 即使原生释放无法确认，失败仍保持终态。
    }
  }

  Future<void> _stop(String id) async {
    try {
      await request('session.stop', {'sessionId': id});
    } catch (_) {
      // 并发停止或断开可能已经结束该会话。
    }
  }

  void _dimensions(VideoJson event, VideoJson data) {
    final id = data['sessionId'];
    final output = outputs[id];
    if (id is! String ||
        output == null ||
        _reconfiguring.contains(id) ||
        _retained.contains(id) ||
        event['deviceId'] != output['deviceId'] ||
        !_owns(output) ||
        !const [
          'generation',
          'captureGeneration',
          'relayId',
          'textureId',
        ].every((key) => data[key] != null && data[key] == output[key])) {
      return;
    }
    final frames = data['frameCount'];
    final generation = data['generation'];
    final previous = _dimensionFrames[id];
    // 替换输出时回执可能保留诊断字段；新原生解码器有独立计数器，不能继承旧栅栏。
    final lastFrames = previous != null && previous.$1 == generation
        ? previous.$2
        : 0;
    final width = data['decodedWidth'], height = data['decodedHeight'];
    if (generation is! int ||
        frames is! int ||
        frames <= lastFrames ||
        width is! int ||
        height is! int ||
        width < 1 ||
        height < 1 ||
        width > 16384 ||
        height > 16384) {
      return;
    }
    _dimensionFrames[id] = (generation, frames);
    outputs[id] = mergeVideoOutputReceipt(output, data);
    emit(event);
    // 核心独立核验两个代际和纹理身份。
    unawaited(
      request(
        'session.frame',
        data,
      ).catchError((Object _) => <String, dynamic>{}),
    );
  }

  void handle(VideoJson event) {
    if (isDisposed()) return;
    final eventData = event['data'];
    if (event['type'] == 'session.frame' &&
        eventData is Map &&
        eventData['metadataOnly'] == true) {
      _dimensions(event, VideoJson.from(eventData));
      return;
    }
    if (event['type'] == 'session.output.failed' &&
        eventData is Map &&
        (_reconfiguring.contains(eventData['sessionId']) ||
            _retained.contains(eventData['sessionId']))) {
      return;
    }
    emit(event);
    if (event['type'] != 'session.output.changed' &&
        event['type'] != 'session.output.failed') {
      return;
    }
    final data = VideoJson.from(event['data'] as Map);
    final id = data['sessionId'];
    if (id is! String) return;
    final current = outputs[id];
    if (current == null || event['deviceId'] != current['deviceId']) return;
    final generation = data['generation'];
    final committedGeneration = current['generation'];
    if (generation is! int || committedGeneration is! int) return;
    if (event['type'] == 'session.output.failed') {
      if (generation == committedGeneration) {
        unawaited(fail(current, data['reason']?.toString() ?? '视频输入已结束。'));
      }
      return;
    }
    if (generation <= committedGeneration) return;
    outputs[id] = mergeVideoOutputReceipt(current, data);
    unawaited(
      request('session.ready', data).catchError((Object error) {
        // 迟到代际回执不能恢复已停止的会话。
        return <String, dynamic>{};
      }),
    );
  }
}
