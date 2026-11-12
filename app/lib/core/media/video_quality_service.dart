import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_capture.dart';
import 'package:scrcpy_connect/core/control/video_quality.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart'
    show RequestFailure;

/// 保存一次设备偏好，再依次重建当前窗口；停止或连接更换会撤销旧意图。
class VideoQualityService {
  VideoQualityService({
    required this.saveQuality,
    required this.listSessions,
    required this.reconfigure,
    required this.applyOutput,
    this.beginReconfigure,
    this.endReconfigure,
  });
  final Future<VideoQuality> Function(String, VideoQualityPatch) saveQuality;
  final Future<List<SessionActivity>> Function(String) listSessions;
  final Future<VideoCapture> Function(String, String, VideoQuality) reconfigure;
  final Future<void> Function(VideoCapture) applyOutput;
  final void Function(String)? beginReconfigure;
  final void Function(String)? endReconfigure;
  final _queues = <String, Future<void>>{};
  final _stopped = <String>{};
  final _deviceEpoch = <String, int>{};
  bool _disposed = false;

  void stopSession(String sessionId) {
    _stopped.add(sessionId);
    if (_stopped.length > 4096) _stopped.remove(_stopped.first);
  }

  void stopDevice(String deviceId) {
    _deviceEpoch[deviceId] = (_deviceEpoch[deviceId] ?? 0) + 1;
  }

  Future<VideoQualityApplication> change(
    String device,
    VideoQualityPatch patch,
  ) {
    if (device.isEmpty || device.contains('\u0000')) {
      throw const RequestFailure('invalid_argument', '缺少设备标识。');
    }
    final epoch = _deviceEpoch[device] ?? 0;
    return _serialize(device, () => _change(device, patch, epoch));
  }

  /// 读取旧偏好的启动先落定，再清点重建目标；后续启动只读取已保存的新偏好。
  Future<T> open<T>(String device, Future<T> Function() work) {
    final epoch = _deviceEpoch[device] ?? 0;
    return _serialize(device, () {
      if (!_current(device, epoch)) {
        throw const RequestFailure('cancelled', '本次画面打开已取消。');
      }
      return work();
    });
  }

  Future<T> _serialize<T>(String device, Future<T> Function() work) {
    final previous = _queues[device] ?? Future<void>.value();
    final result = previous.then((_) => work());
    final completed = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[device] = completed;
    return result.whenComplete(() {
      if (identical(_queues[device], completed)) _queues.remove(device);
    });
  }

  bool _current(String device, int epoch, [String? session]) =>
      !_disposed &&
      (_deviceEpoch[device] ?? 0) == epoch &&
      (session == null || !_stopped.contains(session));

  Future<VideoQualityApplication> _change(
    String device,
    VideoQualityPatch patch,
    int epoch,
  ) async {
    if (!_current(device, epoch)) {
      throw const RequestFailure('cancelled', '设备画面设置已取消。');
    }
    final quality = await saveQuality(device, patch);
    if (!_current(device, epoch)) {
      throw const RequestFailure('cancelled', '设置已保存，设备连接已变化，当前画面未重建。');
    }
    List<SessionActivity> listed;
    try {
      listed = await listSessions(device);
    } catch (error) {
      return VideoQualityApplication(
        current: quality,
        appliedToAll: false,
        appliedSessions: [],
        skippedSessions: [],
        failures: [_failure(error, '当前画面')],
        reason: '画面设置已保存，当前画面状态未能核实，请重试应用。',
      );
    }
    final sessions = listed
        .where(
          (session) =>
              session.deviceId == device &&
              !const {
                'stopped',
                'stopping',
                'disconnected',
              }.contains(session.status) &&
              !session.recordOnly,
        )
        .toList();
    final applied = <SessionActivity>[];
    final failures = <VideoQualityFailure>[];
    final skipped = <String>[];
    for (final session in sessions) {
      final id = session.sessionId;
      if (!_current(device, epoch, id)) {
        skipped.add(id);
        continue;
      }
      beginReconfigure?.call(id);
      try {
        final stream = await reconfigure(device, id, quality);
        if (!_current(device, epoch, id)) {
          skipped.add(id);
          continue;
        }
        if (stream.sessionId != id || stream.deviceId != device) {
          throw const RequestFailure('session_changed', '重建回执不属于当前设备画面。');
        }
        await applyOutput(stream);
        if (!_current(device, epoch, id)) {
          skipped.add(id);
          continue;
        }
        applied.add(session);
      } catch (error) {
        if (!_current(device, epoch, id)) {
          skipped.add(id);
          continue;
        }
        failures.add(_failure(error, session.name, id));
      } finally {
        endReconfigure?.call(id);
      }
    }
    return VideoQualityApplication(
      current: quality,
      appliedToAll: failures.isEmpty && _current(device, epoch),
      appliedSessions: applied,
      failures: failures,
      skippedSessions: skipped,
      reason: failures.isEmpty
          ? applied.isEmpty
                ? '画面设置已保存。'
                : '当前画面与后续画面已使用此设置。'
          : '画面设置已保存，部分当前画面尚未应用。',
    );
  }

  void dispose() => _disposed = true;
}

VideoQualityFailure _failure(Object error, String name, [String? sessionId]) =>
    VideoQualityFailure(
      sessionId: sessionId,
      name: name,
      reason: error is RequestFailure ? error.message : '$error',
      code: error is RequestFailure ? error.code : null,
    );
