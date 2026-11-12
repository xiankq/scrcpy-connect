import 'dart:async';

import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/activities/models/activity_cleanup_failed.dart';
import 'package:scrcpy_connect/core/control/app_launch_journal.dart';
import 'package:scrcpy_connect/core/control/control_session_service.dart';
import 'package:scrcpy_connect/core/control/device_wake_service.dart';
import 'package:scrcpy_connect/core/control/media_capture.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/device_audio_service.dart';
import 'package:scrcpy_connect/core/media/models/recovered_video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_session_view.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/settings/app_settings.dart';
import 'package:scrcpy_connect/utils/ordered_disposal.dart';

/// 控制捕获、设备音源与共享唤醒租约的所有者。
/// 只读空快照及关闭路径不会创建尚未使用的捕获能力。
final class CaptureResources {
  CaptureResources({
    required this._scrcpy,
    required this._readServerQueries,
    required this.requireConnection,
    required this.connectionForDevice,
    required this._records,
    required this._preferences,
    required this._launches,
    required this._diagnostics,
    required this.isDisposed,
    required this.isStateUnverified,
    required this.publish,
    required this.onCleanupFailure,
  });

  final ScrcpyClient _scrcpy;
  final ScrcpyServerQueries Function() _readServerQueries;
  final DeviceConnection Function(String) requireConnection;
  final DeviceConnection? Function(String) connectionForDevice;
  final DeviceRecordStorage _records;
  final AppSettings _preferences;
  final AppLaunchJournal _launches;
  final DiagnosticReporter _diagnostics;
  final bool Function() isDisposed;
  final bool Function() isStateUnverified;
  final void Function(Map<String, dynamic>) publish;
  final void Function(ActivityCleanupFailed) onCleanupFailure;
  final _cleanup = <Future<void>>{};
  bool _closed = false;
  void _checkCreation() {
    if (_closed || isDisposed()) {
      throw const RequestFailure('disposed', '控制捕获能力已关闭。');
    }
  }

  MediaCapture? _capture;
  MediaCapture get capture {
    if (_capture == null) _checkCreation();
    return _capture ??= MediaCapture(
      sessions: () => sessions,
      audio: () => audio,
      currentWake: () => _wake,
      readWake: readWake,
      connectionForDevice: connectionForDevice,
      preferences: _preferences,
      scrcpy: _scrcpy,
    );
  }

  ControlSessionService? _sessions;
  ControlSessionService get sessions {
    if (_sessions == null) _checkCreation();
    return _sessions ??= ControlSessionService(
      scrcpy: _scrcpy,
      requireConnection: requireConnection,
      launches: _launches,
      onClipboardFailure: _diagnostics.clipboardFailure,
      requireClipboardAccess: () {
        if (isDisposed()) {
          throw const RequestFailure('disposed', '连接界面已关闭。');
        }
        if (isStateUnverified()) {
          throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
        }
      },
      serverQueries: _readServerQueries,
      settings: () => _preferences.settings,
      emit: (type, device, data) => publishBusiness(type, device, data),
      onSessionChanged: _publishSession,
      onAudioEligibilityChanged: (id) {
        // 同步撤准入后记录实际排空，回调不等待其他设备，也不丢弃失败所有者。
        if (_audio case final audio?) {
          observeCleanup(audio.eligibilityChanged(id));
        }
        // 关闭最后窗口或未启用偏好时，只排空已有租约，不为通知创建新执行者。
        final needsWake =
            !_closed &&
            !isDisposed() &&
            _preferences.settings.deviceSettings[id]?.stayAwake == true &&
            (_sessions?.hasAudioOwner(id) ?? false);
        final wake = _wake ?? (needsWake ? keepAwake : null);
        if (wake != null) observeCleanup(wake.windowsChanged(id));
      },
    );
  }

  DeviceAudioService? _audio;
  DeviceAudioService get audio {
    if (_audio == null) _checkCreation();
    return _audio ??= DeviceAudioService(
      scrcpy: _scrcpy,
      requireConnection: requireConnection,
      hasAudioOwner: (id) => _sessions?.hasAudioOwner(id) ?? false,
      deviceName: (id) => _records.current.find(id)?.name ?? 'Android 设备',
      apiLevel: (id) => _records.current.find(id)?.apiLevel,
      emit: (type, device, data) => publishBusiness(type, device, data),
    );
  }

  DeviceWakeService? _wake;
  DeviceWakeService get keepAwake {
    if (_wake == null) _checkCreation();
    return _wake ??= DeviceWakeService(
      scrcpy: _scrcpy,
      requireConnection: requireConnection,
      hasWindowOwner: (id) => _sessions?.hasAudioOwner(id) ?? false,
      keepAwakeEnabled: (deviceId) =>
          _preferences.settings.deviceSettings[deviceId]?.stayAwake == true,
      emit: (type, device, data) => publishBusiness(type, device, data),
    );
  }

  List<VideoSessionSnapshot> currentSessions() =>
      _sessions?.currentSessions() ?? [];
  Future<List<VideoSessionSnapshot>> readSessions({String? deviceId}) async {
    if (_sessions case final sessions?) {
      return sessions.readSessions(deviceId: deviceId);
    }
    final records = await _launches.unresolved(deviceId: deviceId);
    // 等待存储期间可能首次打开控制页；已有会话须由同一所有者合并，不能丢失。
    if (_sessions case final sessions?) {
      return sessions.readSessions(deviceId: deviceId);
    }
    return List.unmodifiable([for (final record in records) record.snapshot]);
  }

  Future<List<RecoveredVideoSession>> readRecoverySessions() async => [
    for (final session in await readSessions())
      RecoveredVideoSession(
        session: session,
        keepAwake: readWake(session.deviceId),
      ),
  ];
  Future<List<SessionActivity>> readActivitySessions({
    String? deviceId,
  }) async => List.unmodifiable([
    for (final session in await readSessions(deviceId: deviceId))
      session.activity,
  ]);
  List<DeviceAudioSnapshot> audioSnapshots({bool activeOnly = false}) =>
      _audio?.snapshots(activeOnly: activeOnly) ?? [];
  KeepAwakeSnapshot readWake(String deviceId) =>
      _wake?.readWake(deviceId) ??
      KeepAwakeSnapshot.withoutLease(
        deviceId: deviceId,
        enabled:
            _preferences.settings.deviceSettings[deviceId]?.stayAwake == true,
        hasWindowOwner: _sessions?.hasAudioOwner(deviceId) ?? false,
      );

  void _publishSession(
    VideoSessionChange change,
    VideoSessionSnapshot session,
  ) {
    if (_closed || isDisposed()) return;
    publish({
      'type': 'session.${change.name}',
      'deviceId': session.deviceId,
      'data': VideoSessionView(
        session: session,
        wake: readWake(session.deviceId),
      ),
    });
  }

  void observeCleanup(Future<void> work) {
    _cleanup.add(work);
    unawaited(
      work.then<void>(
        (_) => _cleanup.remove(work),
        onError: (Object error, StackTrace stack) {
          _cleanup.remove(work);
          onCleanupFailure(ActivityCleanupFailed('$error'));
        },
      ),
    );
  }

  void publishBusiness(String type, String? device, Map<String, Object?> data) {
    if (_closed || isDisposed()) return;
    publish({'type': type, 'deviceId': ?device, 'data': data});
    if (type == 'device.keep_active.updated' && device != null) {
      for (final session
          in _sessions?.currentSessions(deviceId: device) ??
              <VideoSessionSnapshot>[]) {
        _publishSession(.updated, session);
      }
    }
  }

  void settingsChanged() {
    if (_wake case final wake?) {
      observeCleanup(
        wake.settingsChanged(
          _records.current.devices.map((record) => record.id),
        ),
      );
    }
  }

  Future<void> stopForConnection(
    String deviceId,
    DeviceConnection connection,
  ) async {
    await Future.wait([
      if (_sessions case final sessions?)
        sessions.stopForConnection(deviceId, connection),
      if (_audio case final audio?)
        audio.stopForConnection(deviceId, connection),
      if (_wake case final wake?) wake.stopForConnection(deviceId, connection),
    ], eagerError: true);
  }

  OrderedDisposal? _disposal;
  Future<void> close() {
    _closed = true;
    _disposal ??= OrderedDisposal([
      () async => await _sessions?.close(),
      () async => await _audio?.close(),
      () async => await _wake?.close(),
      () async => await Future.wait(_cleanup.toList()),
    ]);
    return _disposal!.run();
  }
}
