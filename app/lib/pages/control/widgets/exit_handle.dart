import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/physics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

class ExitHandle extends StatefulWidget {
  const ExitHandle({
    super.key,
    required this.onExit,
    required this.deviceLabel,
    this.connectionLabel = '连接状态待核对',
    this.soundControl,
    this.onSleep,
    this.onScreenshot,
    this.onConvert,
    this.onKeyboard,
    this.onRotate,
    this.independent = false,
  });
  final VoidCallback onExit;
  final String deviceLabel;
  final String connectionLabel;
  final Widget? soundControl;
  final VoidCallback? onSleep, onScreenshot, onConvert, onKeyboard, onRotate;
  final bool independent;
  static const initialTopFraction = 0.44;

  /// 初始叠加区域也在恢复内容中预留位置。远控稿将快捷按钮放在右侧，
  /// 顶部随当前窗口高度取中部位置，避免把手机稿的固定左上角坐标带到
  /// 平板、折叠屏或自由缩放窗口。
  static Rect initialBoundsFor(Size viewport, MediaQueryData media) {
    final bounds = _dragBoundsFor(viewport, media);
    final top = (viewport.height * initialTopFraction).clamp(
      bounds.top,
      bounds.bottom,
    );
    return Rect.fromLTWH(
      bounds.right,
      top.toDouble(),
      DesignTokens.componentRemoteExitSize,
      DesignTokens.componentRemoteExitHitHeight,
    );
  }

  @override
  State<ExitHandle> createState() => _ExitHandleState();
}

Rect _dragBoundsFor(Size viewport, MediaQueryData media) {
  final padding = media.padding;
  final gestures = media.systemGestureInsets;
  final left = math.max(padding.left, gestures.left);
  final right = math.max(padding.right, gestures.right);
  final top = math.max(padding.top, gestures.top) + 12;
  final bottom = math.max(padding.bottom, gestures.bottom) + 12;
  return Rect.fromLTRB(
    left,
    top,
    math.max(left, viewport.width - right - 52),
    math.max(top, viewport.height - bottom - 52),
  );
}

class _ExitHandleState extends State<ExitHandle>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation =
      AnimationController.unbounded(vsync: this)..addListener(() {
        setState(() {
          offset = Offset(animation.value, offset.dy);
        });
      });
  Offset offset = Offset.zero;
  bool collapsed = false;
  bool expanded = false;
  bool dragging = false;
  bool right = false;
  bool dragStartedCollapsed = false;
  double dragStartX = 0;
  Size viewport = Size.zero;
  Rect dragBounds = Rect.zero;
  double collapsedRight = 0;
  bool layoutInitialized = false;

  void activateControl() {
    animation.stop();
    if (!collapsed) {
      setState(() => expanded = !expanded);
      return;
    }
    setState(() {
      collapsed = false;
      expanded = true;
      dragging = false;
      offset = Offset(
        (right ? dragBounds.right - 12 : dragBounds.left + 12).clamp(
          dragBounds.left,
          dragBounds.right,
        ),
        offset.dy.clamp(dragBounds.top, dragBounds.bottom),
      );
    });
  }

  void settle(DragEndDetails detail) {
    dragging = false;
    final movedInward = right ? offset.dx < dragStartX : offset.dx > dragStartX;
    if (dragStartedCollapsed && movedInward) {
      setState(() => expanded = true);
      return;
    }
    right = offset.dx > (dragBounds.left + dragBounds.right) / 2;
    collapsed = true;
    expanded = false;
    final target = right ? collapsedRight : dragBounds.left;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        offset = Offset(target, offset.dy);
      });
      return;
    }
    animation.value = offset.dx;
    animation.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 260, damping: 30),
        offset.dx,
        target,
        detail.velocity.pixelsPerSecond.dx,
      ),
    );
    setState(() {});
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  Widget _action(String label, IconData icon, VoidCallback? callback) =>
      ListTile(
        leading: Icon(icon),
        title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        onTap: callback == null
            ? null
            : () {
                setState(() => expanded = false);
                callback();
              },
        enabled: callback != null,
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      viewport = constraints.biggest;
      final media = MediaQuery.of(context);
      final padding = media.padding;
      final gestures = media.systemGestureInsets;
      final rightInset = math.max(padding.right, gestures.right);
      dragBounds = _dragBoundsFor(viewport, media);
      if (!layoutInitialized) {
        final initial = ExitHandle.initialBoundsFor(viewport, media);
        offset = initial.topLeft;
        right = true;
        layoutInitialized = true;
      } else {
        offset = Offset(
          offset.dx.clamp(dragBounds.left, dragBounds.right).toDouble(),
          offset.dy.clamp(dragBounds.top, dragBounds.bottom).toDouble(),
        );
      }
      collapsedRight = math.max(
        dragBounds.left,
        viewport.width - rightInset - DesignTokens.componentRemoteExitHitWidth,
      );
      final dx = offset.dx.clamp(dragBounds.left, dragBounds.right).toDouble();
      final dy = offset.dy.clamp(dragBounds.top, dragBounds.bottom).toDouble();
      final roomRight = viewport.width - rightInset - dx - 52;
      final roomLeft = dx - dragBounds.left;
      final growRight = roomRight >= roomLeft;
      final panelWidth = math.min(
        244.0,
        math.max(48.0, (growRight ? roomRight : roomLeft) - 8),
      );
      final panelLeft = (growRight ? dx + 60 : dx - panelWidth - 8)
          .clamp(
            dragBounds.left,
            math.max(dragBounds.left, viewport.width - rightInset - panelWidth),
          )
          .toDouble();
      final panelTop = math.max(
        dragBounds.top,
        math.min(dy, dragBounds.bottom - 120),
      );
      return Stack(
        children: [
          if (expanded && !dragging)
            Positioned(
              key: const ValueKey('remote-tool-panel-position'),
              left: panelLeft,
              top: panelTop,
              width: panelWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(48, dragBounds.bottom - panelTop + 52),
                ),
                child: ContentSurface(
                  key: const ValueKey('remote-tool-panel'),
                  radius: DesignTokens.roundedLg,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(DesignTokens.spacingMd),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                widget.deviceLabel,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                widget.connectionLabel,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        ?widget.soundControl,
                        _action('熄屏', LucideIcons.moon, widget.onSleep),
                        _action('截图', LucideIcons.camera, widget.onScreenshot),
                        if (!widget.independent)
                          _action(
                            '转为独立窗口',
                            LucideIcons.appWindow,
                            widget.onConvert,
                          ),
                        _action('键盘', LucideIcons.keyboard, widget.onKeyboard),
                        _action('旋转', LucideIcons.rotateCw, widget.onRotate),
                        _action('关闭画面', LucideIcons.x, widget.onExit),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            key: const ValueKey('remote-tool-handle-position'),
            left: collapsed && right && !dragging ? collapsedRight : dx,
            top: dy,
            width: collapsed && !dragging
                ? DesignTokens.componentRemoteExitHitWidth
                : DesignTokens.componentRemoteExitSize,
            height: DesignTokens.componentRemoteExitHitHeight,
            child: Semantics(
              container: true,
              label: collapsed
                  ? '展开画面工具，${widget.deviceLabel}，${widget.connectionLabel}'
                  : expanded
                  ? '收起画面工具，${widget.deviceLabel}，${widget.connectionLabel}'
                  : '展开画面工具，${widget.deviceLabel}，${widget.connectionLabel}',
              button: true,
              child: GlassPressFeedback(
                child: GestureDetector(
                  key: const ValueKey('remote-tool-handle'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => animation.stop(),
                  onPanStart: (_) {
                    animation.stop();
                    setState(() {
                      dragStartedCollapsed = collapsed;
                      dragStartX = dx;
                      dragging = true;
                      expanded = false;
                      collapsed = false;
                      offset = Offset(dx, dy);
                    });
                  },
                  onPanUpdate: (details) => setState(() {
                    offset = Offset(
                      (offset.dx + details.delta.dx).clamp(
                        dragBounds.left,
                        dragBounds.right,
                      ),
                      (offset.dy + details.delta.dy).clamp(
                        dragBounds.top,
                        dragBounds.bottom,
                      ),
                    );
                  }),
                  onPanEnd: settle,
                  onPanCancel: () {
                    if (dragging) settle(DragEndDetails());
                  },
                  onTap: activateControl,
                  child: Align(
                    alignment: collapsed && !dragging
                        ? (right ? Alignment.centerRight : Alignment.centerLeft)
                        : Alignment.center,
                    child: Glass(
                      variant: GlassVariant.regular,
                      radius: DesignTokens.roundedFull,
                      child: SizedBox(
                        width: collapsed && !dragging
                            ? DesignTokens.componentRemoteExitPeekWidth
                            : DesignTokens.componentRemoteExitSize,
                        height: DesignTokens.componentRemoteExitHitHeight,
                        child: collapsed && !dragging
                            ? Center(
                                child: Container(
                                  width: 3,
                                  height: DesignTokens.spacingMd,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              )
                            : Icon(
                                expanded
                                    ? LucideIcons.chevronUp
                                    : LucideIcons.ellipsis,
                                size: DesignTokens.componentIconFeatureSize,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
