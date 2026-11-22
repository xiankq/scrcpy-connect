import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/platform/desktop_window.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// Publishes the space occupied by the native controls for this window only.
class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame> {
  DesktopWindowLayout _layout = (left: 0, right: 0, top: 0);

  @override
  void initState() {
    super.initState();
    DesktopWindow.channel.setMethodCallHandler((call) async {
      if (call.method == 'layoutChanged') {
        _update(DesktopWindow.decodeLayout(call.arguments as Map));
      }
    });
    unawaited(_readLayout());
  }

  Future<void> _readLayout() async {
    final layout = await DesktopWindow.readLayout();
    if (mounted) _update(layout);
  }

  void _update(DesktopWindowLayout layout) {
    if (layout != _layout) setState(() => _layout = layout);
  }

  @override
  void dispose() {
    DesktopWindow.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DesktopWindowInsets(
    left: _layout.left,
    right: _layout.right,
    top: _layout.top,
    child: widget.child,
  );
}

/// Reserves the physical edge occupied by the window buttons within a pane.
class DesktopWindowInsets extends InheritedWidget {
  const DesktopWindowInsets({
    super.key,
    required this.left,
    required this.right,
    required this.top,
    required super.child,
  });

  final double left;
  final double right;
  final double top;

  static DesktopWindowInsets? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopWindowInsets>();

  @override
  bool updateShouldNotify(DesktopWindowInsets oldWidget) =>
      left != oldWidget.left ||
      right != oldWidget.right ||
      top != oldWidget.top;
}

/// Only a toolbar's passive title and blank space initiate a window drag.
class DesktopWindowDragArea extends StatelessWidget {
  const DesktopWindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (DesktopWindowInsets.of(context) == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onPanStart: (_) => unawaited(DesktopWindow.command('move')),
      onDoubleTap: () => unawaited(DesktopWindow.command('toggleMaximized')),
      child: child,
    );
  }
}

/// The stage paints to the window edge. Only its narrow top edge is draggable.
class DesktopStage extends StatelessWidget {
  const DesktopStage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final window = DesktopWindowInsets.of(context);
    if (window == null || window.top == 0) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: window.left,
          right: window.right,
          top: 0,
          child: const DesktopWindowDragArea(
            child: SizedBox(height: DesignTokens.spacingSm),
          ),
        ),
      ],
    );
  }
}
