import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/platform/desktop_window.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// Draws one window control group above the navigator of this engine.
class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame> {
  static const _buttonHeight = DesignTokens.componentDesktopWindowButtonHeight;
  static const _horizontalInset = DesignTokens.spacingSm;
  static const _edge = DesignTokens.componentDesktopResizeEdgeWidth;
  static const _clearance =
      _horizontalInset * 2 + DesignTokens.componentDesktopWindowButtonWidth * 3;
  static const _resizeEdges = [
    ('top', Alignment.topCenter, SystemMouseCursors.resizeUpDown),
    ('left', Alignment.centerLeft, SystemMouseCursors.resizeLeftRight),
    ('right', Alignment.centerRight, SystemMouseCursors.resizeLeftRight),
    ('bottom', Alignment.bottomCenter, SystemMouseCursors.resizeUpDown),
    ('topLeft', Alignment.topLeft, SystemMouseCursors.resizeUpLeftDownRight),
    ('topRight', Alignment.topRight, SystemMouseCursors.resizeUpRightDownLeft),
    (
      'bottomLeft',
      Alignment.bottomLeft,
      SystemMouseCursors.resizeUpRightDownLeft,
    ),
    (
      'bottomRight',
      Alignment.bottomRight,
      SystemMouseCursors.resizeUpLeftDownRight,
    ),
  ];

  bool get _mac => defaultTargetPlatform == TargetPlatform.macOS;
  final _state = ValueNotifier(DesktopWindowState.normal);
  late final _controls = OverlayEntry(
    builder: (context) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      return Positioned(
        top: (DesignTokens.componentPageHeaderHeight - _buttonHeight) / 2,
        left: _mac ? _horizontalInset : null,
        right: _mac ? null : _horizontalInset,
        child: Material(
          color: colors.surface,
          shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
          child: ValueListenableBuilder(
            valueListenable: _state,
            builder: (context, state, _) {
              final full = state == DesktopWindowState.fullscreen;
              final maximized = state == DesktopWindowState.maximized;
              const close = _WindowButton(
                label: '关闭窗口',
                icon: LucideIcons.x,
                command: 'close',
                destructive: true,
              );
              final minimize = _WindowButton(
                label: '最小化',
                icon: LucideIcons.minus,
                command: 'minimize',
                enabled: !full,
              );
              final expand = _WindowButton(
                label: full
                    ? '退出全屏'
                    : _mac
                    ? '进入全屏'
                    : maximized
                    ? '还原窗口'
                    : '最大化',
                icon: full
                    ? LucideIcons.minimize2
                    : _mac
                    ? LucideIcons.maximize2
                    : maximized
                    ? LucideIcons.copy
                    : LucideIcons.square,
                command: full || _mac ? 'toggleFullscreen' : 'toggleMaximized',
              );
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: _mac
                    ? [close, minimize, expand]
                    : [minimize, expand, close],
              );
            },
          ),
        ),
      );
    },
  );

  @override
  void initState() {
    super.initState();
    DesktopWindow.channel.setMethodCallHandler((call) async {
      if (call.method == 'stateChanged') _setState(call.arguments as String);
    });
    unawaited(_loadState());
  }

  Future<void> _loadState() async {
    final state = await DesktopWindow.channel.invokeMethod<String>('state');
    if (mounted) _setState(state!);
  }

  void _setState(String name) =>
      _state.value = DesktopWindowState.values.byName(name);

  @override
  void dispose() {
    DesktopWindow.channel.setMethodCallHandler(null);
    _controls.remove();
    _controls.dispose();
    _state.dispose();
    super.dispose();
  }

  Widget _resizeGrip(String edge, Alignment alignment, MouseCursor cursor) =>
      Positioned(
        left: alignment.x <= 0 ? (alignment.x == 0 ? _edge : 0) : null,
        right: alignment.x >= 0 ? (alignment.x == 0 ? _edge : 0) : null,
        top: alignment.y <= 0 ? (alignment.y == 0 ? _edge : 0) : null,
        bottom: alignment.y >= 0 ? (alignment.y == 0 ? _edge : 0) : null,
        width: alignment.x == 0 ? null : _edge,
        height: alignment.y == 0 ? null : _edge,
        child: MouseRegion(
          cursor: cursor,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if (event.buttons == kPrimaryButton) {
                unawaited(DesktopWindow.command('resize', edge));
              }
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final linux = defaultTargetPlatform == TargetPlatform.linux;
    return DesktopWindowInsets(
      left: _mac ? _clearance : 0,
      right: _mac ? 0 : _clearance,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned.fill(
            child: Overlay(
              clipBehavior: Clip.none,
              initialEntries: [_controls],
            ),
          ),
          if (!_mac)
            ValueListenableBuilder(
              valueListenable: _state,
              builder: (context, state, _) => state != DesktopWindowState.normal
                  ? const SizedBox.shrink()
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        for (final (edge, alignment, cursor)
                            in linux ? _resizeEdges : _resizeEdges.take(1))
                          _resizeGrip(edge, alignment, cursor),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.label,
    required this.icon,
    required this.command,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final String command;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Semantics(
        label: label,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: IconButton(
            key: ValueKey('desktop-window-$command'),
            onPressed: enabled
                ? () => unawaited(DesktopWindow.command(command))
                : null,
            style: IconButton.styleFrom(
              fixedSize: const Size(
                DesignTokens.componentDesktopWindowButtonWidth,
                DesignTokens.componentDesktopWindowButtonHeight,
              ),
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: colors.onSurfaceVariant,
              overlayColor: destructive ? colors.error : colors.onSurface,
            ),
            icon: Icon(
              icon,
              size: DesignTokens.componentDesktopWindowSymbolSize,
            ),
          ),
        ),
      ),
    );
  }
}

/// Reserves the physical edge occupied by the window buttons within a pane.
class DesktopWindowInsets extends InheritedWidget {
  const DesktopWindowInsets({
    super.key,
    required this.left,
    required this.right,
    required super.child,
  });

  final double left;
  final double right;

  static DesktopWindowInsets? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopWindowInsets>();

  @override
  bool updateShouldNotify(DesktopWindowInsets oldWidget) =>
      left != oldWidget.left || right != oldWidget.right;
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

/// Immersive pages without an application toolbar use a quiet draggable strip.
class DesktopStage extends StatelessWidget {
  const DesktopStage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (DesktopWindowInsets.of(context) == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DesktopWindowDragArea(
          child: SizedBox(height: DesignTokens.componentPageHeaderHeight),
        ),
        Expanded(child: child),
      ],
    );
  }
}
