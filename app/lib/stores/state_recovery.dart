import 'dart:async';

import 'package:scrcpy_connect/models/application_request.dart';

typedef StateJson = Map<String, dynamic>;

/// 精确的 UP/CANCEL 仅清理已有输入租约，不重放动作。
/// 状态未知时仍允许停止和其他清理。
bool needsVerifiedState(String command, StateJson params) {
  if (command == 'session.key' || command == 'session.touch') {
    final exact =
        params['sessionId'] is String &&
        (params['sessionId'] as String).isNotEmpty;
    return !(exact &&
        (params['action'] == 'up' ||
            (command == 'session.touch' && params['action'] == 'cancel')));
  }
  return ApplicationCommand.tryParse(command)?.requiresVerifiedState ?? false;
}

/// 传输出现缺口后替换事件投影；快照携带核心发布水位，较旧排队事件不能覆盖它。
class StateRecovery {
  StateRecovery({
    required this.read,
    required this.emit,
    required this.isDisposed,
    this.timeout = const Duration(seconds: 12),
  });

  final Future<StateJson> Function(bool Function() current) read;
  final void Function(StateJson event) emit;
  final bool Function() isDisposed;
  final Duration timeout;
  Future<StateJson>? _running;
  int _epoch = 0, _watermark = -1, _observed = -1, _gaps = 0;
  int _localRevision = 0;
  bool _pending = false, _disposed = false;

  bool get pending => _pending;
  bool get hasSnapshot => _watermark >= 0;

  /// 本地业务变化没有原生序列；恢复期间发生变化时必须重读组合快照。
  void noteLocalStateChange() {
    if (!_disposed && !isDisposed()) _localRevision++;
  }

  /// 仅在普通事件可安全转发时返回 true。
  bool accept(StateJson event) {
    if (_disposed || isDisposed()) return false;
    final type = event['type'];
    if (type == 'runtime.heartbeat') return false;
    if (type == 'state.resync') {
      _gaps++;
      unawaited(
        refresh().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      return false;
    }
    final sequence = event['sequence'];
    if (sequence is! int || sequence < 0) {
      // 缺失栅栏表示协议缺口，不能据此应用旧数据。
      _gaps++;
      unawaited(
        refresh().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      return false;
    }
    if (type != 'session.frame' && sequence > _observed) _observed = sequence;
    return !_pending && sequence > _watermark;
  }

  Future<StateJson> refresh() {
    if (_disposed || isDisposed()) {
      return Future.error(const RequestFailure('cancelled', '状态恢复已结束。'));
    }
    if (_running case final existing?) return existing;
    _pending = true;
    final epoch = ++_epoch;
    final result = Completer<StateJson>();
    _running = result.future;
    // 先保存操作再发布事件，同步监听者可能立即重试。
    unawaited(_recover(epoch, result));
    return result.future;
  }

  Future<void> _recover(int epoch, Completer<StateJson> result) async {
    bool current() => !_disposed && !isDisposed() && _epoch == epoch;
    try {
      emit({'type': 'state.resync', 'data': <String, dynamic>{}});
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
        final sequence = validateStateSnapshot(snapshot);
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
          emit({'type': 'state.resynced', 'data': snapshot});
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
          emit({
            'type': 'state.resync.failed',
            'data': {'reason': '$error'},
          });
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

/// 授权任何所有权清理前先核验传输信封。
int validateStateSnapshot(StateJson snapshot) {
  final sequence = snapshot['sequence'];
  if (sequence is! int || sequence < 0 || snapshot['settings'] is! Map) {
    throw const RequestFailure('invalid_snapshot', '状态快照缺少版本或设置。');
  }
  for (final key in const [
    'devices',
    'sessions',
    'sources',
    'transfers',
    'activities',
    'shares',
    'companions',
  ]) {
    if (snapshot[key] is! List) {
      throw RequestFailure('invalid_snapshot', '状态快照缺少$key。');
    }
  }
  return sequence;
}
