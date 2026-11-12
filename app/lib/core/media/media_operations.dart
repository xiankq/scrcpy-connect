import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/video_display.dart';
import 'package:scrcpy_connect/core/control/video_quality.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/models/video_stop_requested.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/media/video_screenshots.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';

/// 媒体能力入口；输出、捕获与租约继续归 MediaPlayback 和 MediaCapture。
final class MediaOperations
    implements
        RemoteAudio,
        VideoSessions,
        VideoDisplayControl,
        VideoScreenshots,
        VideoQualityControl {
  MediaOperations({
    required this._videos,
    required this._audio,
    required this._screenshots,
    required this._quality,
    required this.resizeDisplayCapture,
    required this.onStopRequested,
    required this.isDisposed,
    required this.isStateUnverified,
    required this._diagnostics,
  });

  final VideoSessions _videos;
  final RemoteAudio _audio;
  final VideoScreenshots _screenshots;
  final VideoQualityControl _quality;
  final Future<void> Function(ControlTarget, VideoDisplaySize)
  resizeDisplayCapture;
  final void Function(VideoStopRequested) onStopRequested;
  final bool Function() isDisposed;
  final bool Function() isStateUnverified;
  final DiagnosticReporter _diagnostics;

  @override
  Future<void> resizeDisplay(ControlTarget target, VideoDisplaySize size) =>
      _videoOperation(
        'session.display',
        target.deviceId,
        () => resizeDisplayCapture(target, size),
        sessionId: target.sessionId,
        verified: true,
      );

  @override
  Future<VideoScreenshot> captureScreenshot(String sessionId) =>
      _videoOperation(
        'session.screenshot',
        null,
        () => _screenshots.captureScreenshot(sessionId),
        sessionId: sessionId,
      );

  @override
  Future<VideoQualityOptions> readVideoQualityOptions(String deviceId) =>
      _videoOperation(
        'session.quality.options',
        deviceId,
        () => _quality.readVideoQualityOptions(deviceId),
      );
  @override
  Future<VideoQualityApplication> changeVideoQuality(
    String deviceId,
    VideoQualityPatch patch,
  ) => _videoOperation(
    'session.quality',
    deviceId,
    () => _quality.changeVideoQuality(deviceId, patch),
    verified: true,
  );

  Future<T> _videoOperation<T>(
    String label,
    String? deviceId,
    Future<T> Function() action, {
    bool verified = false,
    String? sessionId,
  }) async {
    if (isDisposed()) throw const RequestFailure('disposed', '连接界面已关闭。');
    for (final id in [?deviceId, ?sessionId]) {
      if (id.isEmpty || id.contains('\u0000')) {
        throw const RequestFailure('invalid_argument', '画面身份无效。');
      }
    }
    if (verified && isStateUnverified()) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    final details = {'deviceId': ?deviceId, 'sessionId': ?sessionId};
    try {
      final result = await action();
      _diagnostics.command(label, details, watch.elapsedMilliseconds);
      return result;
    } catch (error, stack) {
      final failure = error is AdbException
          ? RequestFailure(error.code, error.message)
          : error;
      _diagnostics.command(
        label,
        details,
        watch.elapsedMilliseconds,
        error: failure,
      );
      Error.throwWithStackTrace(failure, stack);
    }
  }

  @override
  Future<List<DeviceAudioSnapshot>> readAudioSources({String? deviceId}) =>
      _audioOperation(
        'audio.sources',
        deviceId,
        () => _audio.readAudioSources(deviceId: deviceId),
      );
  @override
  Future<Set<String>> readAudioEligibleDevices() => _audioOperation(
    'audio.eligibility',
    null,
    _audio.readAudioEligibleDevices,
  );
  @override
  Future<DeviceAudioPlayback> startAudio(String deviceId) => _audioOperation(
    'audio.start',
    deviceId,
    () => _audio.startAudio(deviceId),
    verified: true,
  );
  @override
  Future<void> stopAudio(DeviceAudioTarget target) => _audioOperation(
    'audio.stop',
    target.deviceId,
    () => _audio.stopAudio(target),
    sourceId: target.sourceId,
  );
  @override
  Future<DeviceAudioPlayback> pauseAudio(DeviceAudioTarget target) =>
      _audioOperation(
        'audio.pause',
        target.deviceId,
        () => _audio.pauseAudio(target),
        sourceId: target.sourceId,
      );
  @override
  Future<DeviceAudioPlayback> resumeAudio(DeviceAudioTarget target) =>
      _audioOperation(
        'audio.resume',
        target.deviceId,
        () => _audio.resumeAudio(target),
        sourceId: target.sourceId,
        verified: true,
      );
  @override
  Future<DeviceAudioPlayback> changeAudioVolume(
    DeviceAudioTarget target, {
    double? volume,
    bool? muted,
  }) => _audioOperation(
    'audio.volume',
    target.deviceId,
    () => _audio.changeAudioVolume(target, volume: volume, muted: muted),
    sourceId: target.sourceId,
  );

  Future<T> _audioOperation<T>(
    String label,
    String? deviceId,
    Future<T> Function() action, {
    String? sourceId,
    bool verified = false,
  }) async {
    if (isDisposed()) throw const RequestFailure('disposed', '连接界面已关闭。');
    if (deviceId != null && (deviceId.isEmpty || deviceId.contains('\u0000')) ||
        sourceId != null && (sourceId.isEmpty || sourceId.contains('\u0000'))) {
      throw const RequestFailure('invalid_argument', '声音来源身份无效。');
    }
    if (verified && isStateUnverified()) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    final details = {'deviceId': ?deviceId, 'sourceId': ?sourceId};
    try {
      final result = await action();
      _diagnostics.command(label, details, watch.elapsedMilliseconds);
      return result;
    } catch (error, stack) {
      final failure = error is AdbException
          ? RequestFailure(error.code, error.message)
          : error;
      _diagnostics.command(
        label,
        details,
        watch.elapsedMilliseconds,
        error: failure,
      );
      Error.throwWithStackTrace(failure, stack);
    }
  }

  @override
  Future<List<VideoSessionView>> readVideoSessions({String? deviceId}) =>
      _videoOperation(
        'session.list',
        deviceId,
        () => _videos.readVideoSessions(deviceId: deviceId),
      );
  @override
  Future<VideoSessionView> startVideo(VideoSessionPlan plan) => _videoOperation(
    'session.start',
    plan.deviceId,
    () => _videos.startVideo(plan),
    sessionId: plan.sessionId,
    verified: true,
  );
  @override
  Future<VideoStopReceipt> stopVideo(
    ControlTarget target, {
    bool keepLaunchRecord = false,
  }) => _videoOperation('session.stop', target.deviceId, () {
    if (target.sessionId case final id?) {
      onStopRequested(VideoStopRequested(id));
    }
    return _videos.stopVideo(target, keepLaunchRecord: keepLaunchRecord);
  }, sessionId: target.sessionId);
  @override
  Future<VideoPlaybackReceipt> pauseVideo(ControlTarget target) =>
      _videoOperation(
        'session.pause',
        target.deviceId,
        () => _videos.pauseVideo(target),
        sessionId: target.sessionId,
        verified: true,
      );
  @override
  Future<VideoPlaybackReceipt> resumeVideo(ControlTarget target) =>
      _videoOperation(
        'session.resume',
        target.deviceId,
        () => _videos.resumeVideo(target),
        sessionId: target.sessionId,
        verified: true,
      );
}
