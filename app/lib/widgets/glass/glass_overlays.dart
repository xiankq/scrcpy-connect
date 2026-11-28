import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 玻璃操作组中的图标动作；表面、命中几何、焦点和手势识别器仍由 Material 图标按钮负责。
class GlassActionIcon extends StatelessWidget {
  const GlassActionIcon({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconSize,
    this.color,
    this.padding,
    this.constraints,
    this.style,
    this.focusNode,
  });
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double? iconSize;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final ButtonStyle? style;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      icon: icon,
      onPressed: onPressed,
      iconSize: iconSize,
      color: color ?? AppColors.of(context).text,
      padding: padding,
      constraints: constraints,
      style: style,
      focusNode: focusNode,
    );
    final label = tooltip;
    return label == null
        ? button
        : Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: MergeSemantics(
              child: Semantics(label: label, child: button),
            ),
          );
  }
}
