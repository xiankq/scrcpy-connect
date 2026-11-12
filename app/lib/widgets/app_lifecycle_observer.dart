import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';

/// 应用视图拥有引擎可见性与退出请求；数据层只接收可见状态和关闭操作。
final class AppLifecycleObserver {
  AppLifecycleObserver({
    required this.setVisible,
    required this.shutdown,
    this.diagnostics,
  });
  final DiagnosticLog? diagnostics;
  final Future<void> Function(bool)? setVisible;
  final Future<void> Function()? shutdown;
  AppLifecycleListener? _listener;
  bool _disposed = false;

  Future<void> attach() async {
    _listener = AppLifecycleListener(
      onExitRequested: Platform.isAndroid || Platform.isIOS
          ? null
          : () async {
              await shutdown?.call();
              return AppExitResponse.exit;
            },
      onStateChange: (state) => unawaited(_apply(state)),
    );
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null) await _apply(state);
  }

  Future<void> _apply(AppLifecycleState state) async {
    if (_disposed) return;
    diagnostics?.record(
      DiagnosticArea.app,
      'app.lifecycle',
      fields: {'status': state.name},
    );
    if (state != AppLifecycleState.resumed) unawaited(diagnostics?.flush());
    final visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    await setVisible?.call(visible);
  }

  void dispose() {
    _disposed = true;
    _listener?.dispose();
    unawaited(setVisible?.call(false));
  }
}
