import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ExitHandle extends StatefulWidget {
  const ExitHandle({
    super.key,
    required this.onExit,
    required this.deviceLabel,
  });
  final VoidCallback onExit;
  final String deviceLabel;
  static const initialOffset = Offset(12, 80);

  /// The initial overlay footprint also reserves space in recovery content.
  static Rect initialBoundsFor(Size viewport, MediaQueryData media) {
    final bounds = _dragBoundsFor(viewport, media);
    return Rect.fromLTWH(
      initialOffset.dx.clamp(bounds.left, bounds.right).toDouble(),
      initialOffset.dy.clamp(bounds.top, bounds.bottom).toDouble(),
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
  Offset offset = ExitHandle.initialOffset;
  bool collapsed = false;
  bool dragging = false;
  bool right = false;
  bool dragStartedCollapsed = false;
  double dragStartX = 0;
  Size viewport = Size.zero;
  Rect dragBounds = Rect.zero;
  double collapsedRight = 0;
  void activateControl() {
    animation.stop();
    if (!collapsed) {
      widget.onExit();
      return;
    }
    setState(() {
      collapsed = false;
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
      setState(() {});
      return;
    }
    right = offset.dx > (dragBounds.left + dragBounds.right) / 2;
    collapsed = true;
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      viewport = constraints.biggest;
      final media = MediaQuery.of(context);
      final padding = media.padding;
      final gestures = media.systemGestureInsets;
      final rightInset = math.max(padding.right, gestures.right);
      dragBounds = _dragBoundsFor(viewport, media);
      collapsedRight = math.max(
        dragBounds.left,
        viewport.width - rightInset - 44,
      );
      final dx = offset.dx.clamp(dragBounds.left, dragBounds.right).toDouble();
      final dy = offset.dy.clamp(dragBounds.top, dragBounds.bottom).toDouble();
      return Stack(
        children: [
          Positioned(
            left: collapsed && right && !dragging ? collapsedRight : dx,
            top: dy,
            width: collapsed && !dragging
                ? DesignTokens.componentRemoteExitHitWidth
                : DesignTokens.componentRemoteExitSize,
            height: DesignTokens.componentRemoteExitHitHeight,
            child: Semantics(
              container: true,
              label: collapsed
                  ? '展开退出按钮，${widget.deviceLabel}'
                  : '退出控制，返回${widget.deviceLabel}',
              button: true,
              child: GlassPressFeedback(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => animation.stop(),
                  onPanStart: (_) {
                    animation.stop();
                    setState(() {
                      dragStartedCollapsed = collapsed;
                      dragStartX = dx;
                      dragging = true;
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
                            : const Icon(
                                LucideIcons.x,
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
