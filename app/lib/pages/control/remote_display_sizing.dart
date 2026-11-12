import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/remote_display_settings.dart';
import 'package:scrcpy_connect/core/control/video_display.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/pages/control/remote_input_owner.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/pages/control/remote_window.dart';
import 'package:scrcpy_connect/core/media/models/video_session_view.dart';

/// 单个远控窗口的尺寸适配，持有防抖、输入法过渡和在途调整状态。
class RemoteDisplaySizing {
  RemoteDisplaySizing({
    required this.window,
    required this.displays,
    required this.inputs,
    required this.foreground,
    required this.onChanged,
    required this.onFailure,
  });

  final RemoteWindow window;
  final VideoDisplayControl displays;
  final RemoteInputOwner inputs;
  final bool Function() foreground;
  final VoidCallback onChanged;
  final ValueChanged<Object> onFailure;
  final _initialViewport = Completer<Size>();
  Size? _viewport;
  ({int width, int height})? _requested;
  ({int width, int height})? _scheduled;
  RemoteBinding? _scheduledBinding;
  ({int width, int height})? _lastGeometry;
  Timer? _timer;
  bool _auto = false;
  bool _resizing = false;
  bool _waitingForIme = false;
  bool _keyboardVisible = false;
  Size? _imeRequestedWindowSize;
  bool _disposed = false;

  Future<Size> get initialViewport => _initialViewport.future;
  bool get _imeBlocked => _waitingForIme || _keyboardVisible;
  bool get _hasInputAuthority =>
      window.isCurrent &&
      window.presentation.canSendInput(
        foreground: foreground(),
        ownerCurrent: window.view?.isCurrent == true,
      );
  bool get canSendInput => !_disposed && !_resizing && _hasInputAuthority;

  void bind(VideoSessionView view) {
    final session = view.session;
    _auto = session.displayAuto;
    if (session.displayWidth case final width?) {
      if (session.displayHeight case final height?) {
        _requested = (width: width, height: height);
      }
    }
  }

  void requestIme(Size windowSize) {
    _waitingForIme = true;
    _imeRequestedWindowSize = windowSize;
    _timer?.cancel();
  }

  void finishIme() {
    if (_disposed || !_waitingForIme) return;
    _waitingForIme = false;
    onChanged();
  }

  void observeInsets({
    required bool keyboardVisible,
    required Size windowSize,
  }) {
    _keyboardVisible = keyboardVisible;
    // 硬件键盘可能没有 inset；宿主真实尺寸变化仍须结束同窗口的输入法等待。
    if (keyboardVisible ||
        (_waitingForIme && _imeRequestedWindowSize != windowSize)) {
      _waitingForIme = false;
    }
    if (_imeBlocked) _timer?.cancel();
  }

  void reconsider() {
    if (_viewport case final size?) observeViewport(size);
  }

  void observeViewport(Size size) {
    if (_disposed) return;
    if (_imeBlocked) {
      _timer?.cancel();
      return;
    }
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    _viewport = size;
    if (!_initialViewport.isCompleted) _initialViewport.complete(size);
    if (!_auto || window.presentation.sessionId.isEmpty || !canSendInput) {
      return;
    }
    final target = const RemoteDisplaySettings(
      DevicePreferences(remoteAspectRatio: ScreenAspectRatio.automatic),
    ).dimensions(size);
    if (target == null || target == _requested) {
      _timer?.cancel();
      return;
    }
    final binding = window.presentation.binding;
    // 帧重建不应无限推迟同一尺寸、同一绑定的防抖任务。
    if (_timer?.isActive == true &&
        _scheduled == target &&
        _scheduledBinding == binding) {
      return;
    }
    _timer?.cancel();
    _scheduled = target;
    _scheduledBinding = binding;
    _trace('display.scheduled target=$target binding=$binding viewport=$size');
    _timer = Timer(const Duration(milliseconds: 250), () async {
      if (!canSendInput ||
          binding != window.presentation.binding ||
          _imeBlocked) {
        return;
      }
      _resizing = true;
      onChanged();
      try {
        await inputs.releaseInputs();
        if (_disposed ||
            !_hasInputAuthority ||
            binding != window.presentation.binding ||
            _imeBlocked) {
          return;
        }
        _requested = target;
        _trace('display.request target=$target binding=$binding');
        await displays.resizeDisplay(
          ControlTarget(sessionId: binding.$1),
          target,
        );
        _trace(
          'display.return target=$target current=${window.presentation.binding} submitted=$binding',
        );
      } catch (failure) {
        _trace(
          'display.failed target=$target binding=$binding failure=$failure',
        );
        if (!_disposed && binding == window.presentation.binding) {
          onFailure(failure);
        }
      } finally {
        if (!_disposed) {
          _resizing = false;
          onChanged();
          reconsider();
        }
      }
    });
  }

  void observeGeometry() {
    if (!_auto || _viewport == null) return;
    final session = window.presentation.session;
    final width = int.tryParse('${session?['width']}');
    final height = int.tryParse('${session?['height']}');
    if (width == null || height == null || width <= 0 || height <= 0) return;
    final geometry = (width: width, height: height);
    if (geometry == _lastGeometry) return;
    _lastGeometry = geometry;
    final target = const RemoteDisplaySettings(
      DevicePreferences(remoteAspectRatio: ScreenAspectRatio.automatic),
    ).dimensions(_viewport!);
    if (target != null &&
        (width / height - target.width / target.height).abs() > .005) {
      // 手机旋转改变自然坐标映射，视口未变也要重新适配。
      _requested = null;
      reconsider();
    }
  }

  void cancel() {
    _timer?.cancel();
    _scheduled = null;
    _scheduledBinding = null;
  }

  void dispose() {
    _disposed = true;
    cancel();
    if (!_initialViewport.isCompleted) _initialViewport.complete(Size.zero);
  }

  void _trace(String detail) {
    if (const bool.fromEnvironment('CONNECT_DIAGNOSTICS')) {
      debugPrint(
        '[connect.remote ${DateTime.now().millisecondsSinceEpoch}] $detail',
      );
    }
  }
}
