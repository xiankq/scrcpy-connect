// Flutter 3.50 desktop windowing is experimental. Keep its imports here.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';
import 'package:scrcpy_connect/widgets/window_environment_scope.dart';

/// Enable the single-engine desktop views while keeping the runner's main view.
void enableDesktopRemoteWindows() {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    isWindowingEnabled = true;
  }
}

final class DesktopRemoteWindow
    with WindowControllerDelegate, WidgetsBindingObserver {
  // Flutter 3.50's macOS embedder routes accessibility updates to the main view.
  static bool get sharesAccessibilityTree => Platform.isMacOS;

  DesktopRemoteWindow(
    this._navigationHeight, {
    required String title,
    required this.close,
    required this.destroyed,
    required Size? screenSize,
  }) : _aspectRatio = screenSize?.aspectRatio {
    const portrait = Size(460, 780);
    final aspect = _aspectRatio;
    final size = aspect == null
        ? portrait
        : _fitScreen(aspect >= 1 ? portrait.flipped : portrait);
    controller = WindowController(
      size: size,
      constraints: aspect == null
          ? const BoxConstraints(minWidth: 320, minHeight: 320)
          : null,
      title: title,
      delegate: this,
    );
    if (aspect != null) {
      _lastSize = size;
      if (Platform.isLinux) {
        // GTK's configure signal can precede the Flutter view allocation.
        WidgetsBinding.instance.addObserver(this);
      } else {
        controller.addListener(_keepScreenRatio);
      }
    }
  }

  late final WindowController controller;
  final VoidCallback close;
  final VoidCallback destroyed;
  double? _aspectRatio;
  // The navigation bar occupies a separate strip below the phone image.
  double _navigationHeight;
  Size? _lastSize;
  Timer? _linuxResize;

  bool get focused => !controller.isDestroyed && controller.isActivated;

  void activate() {
    if (controller.isMinimized) controller.setMinimized(false);
    controller.activate();
  }

  Size _fitScreen(Size bounds) {
    final aspect = _aspectRatio!;
    final width = math.min(
      bounds.width,
      (bounds.height - _navigationHeight) * aspect,
    );
    return Size(width, width / aspect + _navigationHeight);
  }

  bool get _canResize =>
      !controller.isDestroyed &&
      !controller.isMinimized &&
      !controller.isMaximized &&
      !controller.isFullscreen;

  void updateScreenGeometry(Size screenSize, double navigationHeight) {
    final previous = _aspectRatio;
    if (previous == null) return;
    final aspect = screenSize.aspectRatio;
    if ((previous - aspect).abs() < .001 &&
        _navigationHeight == navigationHeight) {
      return;
    }
    _aspectRatio = aspect;
    final previousNavigationHeight = _navigationHeight;
    _navigationHeight = navigationHeight;
    if (!_canResize) return;
    final size = controller.contentSize;
    final view = controller.rootView;
    final available = view.display.size / view.display.devicePixelRatio;
    final longest = math.max(
      size.width,
      size.height - previousNavigationHeight,
    );
    controller.setSize(
      _fitScreen(
        Size(
          math.min(longest, available.width),
          math.min(longest + navigationHeight, available.height),
        ),
      ),
    );
  }

  void _keepScreenRatio() {
    if (!_canResize) return;
    final view = controller.rootView;
    final size = Platform.isLinux
        ? view.physicalSize / view.devicePixelRatio
        : controller.contentSize;
    final old = _lastSize;
    if (size == old) return;
    _lastSize = size;
    final aspect = _aspectRatio!;
    final contentHeight = size.height - _navigationHeight;
    if (contentHeight <= 0 ||
        (size.width - contentHeight * aspect).abs() <= math.max(1, aspect)) {
      return;
    }
    final widthChangedMore =
        old == null ||
        (size.width - old.width).abs() >
            (size.height - old.height).abs() * aspect;
    final corrected = widthChangedMore
        ? Size(size.width, size.width / aspect + _navigationHeight)
        : Size(contentHeight * aspect, size.height);
    scheduleMicrotask(() {
      if (_canResize && controller.contentSize == size) {
        controller.setSize(corrected);
      }
    });
  }

  @override
  void didChangeMetrics() {
    _linuxResize?.cancel();
    // Let GTK finish allocating the view before requesting the corrected size.
    _linuxResize = Timer(const Duration(milliseconds: 250), _keepScreenRatio);
  }

  void setTitle(String title) {
    if (!controller.isDestroyed && controller.title != title) {
      controller.setTitle(title);
    }
  }

  void dispose() {
    if (Platform.isLinux && _aspectRatio != null) {
      WidgetsBinding.instance.removeObserver(this);
      _linuxResize?.cancel();
    }
    controller.destroy();
    controller.dispose();
  }

  @override
  void onWindowCloseRequested(WindowController controller) => close();

  @override
  void onWindowDestroyed() => destroyed();
}

class DesktopRemoteWindowView extends StatefulWidget {
  const DesktopRemoteWindowView({
    super.key,
    required this.window,
    required this.builder,
  });

  final DesktopRemoteWindow window;
  final Widget Function({required bool visible, required bool focused}) builder;

  @override
  State<DesktopRemoteWindowView> createState() =>
      _DesktopRemoteWindowViewState();
}

class _DesktopRemoteWindowViewState extends State<DesktopRemoteWindowView>
    with WidgetsBindingObserver {
  bool? _focused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    final viewId = widget.window.controller.rootView.viewId;
    final focused = event.state == ViewFocusState.focused;
    if (focused || viewId == event.viewId) {
      setState(() => _focused = focused && viewId == event.viewId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.window.controller;
    if (controller.isDestroyed) return const ViewCollection(views: []);
    final theme = Theme.of(context);
    return Window(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          final visible = !controller.isDestroyed && !controller.isMinimized;
          final focused = visible && (_focused ?? controller.isActivated);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            builder: (context, _) => DesktopWindowInsets(
              left: 0,
              right: 0,
              top: 0,
              child: FlutterWindowEnvironment(
                mode: !controller.isDestroyed && controller.isFullscreen
                    ? WindowMode.fullScreen
                    : WindowMode.freeform,
                child: widget.builder(visible: visible, focused: focused),
              ),
            ),
          );
        },
      ),
    );
  }
}
