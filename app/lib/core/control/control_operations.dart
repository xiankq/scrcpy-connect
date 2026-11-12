import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/recovery/state_recovery.dart';

/// 控制输入的应用准入；恢复期间仍允许精确会话的 UP/CANCEL 释放已有输入。
final class ControlOperations implements RemoteControl {
  ControlOperations({
    required this._sessions,
    required this.isDisposed,
    required this.isStateUnverified,
    required this._diagnostics,
  });

  final RemoteControl _sessions;
  final bool Function() isDisposed;
  final bool Function() isStateUnverified;
  final DiagnosticReporter _diagnostics;

  @override
  Future<ControlReceipt> sendControl(
    ControlTarget target,
    ControlAction action,
  ) async {
    if (isDisposed()) throw const RequestFailure('disposed', '连接界面已关闭。');
    // 保留结构拒绝先于状态屏障的顺序；范围与原生执行仍由捕获所有者核验。
    for (final value in [?target.sessionId, ?target.deviceId]) {
      if (value.isEmpty || value.contains('\u0000')) {
        throw const RequestFailure('invalid_argument', '控制目标无效。');
      }
    }
    if (action.isInput && target.captureGeneration == null) {
      throw const RequestFailure('invalid_argument', '缺少捕获代际。');
    }
    if (isStateUnverified() && needsVerifiedControl(target, action)) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    try {
      return await _sessions.sendControl(target, action);
    } catch (error) {
      _diagnostics.controlFailed(
        target,
        action,
        error,
        watch.elapsedMilliseconds,
      );
      rethrow;
    }
  }
}
