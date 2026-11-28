import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/platform/desktop_window.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// designs/design.md「桌面窗口标题栏」；Ardot 桌面标题栏组件 41:1357。
abstract final class DesktopTitleBarMetrics {
  static const height = 40.0;
  static const buttonSize = 28.0;
  static const buttonGap = 6.0;
  static const endPadding = 6.0;
  static const glyphStroke = 1.5;
  static const glyphWidth = 10.0;
  static const glyphRadius = 3.0;
  static const restoreLayerSize = 9.0;
  static const closeGlyphSize = 14.0;
}

enum DesktopWindowGlyph { minimize, maximize, restore, close }

/// App-drawn title bar for Windows and Linux main windows.
class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({
    super.key,
    required this.title,
    required this.maximized,
    required this.controls,
  });

  final String title;
  final bool maximized;
  final DesktopWindowControls controls;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final style = AppTypography.of(context).footnote
        .copyWith(fontWeight: FontWeight.w600);
    // 标题栏挂在页面导航之上；Material 提供正常的默认文字样式，避免调试下划线。
    return Material(
      color: colors.card,
      child: SizedBox(
        height: DesktopTitleBarMetrics.height,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onPanStart: (_) => unawaited(controls.startMove()),
                onDoubleTap: () => unawaited(controls.toggleMaximized()),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: DesignTokens.spacingLg,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // 40 高的栏在 200% 字号下仍容纳一行。
                        textScaler: MediaQuery.textScalerOf(context)
                            .clamp(maxScaleFactor: 2),
                        style: style,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: DesktopTitleBarMetrics.buttonGap),
            _WindowButton(
              label: '最小化',
              glyph: DesktopWindowGlyph.minimize,
              onPressed: controls.minimize,
            ),
            const SizedBox(width: DesktopTitleBarMetrics.buttonGap),
            _WindowButton(
              label: maximized ? '还原' : '最大化',
              glyph: maximized
                  ? DesktopWindowGlyph.restore
                  : DesktopWindowGlyph.maximize,
              onPressed: controls.toggleMaximized,
            ),
            const SizedBox(width: DesktopTitleBarMetrics.buttonGap),
            _WindowButton(
              label: '关闭',
              glyph: DesktopWindowGlyph.close,
              onPressed: controls.close,
            ),
            const SizedBox(width: DesktopTitleBarMetrics.endPadding),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends HookWidget {
  const _WindowButton({
    required this.label,
    required this.glyph,
    required this.onPressed,
  });

  final String label;
  final DesktopWindowGlyph glyph;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final hovered = useState(false);
    final pressed = useState(false);
    final colors = AppColors.of(context);
    final close = glyph == DesktopWindowGlyph.close;
    final active = hovered.value || pressed.value;
    // 悬停加深一档：块面 → 内嵌；关闭为 destructive 底配白色图形。按住再叠 pressed。
    final hoverFill = close ? colors.destructive : colors.inset;
    final fill = pressed.value
        ? Color.alphaBlend(colors.pressed, hoverFill)
        : active
        ? hoverFill
        : colors.block;
    final ink = close && active ? DesignTokens.colorOnMedia : colors.text;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: () => unawaited(onPressed()),
      child: MouseRegion(
        onEnter: (_) => hovered.value = true,
        onExit: (_) {
          hovered.value = false;
          pressed.value = false;
        },
        child: GestureDetector(
          onTapDown: (_) => pressed.value = true,
          onTapCancel: () => pressed.value = false,
          onTapUp: (_) => pressed.value = false,
          onTap: () => unawaited(onPressed()),
          child: CustomPaint(
            size: const Size.square(DesktopTitleBarMetrics.buttonSize),
            painter: DesktopWindowGlyphPainter(
              glyph: glyph,
              fill: fill,
              ink: ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the circular key and its 1.5-stroke round-capped glyph.
class DesktopWindowGlyphPainter extends CustomPainter {
  const DesktopWindowGlyphPainter({
    required this.glyph,
    required this.fill,
    required this.ink,
  });

  final DesktopWindowGlyph glyph;
  final Color fill;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(center, size.shortestSide / 2, Paint()..color = fill);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = DesktopTitleBarMetrics.glyphStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const radius = Radius.circular(DesktopTitleBarMetrics.glyphRadius);
    switch (glyph) {
      case DesktopWindowGlyph.minimize:
        // 含圆头的总长为 10。
        const half =
            (DesktopTitleBarMetrics.glyphWidth -
                DesktopTitleBarMetrics.glyphStroke) /
            2;
        canvas.drawLine(
          center.translate(-half, 0),
          center.translate(half, 0),
          stroke,
        );
      case DesktopWindowGlyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: center,
              width: DesktopTitleBarMetrics.glyphWidth,
              height: DesktopTitleBarMetrics.glyphWidth,
            ),
            radius,
          ),
          stroke,
        );
      case DesktopWindowGlyph.restore:
        // 两个 9 方块错开 3：后层右上，前层左下并以键底遮住后层。
        const layer = DesktopTitleBarMetrics.restoreLayerSize;
        const offset = 1.5;
        RRect square(Offset at) => RRect.fromRectAndRadius(
          Rect.fromCenter(center: at, width: layer, height: layer),
          radius,
        );
        final back = square(center.translate(offset, -offset));
        final front = square(center.translate(-offset, offset));
        canvas
          ..drawRRect(back, stroke)
          ..drawRRect(front, Paint()..color = fill)
          ..drawRRect(front, stroke);
      case DesktopWindowGlyph.close:
        // Lucide x：24 格中 6→18 的两条对角线，缩放到 14。
        const extent = DesktopTitleBarMetrics.closeGlyphSize * 6 / 24;
        canvas
          ..drawLine(
            center.translate(-extent, -extent),
            center.translate(extent, extent),
            stroke,
          )
          ..drawLine(
            center.translate(extent, -extent),
            center.translate(-extent, extent),
            stroke,
          );
    }
  }

  @override
  bool shouldRepaint(DesktopWindowGlyphPainter oldDelegate) =>
      glyph != oldDelegate.glyph ||
      fill != oldDelegate.fill ||
      ink != oldDelegate.ink;
}
