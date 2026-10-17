import 'dart:async';

import 'video_player_port.dart';
import 'video_presentation.dart';

/// Connects local output observations to the committed core session. Candidate
/// outputs remain owned by PortableVideoOutputs until their changed receipt.
class VideoOutputLifecycle {
  VideoOutputLifecycle({
    required this.outputs,
    required this.core,
    required this.closeOutput,
    required this.reattachOutput,
    required this.emit,
    required this.isDisposed,
  });

  final Map<String, VideoJson> outputs;
  final VideoCoreRequest core;

  /// Retires the local output and its monitor before its first asynchronous
  /// wait, so a later session can open while native cleanup is still pending.
  final Future<void> Function(String) closeOutput;
  final Future<VideoJson> Function(String, VideoJson) reattachOutput;
  final void Function(VideoJson) emit;
  final bool Function() isDisposed;

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
    if (!current() || output == null || !_owns(output)) return;
    try {
      final status = await core('media.status', {'relayId': output['relayId']});
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
    if (id is! String || !_owns(output)) return;
    // Claim this exact committed output synchronously. A second failure or a
    // delayed poll cannot stop it twice, and cleanup never looks up a new owner
    // after awaiting the remote stop acknowledgement.
    outputs.remove(id);
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
      // Failure remains terminal even if native release cannot be confirmed.
    }
  }

  Future<void> _stop(String id) async {
    try {
      await core('session.stop', {'sessionId': id});
    } catch (_) {
      // A concurrent stop or disconnect may already have ended this session.
    }
  }

  void handle(VideoJson event) {
    if (isDisposed()) return;
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
      core('session.ready', data).catchError((Object error) {
        // A stopped session cannot be revived by a late generation receipt.
        return <String, dynamic>{};
      }),
    );
  }
}
