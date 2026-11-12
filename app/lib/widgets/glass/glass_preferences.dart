import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

/// 将应用偏好接入官方辅助功能作用域。
class GlassPreferences extends StatelessWidget {
  const GlassPreferences({
    super.key,
    required this.reduceTransparency,
    required this.child,
  });
  final bool reduceTransparency;
  final Widget child;
  static bool reduced(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_GlassPreferences>()
          ?.reduceTransparency ??
      false;
  @override
  Widget build(BuildContext context) => _GlassPreferences(
    reduceTransparency: reduceTransparency,
    child: liquid.GlassAccessibilityScope(
      reduceTransparency:
          reduceTransparency ||
          MediaQuery.highContrastOf(context) ||
          liquid.GlassAccessibilityData.of(context).reduceTransparency,
      child: child,
    ),
  );
}

class _GlassPreferences extends InheritedWidget {
  const _GlassPreferences({
    required this.reduceTransparency,
    required super.child,
  });
  final bool reduceTransparency;
  @override
  bool updateShouldNotify(_GlassPreferences oldWidget) =>
      reduceTransparency != oldWidget.reduceTransparency;
}

bool opaqueGlass(BuildContext context, {bool solid = false}) =>
    solid ||
    GlassPreferences.reduced(context) ||
    liquid.GlassAccessibilityData.of(context).reduceTransparency ||
    MediaQuery.highContrastOf(context);
