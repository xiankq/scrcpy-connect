import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
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
            height: DesignTokens.componentRemoteNavigationHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const buttonWidth = DesignTokens.componentIconButtonSize;
                final edgePadding = math
                    .min(
                      DesignTokens.componentRemoteNavigationPadding,
                      math.max(0, (constraints.maxWidth - buttonWidth * 3) / 4),
                    )
                    .toDouble();
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: edgePadding),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                );
              },
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
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    if (glyph == _RemoteNavigationGlyph.back) {
      canvas.scale(size.width / 20, size.height / 20);
      final triangle = Path()
        ..moveTo(5, 8.6)
        ..lineTo(14.6, 3.2)
        ..cubicTo(16.13, 2.33, 16.9, 2.77, 16.9, 4.5)
        ..lineTo(16.9, 15.5)
        ..cubicTo(16.9, 17.23, 16.13, 17.67, 14.6, 16.8)
        ..lineTo(5, 11.4)
        ..cubicTo(3.33, 10.47, 3.33, 9.53, 5, 8.6)
        ..close();
      canvas.drawPath(triangle, paint..strokeWidth = 1.8);
    } else {
      canvas.scale(size.width / 22, size.height / 22);
      if (glyph == _RemoteNavigationGlyph.home) {
        canvas.drawOval(Rect.fromLTWH(1.833, 1.833, 18.334, 18.334), paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2.75, 2.75, 16.5, 16.5),
            Radius.circular(DesignTokens.spacingMicro),
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
