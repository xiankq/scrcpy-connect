import 'dart:async';

import 'package:scrcpy/scrcpy.dart';
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
  final void Function(Object) onCleanupFailure;
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
      sessions: sessions,
      audio: audio,
      keepAwake: keepAwake,
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
      onAudioEligibilityChanged: (id) {
        // 同步撤准入后记录实际排空，回调不等待其他设备，也不丢弃失败所有者。
        if (_audio case final audio?) {
          observeCleanup(audio.eligibilityChanged(id));
        }
        final wake = _wake ?? (!_closed && !isDisposed() ? keepAwake : null);
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
      hasAudioOwner: sessions.hasAudioOwner,
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
      hasWindowOwner: sessions.hasAudioOwner,
      keepAwakeEnabled: (deviceId) =>
          _preferences.settings.deviceSettings[deviceId]?.stayAwake == true,
      emit: (type, device, data) => publishBusiness(type, device, data),
    );
  }

  List<VideoSessionSnapshot> currentSessions() =>
      _sessions?.currentSessions() ?? [];
  Future<List<VideoSessionSnapshot>> readSessions() async =>
      await _sessions?.readSessions() ?? [];
  Future<List<RecoveredVideoSession>> readRecoverySessions() async => [
    for (final session in await readSessions())
      RecoveredVideoSession(
        session: session,
        keepAwake:
            _wake?.readWake(session.deviceId) ??
            KeepAwakeSnapshot.withoutLease(
              deviceId: session.deviceId,
              enabled:
                  _preferences
                      .settings
                      .deviceSettings[session.deviceId]
                      ?.stayAwake ==
                  true,
              hasWindowOwner:
                  _sessions?.hasAudioOwner(session.deviceId) ?? false,
            ),
      ),
  ];
  Future<List<SessionActivity>> readActivitySessions({
    String? deviceId,
  }) async => await _sessions?.readActivitySessions(deviceId: deviceId) ?? [];
  List<DeviceAudioSnapshot> audioSnapshots({bool activeOnly = false}) =>
      _audio?.snapshots(activeOnly: activeOnly) ?? [];
  Map<String, Object?> projectSession(Map<String, Object?> state) =>
      keepAwake.projectSession(state);

  void observeCleanup(Future<void> work) {
    _cleanup.add(work);
    unawaited(
      work.then<void>(
        (_) => _cleanup.remove(work),
        onError: (Object error, StackTrace stack) {
          _cleanup.remove(work);
          onCleanupFailure(error);
        },
      ),
    );
  }

  void publishBusiness(String type, String? device, Map<String, Object?> data) {
    if (_closed || isDisposed()) return;
    publish({
      'type': type,
      'deviceId': ?device,
      'data':
          type.startsWith('session.') &&
              type != 'session.frame' &&
              data['sessionId'] is String
          ? projectSession(data)
          : data,
    });
    if (type == 'device.keep_active.updated' && device != null) {
      for (final session
          in _sessions?.currentSessions(deviceId: device) ??
              <VideoSessionSnapshot>[]) {
        publishBusiness('session.updated', device, session.toSnapshot());
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
