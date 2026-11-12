import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/core/control/capture_resources.dart';
import 'package:scrcpy_connect/core/devices/device_resources.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/files/file_resources.dart';
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
    required this._connections,
    required this._captures,
    required this._files,
    required this._events,
    required this._stateRecovery,
    required this._preferences,
    required this._platform,
    required this._background,
    required this._media,
    required this._diagnostics,
  });

  final NativeHost _host;
  final DeviceResources _connections;
  final CaptureResources _captures;
  final FileResources _files;
  final RuntimeEvents _events;
  final StateRecovery _stateRecovery;
  final AppSettings _preferences;
  final AppPlatform _platform;
  final BackgroundPolicy _background;
  final MediaPlayback _media;
  final DiagnosticReporter _diagnostics;

  Future<void> setVisible(bool visible) async {
    if (_disposed) return;
    _connections.reconnections.setVisible(visible);
    if (!Platform.isAndroid) await _media.setVisible(visible);
  }

  bool _disposed = false;
  bool get isDisposed => _disposed;
  void settingsChanged(Preferences preferences) {
    if (_disposed) return;
    final settings = PreferenceCodec.encode(preferences);
    _connections.reconnections.updateBackgroundKeepAlive(
      preferences.backgroundKeepAlive,
    );
    _events.publish({'type': 'settings.changed', 'data': settings});
    _captures.settingsChanged();
  }

  Future<void> cancelDeviceFiles(String deviceId) =>
      _files.cancelFiles(deviceId);

  void requireVerifiedState() {
    if (_stateRecovery.pending) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
  }

  Future<void> _closeHost() async {
    // OrderedDisposal 继续清理独立资源；承载执行层必须等全部依赖实际关闭后才退出。
    await _files.close();
    await _media.dispose();
    await _connections.closeConnections();
    await _captures.close();
    await _connections.closeServices();
    await _host.close();
  }

  Future<void> activate() async {
    await _files.transfers.reconcileShares();
    await _events.attach(
      files: [_files.transfers.events],
      sharing: _files.sharing?.events,
      platform: Platform.isAndroid ? _platform.events : null,
    );
    if (Platform.isAndroid) {
      final state = await _platform.request('audio.platform.state', const {});
      await _media.setVisible(state['visible'] == true);
      _connections.reconnections.setVisible(state['visible'] == true);
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
      _connections.reconnections.stopAutomaticConnections();
    }
    // 由已挂载的应用视图报告可见性，首次报告前不安排自动重连。
    _connections.reconnections.setVisible(false);
    // 可信快照先建立屏幕偏好和旧连接身份，再允许第一次自动重连。
    await _stateRecovery.refresh();
    await _connections.reconnections.start();
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
    _files.stopAdmission();
    _media.stopAdmission();
    _stateRecovery.dispose();
    return OrderedDisposal([
      _connections.stopAdmission,
      _platform.dispose,
      _files.close,
      _events.detach,
      _media.dispose,
      _connections.closeConnections,
      _captures.close,
      _connections.closeServices,
      // 依赖资源若尚未关闭，不能释放承载它们的 SDK scope 或服务器。
      _closeHost,
      _events.close,
    ]);
  }
}
