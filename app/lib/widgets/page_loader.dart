import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 整页加载一轮的时长，见 interaction-motion「等待与状态切换」。
const pageLoaderCycle = Duration(milliseconds: 1200);

/// 停止时形状降到的不透明度（Ardot C8 等待态，与禁用前景同为 38%）。
const _stoppedOpacity = .38;

/// 整页加载：三枚形状依次跳起，等待超过 400 毫秒才出现，下方为阶段文字。
///
/// [stopped] 时形状停止并降到 38%，原位显示 [message] 与 [action]（通常为「重试」）。
class PageLoader extends HookWidget {
  const PageLoader({
    super.key,
    this.message,
    this.detail,
    this.stopped = false,
    this.action,
    this.semanticsLabel = '正在读取',
  });

  final String? message;
  final String? detail;
  final bool stopped;
  final Widget? action;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final elapsed = useState(false);
    useEffect(() {
      final timer = Timer(pageLoaderDelay, () => elapsed.value = true);
      return timer.cancel;
    }, const []);
    final shown = stopped || elapsed.value;
    final lifecycle = useAppLifecycleState();
    final running =
        shown &&
        !stopped &&
        !reduceMotionOf(context) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        TickerMode.valuesOf(context).enabled;
    final phase = useAnimationController(duration: pageLoaderCycle);
    useEffect(() {
      if (running) {
        phase.repeat();
      } else {
        phase.stop();
      }
      return null;
    }, [phase, running]);
    if (!shown) {
      return Semantics(label: semanticsLabel, liveRegion: true);
    }
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: message == null ? semanticsLabel : null,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DesignTokens.spacingXxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.componentEmptyStateWidth,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: LoaderShapes(progress: phase, stopped: stopped),
                ),
                if (message != null) ...[
                  const SizedBox(height: DesignTokens.spacingLg),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: type.subheadline.copyWith(
                      color: stopped ? colors.text : colors.textSecondary,
                    ),
                  ),
                ],
                if (detail != null) ...[
                  const SizedBox(height: DesignTokens.spacingXs),
                  Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: type.footnote.copyWith(color: colors.textSecondary),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: DesignTokens.spacingXxl),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 三枚 `primary` 形状（圆、12 波浪圆、超椭圆）与 `primary-container` 地面。
///
/// [progress] 为一轮内的相位 0–1；外部可用自有时钟驱动，以便暂停后从原相位继续。
class LoaderShapes extends StatelessWidget {
  const LoaderShapes({super.key, required this.progress, this.stopped = false});

  /// Ardot「整页加载」37:805 的画布。
  static const size = Size(160, 96);

  final ValueListenable<double> progress;
  final bool stopped;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        size: size,
        painter: LoaderShapesPainter(
          progress: progress,
          color: colors.primary,
          ground: colors.primaryContainer,
          opacity: stopped ? _stoppedOpacity : 1,
          hop: !stopped && !reduceMotionOf(context),
        ),
      ),
    );
  }
}

class LoaderShapesPainter extends CustomPainter {
  LoaderShapesPainter({
    required this.progress,
    required this.color,
    required this.ground,
    this.opacity = 1,
    this.hop = true,
  }) : super(repaint: progress);

  // 几何取自 Ardot 37:805 与 design.md「空态、加载与进度」：形状 20、间距 52、
  // 跳起 30、地面 44×6；跳起节奏沿用 Prism ActivityIndicator.page。
  static const _shapeSize = 20.0;
  static const _spacing = 52.0;
  static const _restY = 56.0;
  static const _hop = 30.0;
  static const _groundY = 87.0;
  static const _groundSize = Size(44, 6);
  static const _hopShare = .25;
  static const _stagger = 1 / 6;
  static const _hopCurve = Cubic(.3, 0, .3, 1);

  static final _shapes = [
    _outline((_) => 1),
    _outline((angle) => 1 + .055 * math.cos(12 * angle)),
    _outline((angle) {
      final c = math.pow(math.cos(angle).abs(), 4.5);
      final s = math.pow(math.sin(angle).abs(), 4.5);
      return .92 / math.pow(c + s, 1 / 4.5);
    }),
  ];

  static Path _outline(double Function(double) radius) {
    const points = 96;
    final path = Path();
    for (var i = 0; i < points; i++) {
      final angle = i / points * 2 * math.pi;
      final point = Offset.fromDirection(angle, radius(angle));
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  final ValueListenable<double> progress;
  final Color color, ground;
  final double opacity;
  final bool hop;

  double _lift(double phase) {
    if (phase >= _hopShare * 2) return 0;
    return phase < _hopShare
        ? _hopCurve.transform(phase / _hopShare)
        : 1 - _hopCurve.transform(phase / _hopShare - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(
      math.min(size.width / LoaderShapes.size.width, 1),
      math.min(size.height / LoaderShapes.size.height, 1),
    );
    final center = LoaderShapes.size.width / 2;
    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center, _groundY),
          width: _groundSize.width,
          height: _groundSize.height,
        ),
        Radius.circular(_groundSize.height / 2),
      ),
      Paint()..color = ground.withValues(alpha: ground.a * opacity),
    );
    final solid = Paint()..color = color.withValues(alpha: color.a * opacity);
    final t = progress.value;
    for (var i = 0; i < _shapes.length; i++) {
      final lift = hop ? _lift((t - i * _stagger) % 1) * _hop : 0.0;
      canvas.save();
      canvas.translate(center + (i - 1) * _spacing, _restY - lift);
      canvas.scale(_shapeSize / 2);
      canvas.drawPath(_shapes[i], solid);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LoaderShapesPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.ground != ground ||
      oldDelegate.opacity != opacity ||
      oldDelegate.hop != hop;
}
