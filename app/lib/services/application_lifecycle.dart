import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

/// 将引擎生命周期转换为连接可见性；Android 媒体可见性由宿主事实驱动。
final class ApplicationLifecycle {
  ApplicationLifecycle({
    required this.isDisposed,
    required this.setConnectionsVisible,
    required this.setMediaVisible,
    required this.shutdown,
  });

  final bool Function() isDisposed;
  final void Function(bool) setConnectionsVisible;
  final Future<void> Function(bool) setMediaVisible;
  final Future<void> Function() shutdown;
  AppLifecycleListener? _listener;

  Future<void> attach() async {
    _listener = AppLifecycleListener(
      onExitRequested: Platform.isAndroid || Platform.isIOS
          ? null
          : () async {
              await shutdown();
              return AppExitResponse.exit;
            },
      onStateChange: (state) => unawaited(_apply(state)),
    );
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null) await _apply(state);
  }

  Future<void> _apply(AppLifecycleState state) async {
    if (isDisposed()) return;
    final visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    setConnectionsVisible(visible);
    if (!Platform.isAndroid) await setMediaVisible(visible);
  }

  void dispose() => _listener?.dispose();
}
