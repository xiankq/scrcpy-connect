import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 宿主默认字族；字号和文字放大仍分别由设计角色与系统负责。
final class SystemTypography extends ChangeNotifier {
  static const _methods = MethodChannel('dev.scrcpyconnect/system_typography');
  static const _events = EventChannel(
    'dev.scrcpyconnect/system_typography/events',
  );
  StreamSubscription<dynamic>? _subscription;
  AppLifecycleListener? _lifecycle;
  bool _started = false;
  bool _disposed = false;
  int _revision = -1;
  String? _fontFamily;

  String? get fontFamily => _fontFamily;

  void start() {
    if (_started || _disposed || kIsWeb) return;
    _started = true;
    if (defaultTargetPlatform != TargetPlatform.linux &&
        defaultTargetPlatform != TargetPlatform.windows) {
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
      _accept(await _methods.invokeMethod<Object?>('read'));
    } on MissingPluginException {
      // 旧宿主使用主题的系统字族。
    }
  }

  void _accept(Object? value) {
    if (_disposed || value is! Map) return;
    final revision = value['revision'];
    final family = value['fontFamily'];
    if (revision is! int ||
        revision <= _revision ||
        family is! String ||
        family.trim().isEmpty) {
      return;
    }
    _revision = revision;
    if (_fontFamily == family) return;
    _fontFamily = family;
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
