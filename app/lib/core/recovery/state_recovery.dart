import 'dart:async';

import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';

/// 精确的 UP/CANCEL 仅清理已有输入租约；状态未知时仍允许释放。
bool needsVerifiedControl(ControlTarget target, ControlAction action) =>
    !(action.isRelease && target.sessionId?.isNotEmpty == true);

/// 传输出现缺口后替换事件投影；快照携带核心发布水位，较旧排队事件不能覆盖它。
class StateRecovery {
  StateRecovery({
    required this.read,
    required this.emit,
    required this.isDisposed,
    this.timeout = const Duration(seconds: 12),
  });

  final Future<RuntimeSnapshot> Function(bool Function() current) read;
  final void Function(RecoveryEvent event) emit;
  final bool Function() isDisposed;
  final Duration timeout;
  Future<RuntimeSnapshot>? _running;
  int _epoch = 0, _watermark = -1, _observed = -1, _gaps = 0;
  int _localRevision = 0;
  bool _pending = false, _disposed = false;

  bool get pending => _pending;
  bool get hasSnapshot => _watermark >= 0;

  /// 本地业务变化没有原生序列；恢复期间发生变化时必须重读组合快照。
  void noteLocalStateChange() {
    if (!_disposed && !isDisposed()) _localRevision++;
  }

  /// 事件缺口作废在途读取；重复报告共用同一恢复任务。
  void reportGap() {
    if (_disposed || isDisposed()) return;
    _gaps++;
    unawaited(
      refresh().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  /// 只接受越过已核验水位的事件；呈现帧不推进业务水位。
  bool accept({required int? sequence, bool telemetry = false}) {
    if (_disposed || isDisposed()) return false;
    if (sequence == null || sequence < 0) {
      reportGap();
      return false;
    }
    if (!telemetry && sequence > _observed) _observed = sequence;
    return !_pending && sequence > _watermark;
  }

  Future<RuntimeSnapshot> refresh() {
    if (_disposed || isDisposed()) {
      return Future.error(const RequestFailure('cancelled', '状态恢复已结束。'));
    }
    if (_running case final existing?) return existing;
    _pending = true;
    final epoch = ++_epoch;
    final result = Completer<RuntimeSnapshot>();
    _running = result.future;
    // 先保存操作再发布事件，同步监听者可能立即重试。
    unawaited(_recover(epoch, result));
    return result.future;
  }

  Future<void> _recover(int epoch, Completer<RuntimeSnapshot> result) async {
    bool current() => !_disposed && !isDisposed() && _epoch == epoch;
    try {
      emit(const RecoveryStarted());
      if (!current()) {
        throw const RequestFailure('cancelled', '状态恢复已结束。');
      }
      for (var attempt = 0; attempt < 4; attempt++) {
        final gaps = _gaps;
        final localRevision = _localRevision;
        final snapshot = await read(current).timeout(timeout);
        if (!current()) {
          throw const RequestFailure('cancelled', '状态恢复已结束。');
        }
        final sequence = snapshot.sequence;
        if (sequence < _watermark) {
          throw const RequestFailure('invalid_snapshot', '状态快照版本已过期。');
        }
        if (gaps != _gaps ||
            localRevision != _localRevision ||
            sequence < _observed) {
          continue;
        }
        final previousWatermark = _watermark;
        _watermark = sequence;
        _pending = false;
        // 监听者此时可恢复仍持有的可见呈现；核验过程中不能准入恢复。
        try {
          emit(RecoveryCompleted(snapshot));
        } catch (_) {
          // 回执未完成交付不能视为核验成功，亦不能推进快照水位。
          _watermark = previousWatermark;
          rethrow;
        }
        if (identical(_running, result.future)) _running = null;
        result.complete(snapshot);
        return;
      }
      throw const RequestFailure('state_busy', '状态持续变化，尚未完成核验，请重试。');
    } catch (error, stack) {
      if (current()) {
        // 使超时读取失效，防止它释放迟到的所有者。
        _epoch++;
        _pending = true;
        _running = null;
        try {
          emit(RecoveryFailed('$error'));
        } catch (_) {
          // 失败通知再次抛错时仍须以原始失败结算，不能留下悬空操作。
        }
      }
      if (identical(_running, result.future)) _running = null;
      result.completeError(error, stack);
    }
  }

  void dispose() {
    _disposed = true;
    _epoch++;
  }
}
