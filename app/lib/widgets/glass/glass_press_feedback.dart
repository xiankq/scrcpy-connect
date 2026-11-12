import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

/// 为应用持有手势识别器的控件提供指针反馈。
/// 只观察指针，点击、拖动和取消仍由 child 负责。
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
    final fallback =
        opaqueGlass(context) || !ImageFilter.isShaderFilterSupported;
    final pressed = widget.enabled && _pointers.isNotEmpty;
    final reducedMotion = liquid.GlassAccessibilityData.of(context)
        .reduceMotion;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(widget.radius),
    );
    Widget content = KeyedSubtree(key: _contentKey, child: widget.child);
    if (fallback) {
      content = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: shape,
          color: pressed
              ? Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: DesignTokens.componentControlFeedbackOpacity,
                )
              : DesignTokens.colorTransparent,
        ),
        child: content,
      );
    } else {
      content = liquid.GlassGlow(
        key: ValueKey(_lifecycleEpoch),
        enabled: widget.enabled,
        clipper: ShapeBorderClipper(shape: shape),
        child: content,
      );
    }
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
        spring: liquid.GlassSpring.interactive(),
        builder: (context, press, child) => liquid.SpringBuilder(
          value: pressed && !reducedMotion ? _touch.dx : 0,
          spring: liquid.GlassSpring.interactive(),
          builder: (context, x, child) => liquid.SpringBuilder(
            value: pressed && !reducedMotion ? _touch.dy : 0,
            spring: liquid.GlassSpring.interactive(),
            builder: (context, y, child) {
              final growth = reducedMotion
                  ? 0.0
                  : DesignTokens.componentGlassInteractionScale - 1;
              final stretch =
                  growth * DesignTokens.componentGlassInteractionStretch;
              return Transform(
                alignment: Alignment(
                  -x.clamp(-1, 1).toDouble(),
                  -y.clamp(-1, 1).toDouble(),
                ),
                transformHitTests: false,
                transform: Matrix4.diagonal3Values(
                  1 + growth * press + stretch * (x.abs() - y.abs()),
                  1 + growth * press + stretch * (y.abs() - x.abs()),
                  1,
                ),
                child: child,
              );
            },
            child: child,
          ),
          child: child,
        ),
        child: content,
      ),
    );
  }
}
