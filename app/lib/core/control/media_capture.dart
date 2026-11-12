import 'package:media_codec/media_codec.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/control/control_session_service.dart';
import 'package:scrcpy_connect/core/control/device_wake_service.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_capture.dart';
import 'package:scrcpy_connect/core/control/models/video_renderer_receipt.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/video_display.dart';
import 'package:scrcpy_connect/core/control/video_quality.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/device_audio_service.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/settings/app_settings.dart';

/// 捕获的命名操作直接借用会话与设备音源所有者，不经过应用总分派器。
/// 设备设置与共享唤醒租约在捕获边界协调。
class MediaCapture {
  MediaCapture({
    required this._sessions,
    required this._audio,
    required this._keepAwake,
    required this._connectionForDevice,
    required this._preferences,
    required this._scrcpy,
  });

  final ControlSessionService _sessions;
  final DeviceAudioService _audio;
  final DeviceWakeService _keepAwake;
  final DeviceConnection? Function(String) _connectionForDevice;
  final AppSettings _preferences;
  final ScrcpyClient _scrcpy;

  Future<VideoQuality> saveQuality(
    String deviceId,
    VideoQualityPatch patch,
  ) async {
    await _preferences.read();
    final quality = await _sessions.selectVideoQuality(deviceId, patch);
    await _preferences.saveDeviceQuality(deviceId, quality.preferences);
    return quality;
  }

  Future<VideoQualityOptions> readVideoQualityOptions(String deviceId) async {
    await _preferences.read();
    return _sessions.readVideoQualityOptions(deviceId);
  }

  Future<List<SessionActivity>> activitySessions(String deviceId) =>
      _sessions.readActivitySessions(deviceId: deviceId);

  Future<List<VideoSessionSnapshot>> sessionsForDevice(String deviceId) =>
      _sessions.readSessions(deviceId: deviceId);
  VideoSessionSnapshot session(String id) =>
      _sessions.currentSessions().firstWhere((value) => value.sessionId == id);
  Future<VideoSessionSnapshot> startVideo(VideoSessionPlan plan) async {
    await _preferences.read();
    return _sessions.startSession(plan);
  }

  Future<VideoCapture> reconfigure(
    String deviceId,
    String sessionId,
    VideoQuality quality,
  ) => _sessions.reconfigureVideo(
    ControlTarget(deviceId: deviceId, sessionId: sessionId),
    quality,
  );

  Future<void> resizeDisplay(ControlTarget target, VideoDisplaySize size) =>
      _sessions.resizeDisplay(target, size);

  Future<void> readyVideo(VideoRendererReceipt receipt) =>
      _sessions.acceptRenderer(receipt);
  Future<bool> frameVideo(VideoRendererReceipt receipt) =>
      _sessions.acceptFrame(receipt);
  Future<MediaCodecSource> openAudioSource(String sourceId, int generation) =>
      _audio.openSource(sourceId, generation: generation);

  void videoOutputFailed(VideoCapture capture, Object error) => _sessions
      .rendererFailed(capture.sessionId, capture.captureGeneration, error);

  Future<List<VideoSessionSnapshot>> readVideoSessions({String? deviceId}) =>
      _sessions.readSessions(deviceId: deviceId);
  KeepAwakeSnapshot readWake(String deviceId) => _keepAwake.readWake(deviceId);

  Future<VideoStopReceipt> stopVideo(
    ControlTarget target, {
    bool keepLaunchRecord = false,
  }) async {
    final receipt = await _sessions.stopSession(
      target,
      keepLaunchRecord: keepLaunchRecord,
    );
    if (receipt.deviceId case final device?) {
      try {
        await _keepAwake.sync(device);
      } catch (_) {
        // 窗口捕获已关闭，设备共享租约仍由原所有者持有清理责任。
      }
      final wake = _keepAwake.readWake(device);
      final healthySharedLease =
          _sessions.hasAudioOwner(device) &&
          wake.keepActiveLeaseActive &&
          wake.healthy;
      if (!healthySharedLease && wake.hasCleanupEvidence) {
        return receipt.copyWith(wakeCleanup: wake);
      }
    }
    return receipt;
  }

  Set<String> get audioEligibleDevices => _sessions.audioEligibleDevices;
  Future<DeviceAudioSnapshot> startAudio(String deviceId) =>
      _audio.start(deviceId);
  Future<DeviceAudioSnapshot> readyAudio(AudioOutputReceipt receipt) async =>
      _audio.acceptReady(receipt);
  Future<DeviceAudioSnapshot> presentAudio(AudioOutputReceipt receipt) async =>
      _audio.acceptPresentation(receipt);
  Future<DeviceAudioSnapshot> applyAudioVolume(
    AudioOutputReceipt receipt,
  ) async => _audio.acceptVolume(receipt);
  DeviceAudioSnapshot prepareAudioPresentation(DeviceAudioTarget target) =>
      _audio.preparePresentation(target);
  AudioVolumeChange prepareAudioVolume(
    DeviceAudioTarget target, {
    double? volume,
    bool? muted,
  }) => _audio.prepareVolume(target, volume: volume, muted: muted);
  Future<void> stopAudio(String sourceId, String deviceId) async {
    await _audio.stop(deviceId, sourceId: sourceId);
  }

  Future<String?> stopDeviceAudio(DeviceAudioTarget target) =>
      _audio.stop(target.deviceId, sourceId: target.sourceId);
  Future<List<DeviceAudioSnapshot>> audioSources() async => _audio.snapshots();

  Future<VideoSessionSnapshot> pauseVideo(ControlTarget target) =>
      _sessions.setPaused(target, paused: true);
  Future<VideoSessionSnapshot> resumeVideo(ControlTarget target) =>
      _sessions.setPaused(target, paused: false);

  Future<ScrcpySourceStatus> sourceStatus(String sourceId) async {
    final sessions = _sessions.currentSessions();
    for (final session in sessions) {
      if (session.videoSourceId != sourceId) continue;
      final device = session.deviceId;
      final connection = _connectionForDevice(device);
      if (connection == null) {
        throw const RequestFailure('disconnected', '这台设备当前没有可用连接。');
      }
      final status = await _scrcpy.sourceStatus(
        connection.device,
        captureRef: session.captureRef!,
        sourceId: sourceId,
      );
      if (!identical(_connectionForDevice(device), connection)) {
        throw const RequestFailure('cancelled', '输入所属的设备连接已改变。');
      }
      return status;
    }
    return _audio.sourceStatus(sourceId);
  }
}
