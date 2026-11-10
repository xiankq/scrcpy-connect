import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/services/clipboard_sync.dart';

void useClipboardVisibility(ClipboardSync sync) {
  useEffect(() {
    final observer = _ClipboardVisibility(sync);
    WidgetsBinding.instance.addObserver(observer);
    scheduleMicrotask(observer.initialize);
    return observer.dispose;
  }, [sync]);
}

final class _ClipboardVisibility with WidgetsBindingObserver {
  _ClipboardVisibility(this.sync);
  final ClipboardSync sync;
  bool _disposed = false;

  void initialize() {
    if (!_disposed) {
      sync.setVisibility(
        foreground:
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      sync.setVisibility(foreground: state == AppLifecycleState.resumed);

  @override
  void didChangeViewFocus(ViewFocusEvent event) =>
      sync.setVisibility(focused: event.state == ViewFocusState.focused);

  void dispose() {
    _disposed = true;
    sync.setVisibility(foreground: false);
    WidgetsBinding.instance.removeObserver(this);
  }
}
