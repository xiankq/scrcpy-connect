import 'dart:async';

import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/models/video_session_view.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';
import 'package:scrcpy_connect/pages/control/models/remote_session_event.dart';
import 'package:scrcpy_connect/pages/control/remote_connection_recovery.dart';
import 'package:scrcpy_connect/pages/control/remote_window.dart';
import 'package:scrcpy_connect/widgets/remote_failure.dart';

export 'models/remote_session_event.dart';

/// 单个控制页面的启动、连接恢复和状态核验。
/// 窗口保留精确会话与租约；页面保留渲染、焦点和可见性操作。
class RemoteSessionLifecycle {
  RemoteSessionLifecycle({
    required this.window,
    required this.packageName,
    required this.existingSession,
    required this.foreground,
    required this.routeCurrent,
    required this.reconciliationPending,
    required this.reconcile,
    required this.releaseInputs,
    required this.onChanged,
    required this.onFocusLost,
  });

  final RemoteWindow window;
  final String? packageName;
  final VideoSessionView? existingSession;
  final bool Function() foreground, routeCurrent, reconciliationPending;
  final Future<void> Function() reconcile, releaseInputs;
  final void Function() onChanged, onFocusLost;
  final _connection = RemoteConnectionRecovery();
  bool _retired = false;
  int _reconciliationGeneration = 0;

  bool get _current => !_retired && window.isCurrent;
  bool get recoveryPending => _connection.pending;
  bool get _canRecover =>
      _current &&
      window.presentation.canRecoverConnection(
        foreground: foreground(),
        phoneScreen: packageName == null,
        reconciliationPending: reconciliationPending(),
        routeCurrent: routeCurrent(),
      );

  Future<RemoteWindowOpened?> start({
    bool recoveringConnection = false,
    required Future<VideoSessionPlan?> Function(bool Function() current)
    prepare,
  }) async {
    if (!_current) return null;
    final presentation = window.presentation;
    if (presentation.appLaunchUnknown) {
      await checkAppLaunch();
      return null;
    }
    if ((!recoveringConnection && presentation.reconcileOnly) ||
        reconciliationPending()) {
      await reconcileState();
      return null;
    }
    final opening = window.open(
      packageName: packageName,
      existing: existingSession,
      recoveringConnection: recoveringConnection,
      releaseInputs: releaseInputs,
      canProceed: () => _allowStart(recoveringConnection),
      prepare: prepare,
    );
    onChanged();
    final opened = await opening;
    if (!_current) return null;
    onChanged();
    return opened != null && presentation.acceptsStart(opened.ticket)
        ? opened
        : null;
  }

  bool _allowStart(bool recovering) {
    if (!recovering || _canRecover) return true;
    _connection.defer();
    window.presentation.deferStart();
    onChanged();
    return false;
  }

  void viewed() {
    if (_current &&
        packageName == null &&
        !window.presentation.appLaunchUnknown) {
      _connection.viewed();
    }
  }

  /// 同步消耗恢复意图并撤销旧绑定，调用者随后只启动一次恢复。
  bool takeConnectionRecovery() {
    if (!_canRecover || window.presentation.connecting || !_connection.take()) {
      return false;
    }
    window.presentation.suppressInitialAction();
    window.abandonEndedSession();
    return true;
  }

  RemoteSessionEvent acceptEvent(RuntimeEvent event) {
    if (!_current) return .handled;
    final presentation = window.presentation;
    final stopped = _connection.acceptEvent(
      event,
      deviceId: window.deviceId,
      sessionId: presentation.sessionId,
      phoneScreen: packageName == null,
    );
    if (stopped) {
      // 明确停止作废准备中的恢复，迟到连接与启动回执均不能撤销。
      if (window.recoveringConnection) {
        window.cancelRecovery();
        onChanged();
      }
      return .handled;
    }
    switch (event.data) {
      case DeviceListChanged(:final devices):
        final device = devices
            .where((d) => d.id == window.deviceId)
            .firstOrNull;
        return device?.status == .connected ? .connected : .disconnected;
      case RecoveryStarted():
        markStateUnknown();
        return .handled;
      case RecoveryFailed(:final reason):
        markStateUnknown(reason: reason);
        return .handled;
      case RecoveryCompleted(:final snapshot):
        final changed = presentation.reconcile(
          snapshot,
          packageName: packageName,
          deviceId: window.deviceId,
        );
        if (!changed) return .handled;
        _reconciliationGeneration++;
        onChanged();
        return .reconciled;
      default:
        return .unhandled;
    }
  }

  int markStateUnknown({String? reason, VideoSessionView? initialSession}) {
    _reconciliationGeneration++;
    onFocusLost();
    final presentation = window.presentation;
    final epoch = presentation.beginReconciliation(
      initialSession: initialSession,
      reason: reason,
    );
    unawaited(releaseInputs());
    presentation.replaceBinding();
    onChanged();
    return epoch;
  }

  Future<void> reconcileState() async {
    if (!_current) return;
    final epoch = markStateUnknown();
    final generation = _reconciliationGeneration;
    try {
      // 命令回执不能解除门禁，只有完整核验事件可以恢复原会话。
      if (!_current) return;
      await reconcile();
    } catch (failure) {
      if (_current &&
          generation == _reconciliationGeneration &&
          window.presentation.acceptsReconciliation(epoch)) {
        window.presentation.reportError(remoteFailure(failure));
        onChanged();
      }
    }
  }

  Future<void> checkAppLaunch() async {
    if (!_current) return;
    final checking = window.checkAppLaunch(packageName);
    onChanged();
    await checking;
    if (_current) onChanged();
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _connection.stop();
    markStateUnknown(reason: '画面来源已变化，请关闭本页后重新打开。');
  }

  void dispose() {
    _retired = true;
    _connection.stop();
  }
}
