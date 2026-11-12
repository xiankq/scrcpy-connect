import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/core/control/media_capture.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/scrcpy_capture_adapter.dart';
import 'package:scrcpy_connect/core/control/video_quality.dart';
import 'package:scrcpy_connect/core/control/video_quality_policy.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/audio_output_service.dart';
import 'package:scrcpy_connect/core/media/audio_player.dart';
import 'package:scrcpy_connect/core/media/media_intent.dart';
import 'package:scrcpy_connect/core/media/media_output_reconciliation.dart';
import 'package:scrcpy_connect/core/media/models/audio_output_event.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_changed.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/media/video_output_service.dart';
import 'package:scrcpy_connect/core/media/video_playback_service.dart';
import 'package:scrcpy_connect/core/media/video_quality_service.dart';
import 'package:scrcpy_connect/core/media/video_recovery.dart';
import 'package:scrcpy_connect/core/media/video_screenshots.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/utils/ordered_disposal.dart';

/// 拥有当前 Dart 附着的媒体输出、启动意图与释放回执。
/// 设备连接和原生捕获仍由执行层持有。
final class MediaPlayback
    implements
        VideoSessions,
        RemoteAudio,
        VideoScreenshots,
        VideoQualityControl {
  MediaPlayback({
    required MediaCapture Function() captures,
    required this.readCapturedAudio,
    required this.readSnapshot,
    required this.readSettings,
    required this.platform,
    required this.emit,
    required this.isDisposed,
    required this.requireVerifiedState,
    required this.dataDirectory,
    required ScrcpyCaptureAdapter Function() capture,
    this.diagnostics,
    this.audioPlayerFactory,
  }) : _createCapture = captures,
       _createAdapter = capture;

  final MediaCapture Function() _createCapture;
  MediaCapture? _capture;
  MediaCapture get captures => _capture ??= _createCapture();
  final Future<List<DeviceAudioSnapshot>> Function() readCapturedAudio;
  final Future<RuntimeSnapshot> Function() readSnapshot;
  final Future<Preferences> Function() readSettings;

  final AudioPlatformRequest platform;
  final void Function(Map<String, dynamic>) emit;
  final bool Function() isDisposed;
  final void Function() requireVerifiedState;
  final String dataDirectory;
  final ScrcpyCaptureAdapter Function() _createAdapter;
  late final ScrcpyCaptureAdapter capture = _createAdapter();
  final DiagnosticLog? diagnostics;
  final AudioPlayerFactory? audioPlayerFactory;
  bool _closing = false;
  bool get _disposed => _closing || isDisposed();
  final _textures = <String, VideoOutputReceipt>{};
  final _audioSources = <String, DeviceAudioSnapshot>{};
  final _audioClosings = <String, Future<void>>{};
  final _mediaIntents = _MediaIntentRegistry();
  AudioOutputService? _audioOutputsInstance;
  AudioOutputService get _audioOutputs =>
      _audioOutputsInstance ??= AudioOutputService(
        openSource: (id, generation) =>
            captures.openAudioSource(id, generation),
        sourceStatus: (id) => captures.sourceStatus(id),
        diagnostics: diagnostics,
        platform: platform,
        emit: _handleAudioOutput,
        isDisposed: () => _disposed,
        playerFactory: audioPlayerFactory,
      );
  VideoQualityService? _deviceQualityInstance;
  VideoQualityService get _deviceQuality =>
      _deviceQualityInstance ??= VideoQualityService(
        saveQuality: captures.saveQuality,
        listSessions: captures.activitySessions,
        reconfigure: captures.reconfigure,
        applyOutput: (stream) async {
          final id = stream.sessionId;
          VideoOutputReceipt output;
          try {
            output = await _videoOutputs.reconfigure(stream);
          } catch (error) {
            _videoLifecycle.retainFailedOutput(id);
            captures.videoOutputFailed(stream, error);
            rethrow;
          }
          if (_textures.containsKey(id)) _textures[id] = output;
          await captures.readyVideo(output.rendererReceipt);
        },
        beginReconfigure: (id) => _videoLifecycle.beginReconfigure(id),
        endReconfigure: (id) => _videoLifecycle.endReconfigure(id),
      );
  VideoOutputService? _videoOutputsInstance;
  VideoOutputService get _videoOutputs =>
      _videoOutputsInstance ??= VideoOutputService(
        openSource: capture.openSource,
        emit: (event) => _videoLifecycle.handle(event),
        diagnostics: diagnostics,
        isDisposed: () => _disposed,
      );
  VideoPlaybackService? _videoPresentationInstance;
  VideoPlaybackService get _videoPresentation =>
      _videoPresentationInstance ??= VideoPlaybackService(
        pauseCapture: captures.pauseVideo,
        resumeCapture: captures.resumeVideo,
        sessionsForDevice: captures.sessionsForDevice,
        pauseOutput: _videoOutputs.pause,
        resumeOutput: _videoOutputs.resume,
      );
  VideoRecovery? _videoLifecycleInstance;
  VideoRecovery get _videoLifecycle =>
      _videoLifecycleInstance ??= VideoRecovery(
        outputs: _textures,
        sourceStatus: (id) => captures.sourceStatus(id),
        stopCapture: (id) async {
          await captures.stopVideo(ControlTarget(sessionId: id));
        },
        readyCapture: captures.readyVideo,
        recordFrame: captures.frameVideo,
        closeOutput: (id, {failure}) async {
          await _videoOutputs.stop(id, failure: failure);
        },
        emit: emit,
        isDisposed: () => _disposed,
      );
  Future<void> _closeAudio(String id) {
    if (_audioClosings[id] case final pending?) return pending;
    final closing = _releaseAudio(id);
    _audioClosings[id] = closing;
    void finished() {
      if (identical(_audioClosings[id], closing)) _audioClosings.remove(id);
    }

    unawaited(
      closing.then<void>(
        (_) => finished(),
        onError: (Object _, StackTrace _) => finished(),
      ),
    );
    return closing;
  }

  Future<void> _releaseAudio(String id) async {
    _audioSources.remove(id);
    await _audioOutputsInstance?.stop(id);
  }

  void _handleAudioOutput(AudioOutputEvent event) {
    if (_disposed) return;
    emit(event.toApplicationEvent());
    final id = event.sourceId;
    final source = _audioSources[id];
    if (source == null || event.deviceId != source.deviceId) {
      return;
    }
    if (event is AudioOutputFailed) {
      // 等待前先认领精确所有者，防止重复或迟到的焦点事件二次停止或影响其他设备的替换源。
      _audioSources.remove(id);
      _mediaIntents.stop(id, audio: true);
      unawaited(() async {
        try {
          await captures.stopAudio(id, source.deviceId);
        } catch (_) {
          /* 精确源可能已经结束，不能仅按设备停止。 */
        } finally {
          await _closeAudio(id);
        }
      }());
    } else if (event case AudioPresentationChanged(:final receipt)) {
      unawaited(
        captures
            .presentAudio(receipt)
            .then<void>((_) {})
            .catchError((Object _) {}),
      );
    }
  }

  List<VideoDecoderCapability> _decoderCapabilities() =>
      _videoOutputs.capabilities();

  Future<void> retireUnownedAudio() async {
    for (final source in await readCapturedAudio()) {
      if (source.status != DeviceAudioStatus.stopped &&
          source.status != DeviceAudioStatus.error) {
        await captures.stopAudio(source.sourceId, source.deviceId);
      }
    }
  }

  Future<void> _ensureVideoDecoder(
    String deviceId, [
    VideoQualityPatch patch = const VideoQualityPatch(),
  ]) async {
    final quality = VideoQualityPolicy.resolveQuality(
      await readSettings(),
      deviceId,
      patch,
    );
    if (!_decoderCapabilities().any(
      (item) =>
          item.codec == quality.codec &&
          (item.evidence == VideoDecoderEvidence.verified || item.canAttempt),
    )) {
      throw RequestFailure(
        'decoder_unavailable',
        '本机尚未提供 ${quality.codec.name} 解码器，请选择其他视频编码。',
      );
    }
  }

  @override
  Future<VideoQualityOptions> readVideoQualityOptions(String deviceId) async {
    final result = await captures.readVideoQualityOptions(deviceId);
    final decoders = _decoderCapabilities();
    return result.copyWith(
      codecs: [
        for (final option in result.codecs)
          option.copyWith(
            decoder: decoders.firstWhere((item) => item.codec == option.codec),
          ),
      ],
    );
  }

  @override
  Future<VideoQualityApplication> changeVideoQuality(
    String deviceId,
    VideoQualityPatch patch,
  ) async {
    await _ensureVideoDecoder(deviceId, patch);
    return _deviceQuality.change(deviceId, patch);
  }

  @override
  Future<VideoScreenshot> captureScreenshot(String sessionId) async {
    if (_disposed) throw const RequestFailure('disposed', '媒体所有者已关闭。');
    final directory = await Directory('$dataDirectory/screenshots')
        .create(recursive: true);
    return _videoOutputs.screenshot(sessionId, directory: directory.path);
  }

  Future<RuntimeSnapshot> snapshot(bool Function() current) =>
      readAndReconcileMediaSnapshot(
        read: readSnapshot,
        videos: _textures,
        audios: _audioSources,
        closeVideo: (id) async => await _videoLifecycleInstance?.close(id),
        closeAudio: _closeAudio,
        current: current,
      );

  void handleApplicationEvent(Map<String, dynamic> event) {
    if (event['data'] case DeviceListChanged(:final devices)) {
      _mediaIntents.retainDevices({
        for (final device in devices)
          if (device.status == .connected) device.id,
      });
    }
    if (event['data'] case VideoSessionView(:final session)
        when !session.live) {
      final output = _textures[session.sessionId];
      if (output != null &&
          output.deviceId == session.deviceId &&
          (output.captureGeneration < session.captureGeneration ||
              (output.captureGeneration == session.captureGeneration &&
                  output.generation <= session.generation))) {
        unawaited(
          _videoLifecycleInstance
              ?.close(
                session.sessionId,
                failure: session.status == .failed
                    ? RequestFailure(
                        session.failureCode ?? 'session_failed',
                        session.reason ?? '被控端的画面连接意外结束，请重新打开。',
                      )
                    : null,
              )
              .catchError((Object _) {}),
        );
      }
    } else if (event['data'] case DeviceAudioChanged(:final snapshot)
        when snapshot.status == .stopped || snapshot.status == .error) {
      final current = _audioSources[snapshot.sourceId];
      if (current != null &&
          current.deviceId == snapshot.deviceId &&
          current.generation == snapshot.generation) {
        unawaited(_closeAudio(snapshot.sourceId));
      }
    }
  }

  Future<void> setVisible(bool visible) => _audioOutputs.setVisible(visible);
  Future<void> policy(bool enabled) => _audioOutputs.policy(enabled);
  Future<void> handlePlatformEvent(Map<String, dynamic> event) async {
    if (event['type'] == 'connections.stopped') {
      _mediaIntents.cancelAll();
      await Future.wait(_textures.keys.toList().map(_videoLifecycle.close));
      await Future.wait(_audioSources.keys.toList().map(_closeAudio));
    } else {
      await _audioOutputs.handlePlatformEvent(event);
    }
  }

  @override
  Future<List<VideoSessionView>> readVideoSessions({String? deviceId}) async {
    _checkVideoOpen();
    return List.unmodifiable([
      for (final session in await captures.readVideoSessions(
        deviceId: deviceId,
      ))
        VideoSessionView(
          session: session,
          output: _textures[session.sessionId],
          wake: captures.readWake(session.deviceId),
        ),
    ]);
  }

  @override
  Future<VideoSessionView> startVideo(VideoSessionPlan plan) async {
    _checkVideoOpen(verified: true);
    final intent = _mediaIntents.begin(plan.deviceId, audio: false);
    try {
      return await _deviceQuality.open(plan.deviceId, () async {
        _checkVideoOpen(verified: true, intent: intent);
        await _ensureVideoDecoder(plan.deviceId);
        _checkVideoOpen(intent: intent);
        final capture = await captures.startVideo(plan);
        final playback = await _startVideoOutput(capture, intent);
        return VideoSessionView(
          session: playback.session,
          output: playback.output,
          wake: captures.readWake(plan.deviceId),
        );
      });
    } finally {
      _mediaIntents.finish(intent);
    }
  }

  @override
  Future<VideoPlaybackReceipt> pauseVideo(ControlTarget target) =>
      _presentVideo(target, true);
  @override
  Future<VideoPlaybackReceipt> resumeVideo(ControlTarget target) =>
      _presentVideo(target, false);
  Future<VideoPlaybackReceipt> _presentVideo(
    ControlTarget target,
    bool paused,
  ) async {
    _checkVideoOpen(verified: true);
    final playback = await _videoPresentation.setPaused(target, paused: paused);
    final id = playback.session.sessionId;
    // 等待播放器期间可能已切换 renderer；借用当前核心事实，不能退回请求开始时的代次。
    final receipt = VideoPlaybackReceipt(
      session: captures.session(id),
      output: playback.output,
    );
    if (!paused && !_disposed && _textures.containsKey(id)) {
      _textures[id] = _mergeOutput(_textures[id], receipt.output);
      emit({
        'type': 'session.output.resumed',
        'deviceId': receipt.session.deviceId,
        'data': receipt,
      });
    }
    return receipt;
  }

  @override
  Future<VideoStopReceipt> stopVideo(
    ControlTarget target, {
    bool keepLaunchRecord = false,
  }) async {
    _checkVideoOpen();
    // 只有精确窗口身份才能同步撤销它的启动与质量意图。
    final id = target.sessionId;
    if (id != null) {
      _deviceQuality.stopSession(id);
      _videoLifecycle.forget(id);
      _mediaIntents.stop(id, audio: false);
    }
    final receipt = await captures.stopVideo(
      target,
      keepLaunchRecord: keepLaunchRecord,
    );
    _mediaIntents.stop(receipt.sessionId, audio: false);
    await _videoLifecycle.close(receipt.sessionId);
    return receipt;
  }

  void _checkVideoOpen({bool verified = false, MediaIntent? intent}) {
    if (_disposed || intent?.cancelled == true) {
      throw const RequestFailure('cancelled', '已停止本次打开，不会重新启动画面。');
    }
    if (verified) requireVerifiedState();
  }

  /// 撤销本设备已有质量与媒体启动意图，不停止其他设备或取得连接关闭权。
  void stopDeviceIntent(String deviceId) {
    _deviceQualityInstance?.stopDevice(deviceId);
    _mediaIntents.stopDevice(deviceId);
  }

  /// 连接所有者确认停止后，等待本设备现存及待重试的本机输出真正退出。
  Future<void> finishDeviceStop(String deviceId) async {
    for (final id
        in _textures.keys
            .where((id) => _textures[id]?.deviceId == deviceId)
            .toList()) {
      await _videoLifecycle.close(id);
    }
    for (final id
        in _audioSources.keys
            .where((id) => _audioSources[id]?.deviceId == deviceId)
            .toList()) {
      await _closeAudio(id);
    }
    // 页面快照已撤销也可能还有失败或超时的旧输出，仍按设备核对真实释放。
    await Future.wait([
      if (_videoOutputsInstance case final output?) output.stopDevice(deviceId),
      if (_audioOutputsInstance case final output?) output.stopDevice(deviceId),
    ]);
  }

  Future<DeviceAudioPlayback> _startAudioOutput(
    DeviceAudioSnapshot result,
    MediaIntent? intent,
  ) async {
    intent?.bind(result.sourceId);
    if (_disposed || intent?.cancelled == true) {
      await captures.stopAudio(result.sourceId, result.deviceId);
      throw const RequestFailure('cancelled', '已停止本次声音，不会重新启动。');
    }
    final id = result.sourceId;
    _audioSources[id] = result;
    try {
      final playback = await _audioOutputs.start(
        result,
        cancelled: () => _disposed || intent?.cancelled == true,
      );
      if (_disposed || intent?.cancelled == true) {
        throw const RequestFailure('cancelled', '已停止本次声音，不会重新启动。');
      }
      final ready = await captures.readyAudio(playback);
      if (_disposed || intent?.cancelled == true) {
        throw const RequestFailure('cancelled', '已停止本次声音，不会重新启动。');
      }
      return (source: ready, output: playback);
    } catch (_) {
      try {
        await captures.stopAudio(id, result.deviceId);
      } finally {
        await _closeAudio(id);
      }
      rethrow;
    }
  }

  Future<VideoPlaybackReceipt> _startVideoOutput(
    VideoSessionSnapshot result,
    MediaIntent? intent,
  ) async {
    final id = result.sessionId;
    intent?.bind(id);
    if (_disposed || intent?.cancelled == true) {
      await captures.stopVideo(
        ControlTarget(sessionId: id),
        keepLaunchRecord: result.packageName != null,
      );
      throw const RequestFailure('cancelled', '已停止本次画面，不会重新启动。');
    }
    try {
      final texture = await _videoOutputs.start(
        result.capture,
        cancelled: () => _disposed || intent?.cancelled == true,
      );
      if (_disposed || intent?.cancelled == true) {
        throw const RequestFailure('cancelled', '已停止本次画面，不会重新启动。');
      }
      _textures[id] = texture;
      await captures.readyVideo(texture.rendererReceipt);
      if (_disposed || intent?.cancelled == true) {
        throw const RequestFailure('cancelled', '已停止本次画面，不会重新启动。');
      }
      _videoLifecycle.monitor(id);
      return VideoPlaybackReceipt(
        session: captures.session(id),
        output: texture,
      );
    } catch (error) {
      final appLaunch = result.packageName != null;
      try {
        await captures.stopVideo(
          ControlTarget(sessionId: id),
          keepLaunchRecord: appLaunch,
        );
      } catch (_) {
        /* 保留原始输出错误。 */
      }
      await _videoLifecycle.close(id);
      if (appLaunch) {
        throw VideoStartUncertain(
          result.copyWith(
            status: .failed,
            launchOutcome: .unknown,
            textureId: null,
            failureCode: error is RequestFailure
                ? error.code
                : 'video_output_failed',
          ),
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<DeviceAudioSnapshot>> readAudioSources({
    String? deviceId,
  }) async => List.unmodifiable([
    for (final source in await readCapturedAudio())
      if (deviceId == null || source.deviceId == deviceId) source,
  ]);
  @override
  Future<Set<String>> readAudioEligibleDevices() async =>
      captures.audioEligibleDevices;

  @override
  Future<DeviceAudioPlayback> startAudio(String deviceId) async {
    _checkAudioOpen();
    final intent = _mediaIntents.begin(deviceId, audio: true);
    try {
      return await _startAudioOutput(
        await captures.startAudio(deviceId),
        intent,
      );
    } finally {
      _mediaIntents.finish(intent);
    }
  }

  @override
  Future<void> stopAudio(DeviceAudioTarget target) async {
    _checkAudioOpen();
    final source = target.sourceId;
    if (source != null) {
      _mediaIntents.stop(source, audio: true);
    } else {
      _mediaIntents.stopAudioDevice(target.deviceId);
    }
    final ids = [
      for (final entry in _audioSources.entries)
        if (source != null
            ? entry.key == source
            : entry.value.deviceId == target.deviceId)
          entry.key,
    ];
    await captures.stopDeviceAudio(target);
    for (final id in ids) {
      await _closeAudio(id);
    }
    if (source != null && !ids.contains(source)) {
      await _closeAudio(source);
    } else if (source == null) {
      await _audioOutputs.stopDevice(target.deviceId);
    }
  }

  @override
  Future<DeviceAudioPlayback> pauseAudio(DeviceAudioTarget target) =>
      _setAudioPaused(target, true);
  @override
  Future<DeviceAudioPlayback> resumeAudio(DeviceAudioTarget target) =>
      _setAudioPaused(target, false);
  Future<DeviceAudioPlayback> _setAudioPaused(
    DeviceAudioTarget target,
    bool paused,
  ) async {
    _checkAudioOpen();
    final source = captures.prepareAudioPresentation(target);
    final applied = paused
        ? await _audioOutputs.pause(source.sourceId)
        : await _audioOutputs.resume(source.sourceId);
    final updated = await captures.presentAudio(applied);
    return (source: updated, output: applied);
  }

  @override
  Future<DeviceAudioPlayback> changeAudioVolume(
    DeviceAudioTarget target, {
    double? volume,
    bool? muted,
  }) async {
    _checkAudioOpen();
    final proposed = captures.prepareAudioVolume(
      target,
      volume: volume,
      muted: muted,
    );
    final applied = await _audioOutputs.volume(
      proposed.target.sourceId!,
      volume: proposed.volume,
      muted: proposed.muted,
    );
    final updated = await captures.applyAudioVolume(applied);
    return (source: updated, output: applied);
  }

  void _checkAudioOpen() {
    if (_disposed) throw const RequestFailure('cancelled', '媒体所有者已关闭。');
  }

  OrderedDisposal? _disposal;
  void stopAdmission() {
    _closing = true;
    _deviceQualityInstance?.dispose();
    _mediaIntents.cancelAll();
  }

  Future<void> dispose() {
    stopAdmission();
    _disposal ??= _prepareDisposal();
    return _disposal!.run();
  }

  OrderedDisposal _prepareDisposal() {
    final pending = _mediaIntents.active.toList();
    final videoIds = {
      ..._textures.keys,
      ...pending.where((i) => !i.audio).expand((i) => i.ids),
    };
    final audioIds = {
      ..._audioSources.keys,
      ...pending.where((i) => i.audio).expand((i) => i.ids),
    };
    return OrderedDisposal([
      for (final id in videoIds) () => _videoLifecycle.close(id),
      () async => await _videoOutputsInstance?.dispose(),
      for (final id in audioIds)
        () async {
          final device = _audioSources[id]?.deviceId;
          if (device is String) {
            try {
              await captures.stopAudio(id, device);
            } catch (_) {
              /* 原生源可能已结束，本地输出仍需释放。 */
            }
          }
          await _closeAudio(id);
        },
      () async => await _audioOutputsInstance?.dispose(),
      () async {
        _textures.clear();
        _audioSources.clear();
        try {
          await Future.wait(pending.map((i) => i.done))
              .timeout(const Duration(seconds: 45));
        } on TimeoutException {
          // 迟到的原生启动继续由原所有者完成有界取消清理。
        }
      },
    ]);
  }
}

/// 登记在途启动意图，按设备或实际源撤销，并等待原启动完成。
class _MediaIntentRegistry {
  final active = <MediaIntent>{};
  MediaIntent begin(String deviceId, {required bool audio}) {
    final intent = MediaIntent(deviceId, audio);
    active.add(intent);
    return intent;
  }

  void finish(MediaIntent intent) {
    active.remove(intent);
    intent.complete();
  }

  void stop(String id, {required bool audio}) {
    for (final intent in active.where((i) => i.audio == audio)) {
      intent.stop(id);
    }
  }

  void stopDevice(String device) {
    for (final intent in active.where((i) => i.deviceId == device)) {
      intent.cancelled = true;
    }
  }

  void retainDevices(Set<String> connected) {
    for (final intent in active) {
      if (!connected.contains(intent.deviceId)) intent.cancelled = true;
    }
  }

  void stopAudioDevice(String device) {
    for (final intent in active.where((i) => i.deviceId == device && i.audio)) {
      intent.cancelled = true;
    }
  }

  void cancelAll() {
    for (final intent in active) {
      intent.cancelled = true;
    }
  }
}

VideoOutputReceipt _mergeOutput(
  VideoOutputReceipt? current,
  VideoOutputReceipt receipt,
) {
  if (current != null &&
      (current.captureGeneration > receipt.captureGeneration ||
          (current.captureGeneration == receipt.captureGeneration &&
              current.generation > receipt.generation))) {
    return current;
  }
  return receipt;
}
