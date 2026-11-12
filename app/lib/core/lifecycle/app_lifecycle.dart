import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/core/companion/companion_service.dart';
import 'package:scrcpy_connect/core/content/content_preview.dart';
import 'package:scrcpy_connect/core/content/thumbnail_job_service.dart';
import 'package:scrcpy_connect/core/control/control_session_service.dart';
import 'package:scrcpy_connect/core/control/device_wake_service.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_connection_service.dart';
import 'package:scrcpy_connect/core/devices/device_health_service.dart';
import 'package:scrcpy_connect/core/devices/device_observation_service.dart';
import 'package:scrcpy_connect/core/devices/device_power_service.dart';
import 'package:scrcpy_connect/core/devices/device_reconnect_service.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/device_service.dart';
import 'package:scrcpy_connect/core/devices/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/files/adb_file_executor.dart';
import 'package:scrcpy_connect/core/files/file_catalog.dart';
import 'package:scrcpy_connect/core/files/file_mutation_service.dart';
import 'package:scrcpy_connect/core/files/file_share_service.dart';
import 'package:scrcpy_connect/core/files/file_transfer_service.dart';
import 'package:scrcpy_connect/core/media/device_audio_service.dart';
import 'package:scrcpy_connect/core/media/media_playback.dart';
import 'package:scrcpy_connect/core/platform/app_platform.dart';
import 'package:scrcpy_connect/core/platform/background_policy.dart';
import 'package:scrcpy_connect/core/platform/native_host.dart';
import 'package:scrcpy_connect/core/recovery/state_recovery.dart';
import 'package:scrcpy_connect/core/settings/app_settings.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preference_codec.dart';
import 'package:scrcpy_connect/utils/ordered_disposal.dart';

/// 协调应用启停、连接退休与有序关闭；依赖由 bootstrap 装配。
final class AppLifecycle {
  AppLifecycle({
    required this._host,
    required this._records,
    required this._events,
    required this._stateRecovery,
    required this._preferences,
    required this._transfers,
    required this._fileCatalog,
    required this._fileMutations,
    required this._fileExecutor,
    required this._sharing,
    required this._platform,
    required this._background,
    required this._reconnections,
    required this._setup,
    required this._media,
    required this._devices,
    required this._observations,
    required this._health,
    required this._power,
    required this._sessions,
    required this._audio,
    required this._keepAwake,
    required this._serverQueries,
    required this._mediaJobs,
    required this._companion,
    required this._artifacts,
    required this._diagnostics,
  });

  final NativeHost _host;
  final DeviceRecordStorage _records;
  final RuntimeEvents _events;
  final StateRecovery _stateRecovery;
  final AppSettings _preferences;
  final FileTransferService _transfers;
  final FileCatalog _fileCatalog;
  final FileMutationService _fileMutations;
  final AdbFileExecutor _fileExecutor;
  final FileShareService? _sharing;
  final AppPlatform _platform;
  final BackgroundPolicy _background;
  final DeviceReconnectService _reconnections;
  final DeviceConnectionService _setup;
  final MediaPlayback _media;
  final DeviceService _devices;
  final DeviceObservationService _observations;
  final DeviceHealthService _health;
  final DevicePowerService _power;
  final ControlSessionService _sessions;
  final DeviceAudioService _audio;
  final DeviceWakeService _keepAwake;
  final ScrcpyServerQueries _serverQueries;
  final ThumbnailJobService _mediaJobs;
  final CompanionService _companion;
  final ContentPreview _artifacts;
  final DiagnosticReporter _diagnostics;

  Future<void> setVisible(bool visible) async {
    if (_disposed) return;
    _reconnections.setVisible(visible);
    if (!Platform.isAndroid) await _media.setVisible(visible);
  }

  bool _disposed = false;
  bool get isDisposed => _disposed;
  final _businessTasks = <Future<void>>{};
  final _observedConnections = <String, DeviceConnection>{};
  // 当前连接投影可先消失；设备级任务的退休责任保留到精确旧连接排空。
  final _deviceTaskConnections = <DeviceConnection>{};

  void observeCleanup(Future<void> work) {
    _businessTasks.add(work);
    unawaited(
      work.then<void>(
        (_) {
          _businessTasks.remove(work);
        },
        onError: (Object error, StackTrace stack) {
          _businessTasks.remove(work);
          _events.emit({
            'type': 'activity.cleanup.failed',
            'data': {'reason': '$error'},
          });
        },
      ),
    );
  }

  void publishBusiness(String type, String? device, Map<String, Object?> data) {
    _events.publish({
      'type': type,
      'deviceId': ?device,
      'data':
          type.startsWith('session.') &&
              type != 'session.frame' &&
              data['sessionId'] is String
          ? _keepAwake.projectSession(data)
          : data,
    });
    if (type == 'device.keep_active.updated' && device != null) {
      _publishKeepAwake(device);
    }
  }

  void _publishKeepAwake(String device) {
    for (final session in _sessions.currentSessions(deviceId: device)) {
      publishBusiness('session.updated', device, session.toSnapshot());
    }
  }

  void handleBusinessEvent(Map<String, dynamic> event) {
    _setup.handleEvent(event);
    _reconnections.handleEvent(event);
    if (event['type'] == 'devices.changed') {
      final ids = {
        ..._observedConnections.keys,
        ..._records.current.devices.map((record) => record.id),
      };
      for (final id in ids) {
        final connection = _devices.current(id);
        if (identical(_observedConnections[id], connection)) continue;
        if (connection == null) {
          _observedConnections.remove(id);
        } else {
          _observedConnections[id] = connection;
          _deviceTaskConnections.add(connection);
        }
        observeCleanup(_observations.connectionChanged(id));
      }
    }
  }

  Future<void> stopConnectionActivities(
    String id,
    DeviceConnection connection,
  ) async {
    // 各调用先同步撤销自己创建的资源；所有步骤均运行并保留精确失败供下一轮重试。
    final stops = [
      _health.stopConnection(id, connection),
      _power.stopConnection(id, connection),
      _sessions.stopForConnection(id, connection),
      _audio.stopForConnection(id, connection),
      _keepAwake.stopForConnection(id, connection),
      _serverQueries.stopForConnection(connection),
      // 未获接纳的候选也会回收到这里，不能取消原连接仍持有的设备级任务。
      // 观察投影变化不撤销退休责任；清理失败后仍由同一旧连接重试。
      if (_deviceTaskConnections.contains(connection)) ...[
        _transfers.cancelDevice(id),
        _fileCatalog.cancelDevice(id),
        _fileMutations.cancelDevice(id),
        _artifacts.cancelDevice(id),
      ],
      _mediaJobs.stopForConnection(id, connection),
      // 同步撤销普通执行并关闭原 worker，避免目录或传输取消仍在等待阻塞读取。
      _fileExecutor.stopForConnection(connection),
    ];
    // 首个失败立即保留退休责任；其他任务仍归各自所有者，不能断开承载连接。
    await Future.wait(stops, eagerError: true);
    final displays = _host.physicalDisplays;
    if ((await connection.client.services.connectionFacts(connection.device))
        .closed) {
      await displays.detachClosedConnection(connection);
    } else {
      try {
        await displays.stopForConnection(connection);
      } catch (_) {
        if (!(await connection.client.services.connectionFacts(
          connection.device,
        )).closed) {
          rethrow;
        }
        await displays.detachClosedConnection(connection);
      }
    }
    // 远端子任务确认退出后才能关闭承载它们的有序 RPC 部署。
    await _observations.stopForConnection(id, connection);
    await _companion.stopForConnection(id, connection);
    _deviceTaskConnections.remove(connection);
  }

  void settingsChanged(Preferences preferences) {
    if (_disposed) return;
    final settings = PreferenceCodec.encode(preferences);
    _reconnections.updateBackgroundKeepAlive(preferences.backgroundKeepAlive);
    _events.publish({'type': 'settings.changed', 'data': settings});
    observeCleanup(
      _keepAwake.settingsChanged(
        _records.current.devices.map((record) => record.id),
      ),
    );
  }

  Future<void> cancelDeviceFiles(String deviceId) async {
    await Future.wait([
      _fileCatalog.cancelDevice(deviceId),
      _fileMutations.cancelDevice(deviceId),
      _transfers.cancelDevice(deviceId),
    ]);
  }

  void requireVerifiedState() {
    if (_stateRecovery.pending) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
  }

  Future<void> _closeFiles() async {
    // 文件协调器先撤销任务；执行器独立排空原 worker，关闭失败不能困住任务等待。
    await Future.wait([
      _transfers.close(),
      _fileCatalog.close(),
      _fileMutations.close(),
      _fileExecutor.close(),
    ], eagerError: true);
  }

  Future<void> _closeHost() async {
    // OrderedDisposal 继续清理独立资源；承载执行层必须等全部依赖实际关闭后才退出。
    await _artifacts.close();
    await _closeFiles();
    await _sharing?.close();
    await _media.dispose();
    await _health.close();
    await _power.close();
    await _devices.close();
    await _mediaJobs.close();
    await _sessions.close();
    await _audio.close();
    await _keepAwake.close();
    await _serverQueries.close();
    await _observations.close();
    await _companion.close();
    await Future.wait(_businessTasks.toList());
    await _host.close();
  }

  Future<void> activate() async {
    await _transfers.reconcileShares();
    await _events.attach(
      files: [_transfers.events, _fileCatalog.events],
      sharing: _sharing?.events,
      platform: Platform.isAndroid ? _platform.events : null,
    );
    if (Platform.isAndroid) {
      final state = await _platform.request('audio.platform.state', const {});
      await _media.setVisible(state['visible'] == true);
      _reconnections.setVisible(state['visible'] == true);
      await _platform.attachShare();
    }
    // isolate 重启会丢失播放器及一次性媒体流；回收孤立捕获，不能接管未经核验的播放。
    await _media.retireUnownedAudio();
    final settings = await _preferences.read();
    final backgroundStatus = await _background.apply(
      settings.backgroundKeepAlive,
      automatic: true,
    );
    // 恢复快照安排连接前先应用宿主的显式或系统停止状态，之后仍允许手动连接。
    if (backgroundStatus?.stopped == true) {
      _reconnections.stopAutomaticConnections();
    }
    // 由已挂载的应用视图报告可见性，首次报告前不安排自动重连。
    _reconnections.setVisible(false);
    // 可信快照先建立屏幕偏好和旧连接身份，再允许第一次自动重连。
    await _stateRecovery.refresh();
    await _reconnections.start();
  }

  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> reconcileState() async {
    if (_disposed) {
      throw const RequestFailure('disposed', '连接界面已关闭。');
    }
    final watch = Stopwatch()..start();
    try {
      await _stateRecovery.refresh();
    } catch (error) {
      _diagnostics.command(
        'state.reconcile',
        const {},
        watch.elapsedMilliseconds,
        error: error,
      );
      rethrow;
    }
  }

  OrderedDisposal? _disposal;

  /// 结束当前应用所有者；关闭失败保留原对象，下一次调用继续排空。
  Future<void> dispose() {
    _disposal ??= _prepareDisposal();
    return _disposal!.run();
  }

  OrderedDisposal _prepareDisposal() {
    _disposed = true;
    _sharing?.stopIntake();
    _media.stopAdmission();
    _stateRecovery.dispose();
    return OrderedDisposal([
      () async =>
          await Future.wait([_reconnections.dispose(), _setup.dispose()]),
      _platform.dispose,
      _artifacts.close,
      _closeFiles,
      if (_sharing != null) _sharing.close,
      _events.detach,
      _media.dispose,
      _health.close,
      _power.close,
      _devices.close,
      _mediaJobs.close,
      _sessions.close,
      _audio.close,
      _keepAwake.close,
      _serverQueries.close,
      _observations.close,
      _companion.close,
      // 依赖资源若尚未关闭，不能释放承载它们的 SDK scope 或服务器。
      _closeHost,
      _events.close,
    ]);
  }
}
