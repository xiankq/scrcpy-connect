import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';

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
  static const _handleSize = DesignTokens.componentRemoteExitSize;
  static const _peekWidth = DesignTokens.componentRemoteExitPeekWidth;
  static const _hitWidth = DesignTokens.componentRemoteExitHitWidth;
  static const _hitHeight = DesignTokens.componentRemoteExitHitHeight;

  late final AnimationController animation =
      AnimationController.unbounded(vsync: this)..addListener(() {
        setState(() => offset = Offset(animation.value, offset.dy));
      });
  Rect dragBounds = Rect.zero;
  Offset offset = Offset.zero;
  bool initialized = false;
  bool expanded = false;
  bool dragging = false;
  bool right = true;
  bool get docked => !dragging && !animation.isAnimating;

  void settle([double velocity = 0]) {
    final midpoint = (dragBounds.left + dragBounds.right) / 2;
    final target = offset.dx >= midpoint ? dragBounds.right : dragBounds.left;
    setState(() {
      right = target == dragBounds.right;
      dragging = false;
    });
    if (MediaQuery.disableAnimationsOf(context) ||
        GlassMaterial.reduceMotion(context) ||
        (offset.dx - target).abs() < 0.5) {
      offset = Offset(target, offset.dy);
      return;
    }
    animation.value = offset.dx;
    animation
        .animateWith(
          SpringSimulation(
            const SpringDescription(mass: 1, stiffness: 260, damping: 30),
            offset.dx,
            target,
            velocity,
          ),
        )
        .whenComplete(() => setState(() {}));
  }

  void closePanel() => setState(() => expanded = false);

  VoidCallback? closeThen(VoidCallback? callback) => callback == null
      ? null
      : () {
          closePanel();
          callback();
        };

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = constraints.biggest;
      final sourceMedia = MediaQuery.of(context);
      final window = DesktopWindowInsets.of(context);
      final media = window == null
          ? sourceMedia
          : sourceMedia.copyWith(
              padding: sourceMedia.padding.copyWith(
                top: math.max(sourceMedia.padding.top, window.top),
              ),
            );
      dragBounds = _dragBoundsFor(viewport, media);
      if (!initialized) {
        offset = ExitHandle.initialBoundsFor(viewport, media).topLeft;
        initialized = true;
      }
      final rightEdge =
          viewport.width -
          math.max(media.padding.right, media.systemGestureInsets.right);
      final bottomEdge = dragBounds.bottom + _hitHeight;
      final dy = offset.dy.clamp(dragBounds.top, dragBounds.bottom).toDouble();
      final snapX = right ? dragBounds.right : dragBounds.left;
      final dx = docked
          ? snapX
          : offset.dx.clamp(dragBounds.left, dragBounds.right).toDouble();
      final handleLeft = docked && right
          ? math.max(dragBounds.left, rightEdge - _hitWidth)
          : dx;
      final panelWidth = math.min(
        DesignTokens.componentRemoteToolPanelWidth,
        math.max(0.0, rightEdge - dragBounds.left - 2 * DesignTokens.spacingMd),
      );
      final panelHeight = DesignTokens.componentRemoteToolPanelHeight;
      final panelLeft = viewport.width < 440
          ? dragBounds.left + (rightEdge - dragBounds.left - panelWidth) / 2
          : right
          ? rightEdge - panelWidth - DesignTokens.spacingLg
          : dragBounds.left + DesignTokens.spacingLg;
      final panelTop = (dy - 72)
          .clamp(
            dragBounds.top,
            math.max(dragBounds.top, bottomEdge - panelHeight),
          )
          .toDouble();

      return Stack(
        children: [
          if (expanded) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: closePanel,
                excludeFromSemantics: true,
              ),
            ),
            Positioned(
              left: panelLeft,
              top: panelTop,
              width: panelWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: bottomEdge - panelTop),
                child: Glass(
                  key: const ValueKey('remote-tool-panel'),
                  radius: DesignTokens.roundedLg,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '画面工具',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: '收起画面工具',
                              onPressed: closePanel,
                              icon: const Icon(LucideIcons.slidersHorizontal),
                            ),
                          ],
                        ),
                        Text(
                          widget.independent ? '独立窗口' : '整机画面',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: DesignTokens.spacingMd),
                        LayoutBuilder(
                          builder: (context, limits) {
                            final tileWidth =
                                limits.maxWidth /
                                (limits.maxWidth < 192 ? 2 : 3);
                            return Wrap(
                              runSpacing: DesignTokens.spacingXs,
                              children: [
                                for (final action in [
                                  widget.soundControl ??
                                      const RemoteToolAction(
                                        icon: LucideIcons.volume2,
                                        label: '设备声音',
                                      ),
                                  RemoteToolAction(
                                    icon: LucideIcons.sun,
                                    label: '熄屏',
                                    onPressed: closeThen(widget.onSleep),
                                  ),
                                  RemoteToolAction(
                                    icon: LucideIcons.camera,
                                    label: '截图',
                                    onPressed: closeThen(widget.onScreenshot),
                                  ),
                                  if (!widget.independent)
                                    RemoteToolAction(
                                      icon: LucideIcons.layers,
                                      label: '独立窗口',
                                      onPressed: closeThen(widget.onConvert),
                                    ),
                                  RemoteToolAction(
                                    icon: LucideIcons.keyboard,
                                    label: '键盘',
                                    onPressed: closeThen(widget.onKeyboard),
                                  ),
                                  RemoteToolAction(
                                    icon: LucideIcons.rotateCw,
                                    label: '旋转',
                                    onPressed: closeThen(widget.onRotate),
                                  ),
                                ])
                                  SizedBox(width: tileWidth, child: action),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: DesignTokens.spacingLg),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            fixedSize: const Size.fromHeight(50),
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surface,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                DesignTokens.roundedMd,
                              ),
                            ),
                          ),
                          onPressed: closeThen(widget.onExit),
                          child: const Text('关闭画面'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ] else
            Positioned(
              key: const ValueKey('remote-tool-handle-position'),
              left: handleLeft,
              top: dy,
              width: docked ? _hitWidth : _handleSize,
              height: _hitHeight,
              child: Semantics(
                label: '展开画面工具，${widget.deviceLabel}，${widget.connectionLabel}',
                button: true,
                child: GlassPressFeedback(
                  child: GestureDetector(
                    key: const ValueKey('remote-tool-handle'),
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: (_) {
                      animation.stop();
                      setState(() {
                        dragging = true;
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
                    onPanEnd: (details) =>
                        settle(details.velocity.pixelsPerSecond.dx),
                    onPanCancel: () {
                      if (dragging) settle();
                    },
                    onTap: () {
                      animation.stop();
                      setState(() => expanded = true);
                    },
                    child: Align(
                      alignment: right
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Glass(
                        radius: DesignTokens.roundedFull,
                        child: SizedBox(
                          width: docked ? _peekWidth : _handleSize,
                          height: _hitHeight,
                          child: docked
                              ? Center(
                                  child: Container(
                                    width: DesignTokens
                                        .componentRemoteExitHandleWidth,
                                    height: DesignTokens
                                        .componentRemoteExitHandleHeight,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      borderRadius: BorderRadius.circular(
                                        DesignTokens
                                            .componentRemoteExitHandleRounded,
                                      ),
                                    ),
                                  ),
                                )
                              : const Icon(LucideIcons.slidersHorizontal),
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

class RemoteToolAction extends StatelessWidget {
  const RemoteToolAction({
    super.key,
    required this.icon,
    required this.label,
    this.description,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final String? description;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final action = TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        minimumSize: const Size(0, 66),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMicro,
          vertical: DesignTokens.spacingXs,
        ),
      ),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: DesignTokens.componentIconFeatureSize),
          const SizedBox(height: DesignTokens.spacingMicro),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
    return description == null
        ? action
        : Tooltip(message: description!, child: action);
  }
}
