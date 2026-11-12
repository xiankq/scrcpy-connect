import 'dart:async';
import 'dart:collection';

import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/remote_presentation.dart';

typedef RemoteInputDispatch = Future<void> Function(
  ControlAction action,
  ControlTarget target,
  RemoteBinding binding,
);
typedef RemoteInputAdmission = bool Function(
  ControlAction action,
  ControlTarget target,
  RemoteBinding binding,
);

/// 串行发送输入，每个触点只保留最新待发移动；按下、抬起等边缘事件保持顺序且不合并。
final class RemoteInputQueue {
  RemoteInputQueue({
    required this.dispatch,
    required this.admits,
    this.capacity = 256,
  });

  final RemoteInputDispatch dispatch;
  final RemoteInputAdmission admits;
  final int capacity;
  final _pending = LinkedList<_PendingInput>();
  final _moves = <(RemoteBinding, int), _PendingInput>{};
  Completer<void>? _idle;
  bool _pumping = false;
  bool _closed = false;

  /// 调用时已准入的全部输入完成分发或被当前绑定拒绝后，此 Future 才结束。
  Future<void> get idle {
    if (!_pumping && _pending.isEmpty) return Future<void>.value();
    return (_idle ??= Completer<void>()).future;
  }

  Future<void> enqueue(
    ControlAction action,
    ControlTarget target,
    RemoteBinding binding,
  ) {
    if (_closed) return Future<void>.value();
    final pointerKey = action is ControlTouch
        ? (binding, action.pointerId)
        : null;
    final moveKey =
        action is ControlTouch &&
            (action.action == .move || action.action == .hover)
        ? pointerKey
        : null;
    if (moveKey != null) {
      final pending = _moves[moveKey];
      if (pending != null && pending.pending) {
        pending.unlink();
        pending.action = action;
        pending.target = target;
        _pending.add(pending);
        // 被覆盖的移动共享同一完成信号，慢写入不能为每个物理事件保留独立等待者。
        return pending.waiter.future;
      }
    } else if (pointerKey != null) {
      // 后续按下、抬起或取消必须排在该触点已有移动之后，不能跨此边缘合并移动。
      _moves.remove(pointerKey);
    }

    // 有界队列预留一半容量给释放事件，文字和按下拥塞不能阻止页面撤销准入后释放已持有输入。
    final limit = action.isRelease || capacity < 16 ? capacity : capacity ~/ 2;
    if (_pending.length >= limit) {
      return Future<void>.error(StateError('控制输入队列繁忙，请等待网络恢复。'));
    }
    final waiter = Completer<void>();
    final entry = _PendingInput(action, target, binding, moveKey, waiter);
    _pending.add(entry);
    if (moveKey != null) _moves[moveKey] = entry;
    _pump();
    return waiter.future;
  }

  /// 停止接收新命令；本机结算待发输入且不重放，允许已分发请求结束。
  void close() {
    if (_closed) return;
    _closed = true;
    for (final entry in List<_PendingInput>.of(_pending)) {
      entry.pending = false;
      entry.complete();
    }
    _pending.clear();
    _moves.clear();
    _completeIdleIfNeeded();
  }

  void _pump() {
    if (_pumping || _pending.isEmpty || _closed) return;
    _pumping = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty && !_closed) {
        final entry = _pending.first;
        entry.unlink();
        entry.pending = false;
        final moveKey = entry.moveKey;
        if (moveKey != null && identical(_moves[moveKey], entry)) {
          _moves.remove(moveKey);
        }

        var accepted = false;
        try {
          accepted = admits(entry.action, entry.target, entry.binding);
        } catch (error, stack) {
          entry.complete(error, stack);
          continue;
        }
        if (accepted) {
          try {
            await dispatch(entry.action, entry.target, entry.binding);
          } catch (error, stack) {
            entry.complete(error, stack);
            continue;
          }
        }
        entry.complete();
      }
    } finally {
      _pumping = false;
      if (_pending.isNotEmpty && !_closed) {
        _pump();
      } else {
        _completeIdleIfNeeded();
      }
    }
  }

  void _completeIdleIfNeeded() {
    if (_pumping || _pending.isNotEmpty) return;
    final idle = _idle;
    _idle = null;
    if (idle != null && !idle.isCompleted) idle.complete();
  }
}

final class _PendingInput extends LinkedListEntry<_PendingInput> {
  _PendingInput(
    this.action,
    this.target,
    this.binding,
    this.moveKey,
    this.waiter,
  );

  ControlAction action;
  ControlTarget target;
  final RemoteBinding binding;
  final (RemoteBinding, int)? moveKey;
  final Completer<void> waiter;
  bool pending = true;

  void complete([Object? error, StackTrace? stack]) {
    if (waiter.isCompleted) return;
    if (error == null) {
      waiter.complete();
    } else {
      waiter.completeError(error, stack);
    }
  }
}
