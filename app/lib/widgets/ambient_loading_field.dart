import 'dart:math' as math;

import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

/// 等待任务的共享背景；异常冻结当前帧，重试从原相位继续。
class AmbientLoadingField extends StatefulWidget {
  const AmbientLoadingField({
    super.key,
    required this.semanticsLabel,
    this.animating = true,
    this.showParticles = true,
    this.overlay,
    this.footer,
  });

  final String semanticsLabel;
  final bool animating;
  final bool showParticles;
  final Widget? overlay;
  final Widget? footer;

  @override
  State<AmbientLoadingField> createState() => _AmbientLoadingFieldState();
}

class _AmbientLoadingFieldState extends State<AmbientLoadingField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _motion = _LoadingMotion();
  late final Ticker _ticker = createTicker(_advance);
  Duration _lastTick = Duration.zero;
  bool _reduceMotion = false;
  bool _routeVisible = true;
  bool _tickerEnabled = true;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.reduceMotionOf(context);
    _routeVisible = ModalRoute.isCurrentOf(context) != false;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncMotion();
  }

  @override
  void didUpdateWidget(AmbientLoadingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _advance(Duration elapsed) {
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    _motion.advance(delta, particles: widget.showParticles);
  }

  void _syncMotion() {
    final active =
        widget.animating &&
        !_reduceMotion &&
        _routeVisible &&
        _tickerEnabled &&
        _foreground;
    if (active && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!active && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
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
              showParticles: widget.showParticles,
              background: Theme.of(context).brightness == Brightness.dark
                  ? DesignTokens.colorCanvasDark
                  : DesignTokens.colorCanvas,
            ),
          ),
        ),
        if (widget.overlay != null) Positioned.fill(child: widget.overlay!),
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

class _LoadingMotion extends ChangeNotifier {
  double backgroundSeconds = 0;
  double particleSeconds = 0;

  void advance(Duration delta, {required bool particles}) {
    if (delta <= Duration.zero) return;
    final seconds = delta.inMicroseconds / Duration.microsecondsPerSecond;
    backgroundSeconds += seconds;
    if (particles) particleSeconds += seconds;
    notifyListeners();
  }
}

class _AmbientLoadingPainter extends CustomPainter {
  _AmbientLoadingPainter({
    required this.motion,
    required this.background,
    required this.showParticles,
  }) : super(repaint: motion);

  final _LoadingMotion motion;
  final Color background;
  final bool showParticles;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = background);
    _layer(
      canvas,
      size,
      seconds: 16,
      phase: 0,
      paint: (bounds) {
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                DesignTokens.colorLoadingWarm,
                DesignTokens.colorTransparent,
                DesignTokens.colorLoadingBlue,
              ],
              stops: [0, 0.45, 1],
            ).createShader(bounds),
        );
      },
    );
    _layer(
      canvas,
      size,
      seconds: 20,
      phase: 0.7,
      paint: (bounds) {
        _radial(
          canvas,
          bounds,
          center: bounds.bottomRight,
          radii: Size(bounds.width * 1.1, bounds.height * 0.7),
          color: DesignTokens.colorLoadingMint,
        );
      },
    );
    _layer(
      canvas,
      size,
      seconds: 18,
      phase: 1.9,
      paint: (bounds) {
        _radial(
          canvas,
          bounds,
          center: Offset(bounds.left, bounds.top + bounds.height * 0.45),
          radii: Size(bounds.width * 0.9, bounds.height * 0.45),
          color: DesignTokens.colorLoadingViolet,
        );
      },
    );
    if (showParticles) {
      final center = Offset(size.width * 0.5, size.height * 0.453);
      final widthScale = math.min(
        1.0,
        size.width / DesignTokens.componentPhoneWidth,
      );
      for (final orb in const [
        (32.0, -35.0, 2.8, DesignTokens.colorListIconMint),
        (28.0, 85.0, 3.4, DesignTokens.colorListIconCoral),
        (22.0, 205.0, 3.9, DesignTokens.colorListIconPurple),
      ]) {
        final phase = orb.$2 * math.pi / 180;
        final angle = motion.particleSeconds * 2 * math.pi / 4.2 + phase;
        final scale =
            1.15 +
            0.45 *
                math.sin(motion.particleSeconds * 2 * math.pi / orb.$3 + phase);
        canvas.drawCircle(
          center +
              Offset(
                math.cos(angle) * 52 * widthScale,
                math.sin(angle) * 38 * widthScale,
              ),
          orb.$1 / 2 * scale,
          Paint()
            ..color = orb.$4.withValues(
              alpha: DesignTokens.componentLoadingOrbOpacity,
            ),
        );
      }
    }
    canvas.restore();
  }

  void _layer(
    Canvas canvas,
    Size size, {
    required double seconds,
    required double phase,
    required void Function(Rect) paint,
  }) {
    final angle = motion.backgroundSeconds * 2 * math.pi / seconds;
    final scale = 1.06 - 0.06 * math.cos(angle);
    final bounds = Rect.fromLTRB(
      -size.width * 0.2,
      -size.height * 0.2,
      size.width * 1.2,
      size.height * 1.2,
    );
    canvas.save();
    canvas.translate(
      size.width / 2 + bounds.width * 0.08 * math.sin(angle + phase),
      size.height / 2 + bounds.height * 0.08 * math.sin(angle + phase * 1.7),
    );
    canvas.scale(scale);
    canvas.translate(-size.width / 2, -size.height / 2);
    paint(bounds);
    canvas.restore();
  }

  void _radial(
    Canvas canvas,
    Rect bounds, {
    required Offset center,
    required Size radii,
    required Color color,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(radii.width, radii.height);
    canvas.drawRect(
      Rect.fromLTRB(
        (bounds.left - center.dx) / radii.width,
        (bounds.top - center.dy) / radii.height,
        (bounds.right - center.dx) / radii.width,
        (bounds.bottom - center.dy) / radii.height,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [color, DesignTokens.colorTransparent],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AmbientLoadingPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.showParticles != showParticles ||
      oldDelegate.motion != motion;
}
