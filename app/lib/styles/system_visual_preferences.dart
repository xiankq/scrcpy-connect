import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Apple 系统辅助视觉偏好；与应用设置及后台权限分开拥有订阅。
final class SystemVisualPreferences extends ChangeNotifier {
  static const _channel = MethodChannel('dev.scrcpyconnect/visual_preferences');
  static const _events = EventChannel(
    'dev.scrcpyconnect/visual_preferences/events',
  );
  StreamSubscription<dynamic>? _subscription;
  AppLifecycleListener? _lifecycle;
  bool _started = false;
  bool _disposed = false;
  int _revision = -1;
  bool _reduceTransparency = false;

  bool get reduceTransparency => _reduceTransparency;

  void start() {
    if (_started || _disposed || kIsWeb) return;
    _started = true;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_refresh()));
    _subscription = _events
        .receiveBroadcastStream()
        .handleError(
          (Object _) {},
          test: (error) => error is MissingPluginException,
        )
        .listen(_accept);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      _accept(await _channel.invokeMethod<Object?>('read'));
    } on MissingPluginException {
      // 旧宿主使用框架提供的辅助偏好。
    }
  }

  void _accept(Object? value) {
    if (_disposed || value is! Map) return;
    final revision = value['revision'];
    final reduced = value['reduceTransparency'];
    if (revision is! int || revision <= _revision || reduced is! bool) return;
    _revision = revision;
    if (_reduceTransparency == reduced) return;
    _reduceTransparency = reduced;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
