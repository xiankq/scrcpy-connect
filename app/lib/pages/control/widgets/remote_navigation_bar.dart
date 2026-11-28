import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// 远控三键栏（Ardot「远控 / 三键栏」37:1097）：`viewport` 底、高 48，
/// 三键均分宽度，图形 24、2 点 `on-media` 描边。
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

  /// 媒体上的禁用前景，与 `disabled` 同为 38%。
  static const _disabledOpacity = .38;

  @override
  Widget build(BuildContext context) {
    const foreground = DesignTokens.colorOnMedia;
    final color = enabled
        ? foreground
        : foreground.withValues(alpha: _disabledOpacity);
    return ColoredBox(
      color: DesignTokens.componentRemoteViewportBackgroundColor,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: DesignTokens.componentRemoteNavigationHeight,
          child: Row(
            children: [
              for (final (tooltip, glyph, callback) in [
                ('返回', _RemoteNavigationGlyph.back, onBack),
                ('主屏幕', _RemoteNavigationGlyph.home, onHome),
                ('最近任务', _RemoteNavigationGlyph.recent, onRecent),
              ])
                Expanded(
                  child: IconButton(
                    tooltip: tooltip,
                    onPressed: enabled ? callback : null,
                    iconSize: DesignTokens.componentBarGlyphSize,
                    constraints: const BoxConstraints.expand(),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      shape: const RoundedSuperellipseBorder(),
                      highlightColor: foreground.withValues(
                        alpha:
                            DesignTokens.componentGlassInteractionGlowIntensity,
                      ),
                    ),
                    icon: CustomPaint(
                      size: const Size.square(
                        DesignTokens.componentBarGlyphSize,
                      ),
                      painter: _RemoteNavigationGlyphPainter(glyph, color),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RemoteNavigationGlyph { back, home, recent }

/// 几何取自 Ardot 37:1100（返回三角 9×13 于 7,5.5）、37:1103（主屏幕圆 15 于 4.5）、
/// 37:1106（最近任务方块 13 于 5.5，圆角 3），画布 24。
class _RemoteNavigationGlyphPainter extends CustomPainter {
  const _RemoteNavigationGlyphPainter(this.glyph, this.color);

  final _RemoteNavigationGlyph glyph;
  final Color color;

  static const _canvas = DesignTokens.componentBarGlyphSize;
  static const _strokeWidth = 2.0;
  static const _recentRadius = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    canvas.scale(size.width / _canvas, size.height / _canvas);
    switch (glyph) {
      case _RemoteNavigationGlyph.back:
        final triangle = Path()
          ..moveTo(16, 5.5)
          ..lineTo(16, 18.5)
          ..lineTo(7, 12)
          ..close();
        canvas.drawPath(triangle, paint);
      case _RemoteNavigationGlyph.home:
        canvas.drawOval(const Rect.fromLTWH(4.5, 4.5, 15, 15), paint);
      case _RemoteNavigationGlyph.recent:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(5.5, 5.5, 13, 13),
            const Radius.circular(_recentRadius),
          ),
          paint,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RemoteNavigationGlyphPainter oldDelegate) =>
      glyph != oldDelegate.glyph || color != oldDelegate.color;
}
