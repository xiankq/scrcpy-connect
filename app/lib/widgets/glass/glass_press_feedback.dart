import 'dart:math' as math;
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

/// designs/interaction-motion.md「触点反馈」中玻璃按钮与按钮组的按压参数。
abstract final class GlassPressMetrics {
  /// 按住时最多放大 16 点。
  static const maximumGrowth = DesignTokens.spacingLg;

  /// 放大不超过 25%。
  static const maximumScale = 1.25;

  /// 刚度 311、阻尼比 0.593，带一次轻微回弹。
  static final spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 311,
    ratio: .593,
  );

  /// 拖动时朝手指方向拉伸，最多拉长短边的 7/32。
  static const maximumPull = 7 / 32;

  /// 辉光覆盖约 高/√2。
  static const glowReach = math.sqrt1_2;

  /// 给定尺寸的放大倍率：`1 + min(16/最长边, 0.25)`。
  static double scaleFor(Size size) {
    final longest = size.longestSide;
    if (longest <= 0) return 1;
    return 1 + math.min(maximumGrowth / longest, maximumScale - 1);
  }
}

/// 为应用持有手势识别器的玻璃控件提供指针反馈：向外膨胀、朝手指拉伸、手指处 16% 白色辉光。
/// 任何按钮按下都不缩小。只观察指针，点击、拖动和取消仍由 child 负责。
class GlassPressFeedback extends StatefulWidget {
  const GlassPressFeedback({
    super.key,
    required this.child,
    this.radius = DesignTokens.roundedFull,
    this.enabled = true,
  });
  final Widget child;
  final double radius;
  final bool enabled;

  @override
  State<GlassPressFeedback> createState() => _GlassPressFeedbackState();
}

class _GlassPressFeedbackState extends State<GlassPressFeedback>
    with WidgetsBindingObserver {
  final _contentKey = GlobalKey();
  final Map<int, Offset> _pointers = {};
  Offset _touch = Offset.zero;
  Size _size = Size.zero;
  int _lifecycleEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(GlassPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _pointers.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _pointers.isNotEmpty) {
      setState(() {
        _pointers.clear();
        _lifecycleEpoch++;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pointers.clear();
    super.dispose();
  }

  void _track(PointerEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return;
    final position = box.globalToLocal(event.position);
    setState(() {
      _pointers[event.pointer] = position;
      _size = box.size;
      _touch = Offset(
        (position.dx / box.size.width * 2 - 1).clamp(-1, 1),
        (position.dy / box.size.height * 2 - 1).clamp(-1, 1),
      );
    });
  }

  void _release(PointerEvent event) {
    if (_pointers.containsKey(event.pointer)) {
      setState(() => _pointers.remove(event.pointer));
    }
  }

  @override
  Widget build(BuildContext context) {
    final opaque = opaqueGlass(context);
    final fallback = opaque || !ImageFilter.isShaderFilterSupported;
    final pressed = widget.enabled && _pointers.isNotEmpty;
    // 降低透明度只换材质，膨胀保留；减少动态时只保留按压状态。
    final reducedMotion = liquid.GlassAccessibilityData.of(context)
        .reduceMotion;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(widget.radius),
    );
    Widget content = KeyedSubtree(key: _contentKey, child: widget.child);
    if (fallback) {
      content = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: shape,
          color: pressed
              ? AppColors.of(context).pressed
              : AppColors.of(context).pressed.withAlpha(0),
        ),
        child: content,
      );
    } else {
      content = liquid.GlassGlow(
        key: ValueKey(_lifecycleEpoch),
        enabled: widget.enabled,
        glowColor: DesignTokens.colorGlassRim.withValues(
          alpha: DesignTokens.componentGlassInteractionGlowIntensity,
        ),
        glowRadius: GlassPressMetrics.glowReach,
        clipper: ShapeBorderClipper(shape: shape),
        child: content,
      );
    }
    final spring = GlassPressMetrics.spring;
    final growth = reducedMotion ? 0.0 : GlassPressMetrics.scaleFor(_size) - 1;
    final pull = reducedMotion || _size.isEmpty
        ? 0.0
        : GlassPressMetrics.maximumPull *
              _size.shortestSide /
              _size.longestSide *
              DesignTokens.componentGlassInteractionStretch;
    // 只观察指针；child 识别器仍持有点击、拖动和手势竞技场取消。
    // 变换不能扩大布局或命中范围。
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.enabled ? _track : null,
      onPointerMove: widget.enabled
          ? (event) {
              if (_pointers.containsKey(event.pointer)) _track(event);
            }
          : null,
      onPointerUp: _release,
      onPointerCancel: _release,
      child: liquid.SpringBuilder(
        value: pressed && !reducedMotion ? 1 : 0,
        spring: spring,
        builder: (context, press, child) => liquid.SpringBuilder(
          value: pressed && !reducedMotion ? _touch.dx : 0,
          spring: spring,
          builder: (context, x, child) => liquid.SpringBuilder(
            value: pressed && !reducedMotion ? _touch.dy : 0,
            spring: spring,
            builder: (context, y, child) => Transform(
              alignment: Alignment(
                -x.clamp(-1, 1).toDouble(),
                -y.clamp(-1, 1).toDouble(),
              ),
              transformHitTests: false,
              transform: Matrix4.diagonal3Values(
                1 + growth * press + pull * (x.abs() - y.abs()),
                1 + growth * press + pull * (y.abs() - x.abs()),
                1,
              ),
              child: child,
            ),
            child: child,
          ),
          child: child,
        ),
        child: content,
      ),
    );
  }
}
