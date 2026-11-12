import 'package:flutter/material.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

class RemoteNavigationBar extends StatelessWidget {
  const RemoteNavigationBar({
    super.key,
    required this.enabled,
    required this.onBack,
    required this.onHome,
    required this.onRecent,
  });

  final bool enabled;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onRecent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconColor = enabled
        ? colors.onSurface
        : colors.onSurface.withValues(alpha: 0.38);
    return ColoredBox(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant,
                width: DesignTokens.spacingHairline,
              ),
            ),
          ),
          child: SizedBox(
            height: DesignTokens.componentPageHeaderHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _button(
                  tooltip: '返回',
                  enabled: enabled,
                  onPressed: onBack,
                  glyph: _RemoteNavigationGlyph.back,
                  color: iconColor,
                ),
                _button(
                  tooltip: '主屏幕',
                  enabled: enabled,
                  onPressed: onHome,
                  glyph: _RemoteNavigationGlyph.home,
                  color: iconColor,
                ),
                _button(
                  tooltip: '最近任务',
                  enabled: enabled,
                  onPressed: onRecent,
                  glyph: _RemoteNavigationGlyph.recent,
                  color: iconColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button({
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
    required _RemoteNavigationGlyph glyph,
    required Color color,
  }) => SizedBox(
    width: DesignTokens.componentIconButtonSize,
    height: DesignTokens.componentIconButtonSize,
    child: IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      iconSize: DesignTokens.componentIconSize,
      icon: CustomPaint(
        size: const Size.square(DesignTokens.componentIconSize),
        painter: _RemoteNavigationGlyphPainter(glyph, color),
      ),
    ),
  );
}

enum _RemoteNavigationGlyph { back, home, recent }

class _RemoteNavigationGlyphPainter extends CustomPainter {
  const _RemoteNavigationGlyphPainter(this.glyph, this.color);

  final _RemoteNavigationGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    if (glyph == _RemoteNavigationGlyph.back) {
      canvas.scale(size.width / 28, size.height / 28);
      final triangle = Path()
        ..moveTo(6.49, 14.86)
        ..cubicTo(5.83, 14.47, 5.83, 13.52, 6.49, 13.13)
        ..lineTo(12.51, 9.60)
        ..lineTo(18.40, 6.14)
        ..cubicTo(19.11, 5.73, 20, 6.26, 20, 7.10)
        ..lineTo(20, 20.90)
        ..cubicTo(20, 21.74, 19.11, 22.27, 18.40, 21.85)
        ..lineTo(12.51, 18.39)
        ..close();
      canvas.drawPath(triangle, paint..style = PaintingStyle.fill);
    } else {
      canvas.scale(size.width / 22, size.height / 22);
      paint.style = PaintingStyle.stroke;
      if (glyph == _RemoteNavigationGlyph.home) {
        canvas.drawOval(Rect.fromLTWH(1.833, 1.833, 18.334, 18.334), paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2.75, 2.75, 16.5, 16.5),
            const Radius.circular(2),
          ),
          paint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RemoteNavigationGlyphPainter oldDelegate) =>
      glyph != oldDelegate.glyph || color != oldDelegate.color;
}
