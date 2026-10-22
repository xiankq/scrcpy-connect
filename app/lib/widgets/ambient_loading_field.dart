import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Full-surface ambient waiting field for an operation that has been submitted
/// but has not produced its first verified result yet.
class AmbientLoadingField extends StatefulWidget {
  const AmbientLoadingField({
    super.key,
    required this.semanticsLabel,
    this.footer,
  });

  final String semanticsLabel;
  final Widget? footer;

  @override
  State<AmbientLoadingField> createState() => _AmbientLoadingFieldState();
}

class _AmbientLoadingFieldState extends State<AmbientLoadingField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncMotion();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _motion
        ..stop()
        ..value = 0.24;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      liveRegion: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _AmbientLoadingPainter(
                motion: _motion,
                background: colors.surfaceContainerLowest,
                purple: DesignTokens.colorListIconPurple,
                mint: ConnectTokens.accent(context, ConnectTokens.mint),
                coral: ConnectTokens.accent(context, ConnectTokens.coral),
                blue: ConnectTokens.accent(context, ConnectTokens.blue),
                amber: ConnectTokens.accent(context, ConnectTokens.amber),
                dark: dark,
              ),
            ),
          ),
          if (widget.footer != null)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingMd),
                  child: widget.footer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AmbientLoadingPainter extends CustomPainter {
  _AmbientLoadingPainter({
    required this.motion,
    required this.background,
    required this.purple,
    required this.mint,
    required this.coral,
    required this.blue,
    required this.amber,
    required this.dark,
  }) : super(repaint: motion);

  final Animation<double> motion;
  final Color background;
  final Color purple;
  final Color mint;
  final Color coral;
  final Color blue;
  final Color amber;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = background);
    final time = motion.value * math.pi * 2;
    final base = dark ? 0.18 : 0.25;
    _wash(
      canvas,
      rect,
      center: Offset(
        size.width * (0.18 + 0.08 * math.sin(time * 0.28)),
        size.height * (0.12 + 0.05 * math.cos(time * 0.21)),
      ),
      radius: size.longestSide * (0.54 + 0.04 * math.sin(time * 0.18)),
      color: coral,
      alpha: base * (dark ? 0.42 : 0.36),
    );
    _wash(
      canvas,
      rect,
      center: Offset(
        size.width * (0.82 + 0.07 * math.cos(time * 0.24)),
        size.height * (0.23 + 0.06 * math.sin(time * 0.19)),
      ),
      radius: size.longestSide * (0.6 + 0.05 * math.cos(time * 0.2)),
      color: purple,
      alpha: base * (dark ? 0.36 : 0.28),
    );
    _wash(
      canvas,
      rect,
      center: Offset(
        size.width * (0.2 + 0.08 * math.cos(time * 0.22)),
        size.height * (0.78 + 0.05 * math.sin(time * 0.25)),
      ),
      radius: size.longestSide * (0.57 + 0.04 * math.sin(time * 0.17)),
      color: blue,
      alpha: base * (dark ? 0.48 : 0.4),
    );
    _wash(
      canvas,
      rect,
      center: Offset(
        size.width * (0.78 + 0.08 * math.sin(time * 0.23)),
        size.height * (0.82 + 0.06 * math.cos(time * 0.2)),
      ),
      radius: size.longestSide * (0.55 + 0.05 * math.cos(time * 0.16)),
      color: mint,
      alpha: base * (dark ? 0.34 : 0.28),
    );
    _wash(
      canvas,
      rect,
      center: Offset(
        size.width * (0.44 + 0.08 * math.sin(time * 0.2)),
        size.height * (0.48 + 0.06 * math.cos(time * 0.17)),
      ),
      radius: size.shortestSide * (0.52 + 0.05 * math.sin(time * 0.14)),
      color: amber,
      alpha: base * 0.14,
    );

    final cluster = Offset(size.width * 0.44, size.height * 0.42);
    final orbit = math.min(size.width * 0.15, 66.0);
    _particle(
      canvas,
      cluster +
          Offset(
            math.cos(time + math.pi * 0.25) * orbit * 0.82,
            math.sin(time * 0.82 + math.pi * 0.25) * orbit * 0.62,
          ),
      radius: math.max(8.0, orbit * 0.135),
      color: purple,
      phase: time,
    );
    _particle(
      canvas,
      cluster +
          Offset(
            math.cos(time * 0.72 + math.pi * 1.02) * orbit,
            math.sin(time * 0.72 + math.pi * 1.02) * orbit * 0.76,
          ),
      radius: math.max(10.0, orbit * 0.17),
      color: mint,
      phase: time + 1.7,
    );
    _particle(
      canvas,
      cluster +
          Offset(
            math.cos(time * 0.9 - math.pi * 0.22) * orbit * 0.58,
            math.sin(time * 0.9 - math.pi * 0.22) * orbit * 0.9,
          ),
      radius: math.max(9.0, orbit * 0.15),
      color: coral,
      phase: time + 3.1,
    );
  }

  void _wash(
    Canvas canvas,
    Rect bounds, {
    required Offset center,
    required double radius,
    required Color color,
    required double alpha,
  }) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.42),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.48, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawRect(bounds, paint);
  }

  void _particle(
    Canvas canvas,
    Offset center, {
    required double radius,
    required Color color,
    required double phase,
  }) {
    final pulse = 0.9 + math.sin(phase * 1.3) * 0.1;
    final glow = Paint()
      ..color = color.withValues(alpha: dark ? 0.16 : 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(center, radius * 3.35 * pulse, glow);
    final core = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: dark ? 0.42 : 0.62),
          color.withValues(alpha: dark ? 0.68 : 0.78),
          color.withValues(alpha: dark ? 0.32 : 0.46),
        ],
        stops: const [0, 0.32, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius * pulse));
    canvas.drawCircle(center, radius * pulse, core);
  }

  @override
  bool shouldRepaint(_AmbientLoadingPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.purple != purple ||
      oldDelegate.mint != mint ||
      oldDelegate.coral != coral ||
      oldDelegate.blue != blue ||
      oldDelegate.amber != amber ||
      oldDelegate.dark != dark;
}
