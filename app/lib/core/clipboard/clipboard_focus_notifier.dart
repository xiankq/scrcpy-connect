import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';

import 'models/clipboard_focus.dart';

part 'clipboard_focus_notifier.g.dart';

/// 页面持有焦点租约；旧页面释放不能清除新页面或新作用域的焦点。
@Riverpod(keepAlive: true)
class ClipboardFocusNotifier extends _$ClipboardFocusNotifier {
  late Object _epoch;
  Object? _focusedLease;

  @override
  ClipboardFocus? build() {
    ref.watch(runtimeEventsProvider);
    _epoch = Object();
    _focusedLease = null;
    return null;
  }

  ClipboardFocusLease claim(String deviceId) {
    final epoch = _epoch;
    final events = ref.read(runtimeEventsProvider);
    final token = Object();
    return ClipboardFocusLease._((sessionId, focused) {
      if (!ref.mounted ||
          !identical(ref.read(runtimeEventsProvider), events) ||
          !identical(_epoch, epoch)) {
        return;
      }
      if (!focused) {
        if (!identical(_focusedLease, token)) return;
        _focusedLease = null;
        state = null;
        return;
      }
      _focusedLease = token;
      if (state?.deviceId == deviceId && state?.sessionId == sessionId) return;
      state = ClipboardFocus(deviceId: deviceId, sessionId: sessionId!);
    });
  }
}

class ClipboardFocusLease {
  ClipboardFocusLease._(this._update);
  final void Function(String?, bool) _update;
  bool _disposed = false;

  void focus(String sessionId, bool focused) {
    if (!_disposed) _update(sessionId, focused);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _update(null, false);
  }
}
