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
  @override
  State<ExitHandle> createState() => _ExitHandleState();
}

class _ExitHandleState extends State<ExitHandle>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation =
      AnimationController.unbounded(vsync: this)..addListener(() {
        setState(() {
          offset = Offset(animation.value, offset.dy);
        });
      });
  Offset offset = const Offset(12, 80);
  bool collapsed = false;
  bool dragging = false;
  bool right = false;
  Size viewport = Size.zero;
  void activateControl() {
    animation.stop();
    if (!collapsed) {
      widget.onExit();
      return;
    }
    final insets = MediaQuery.paddingOf(context);
    setState(() {
      collapsed = false;
      dragging = false;
      offset = Offset(
        right ? viewport.width - 64 : 12,
        offset.dy.clamp(
          insets.top + 12,
          math.max(insets.top + 12, viewport.height - insets.bottom - 64),
        ),
      );
    });
  }

  void settle(DragEndDetails detail) {
    dragging = false;
    final projected = offset.dx + detail.velocity.pixelsPerSecond.dx * .2;
    right = projected > viewport.width / 2;
    collapsed = true;
    final target = right ? viewport.width - 44 : 0.0;
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
      final insets = MediaQuery.paddingOf(context);
      final dx = offset.dx
          .clamp(0.0, math.max(0.0, viewport.width - 52))
          .toDouble();
      final dy = offset.dy
          .clamp(
            insets.top + 12,
            math.max(insets.top + 12, viewport.height - insets.bottom - 64),
          )
          .toDouble();
      return Stack(
        children: [
          Positioned(
            left: collapsed && right && !dragging ? viewport.width - 44 : dx,
            top: dy,
            width: collapsed && !dragging ? 44 : 52,
            height: 52,
            child: Semantics(
              container: true,
              label: collapsed
                  ? '展开退出按钮，${widget.deviceLabel}'
                  : '退出控制，返回${widget.deviceLabel}',
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => animation.stop(),
                onPanStart: (_) {
                  animation.stop();
                  setState(() {
                    dragging = true;
                    collapsed = false;
                    offset = Offset(dx, dy);
                  });
                },
                onPanUpdate: (details) => setState(() {
                  offset = Offset(
                    (offset.dx + details.delta.dx).clamp(
                      0,
                      viewport.width - 52,
                    ),
                    (offset.dy + details.delta.dy).clamp(
                      insets.top + 12,
                      math.max(
                        insets.top + 12,
                        viewport.height - insets.bottom - 64,
                      ),
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
                    radius: 999,
                    child: SizedBox(
                      width: collapsed && !dragging ? 12 : 52,
                      height: 52,
                      child: collapsed && !dragging
                          ? Center(
                              child: Container(
                                width: 3,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            )
                          : const Icon(LucideIcons.x, size: 23),
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
