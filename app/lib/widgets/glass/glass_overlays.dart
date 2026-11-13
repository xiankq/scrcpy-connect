import 'package:material_ui/material_ui.dart';

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
    this.visualDensity,
    this.style,
    this.alignment = Alignment.center,
    this.disabledColor,
    this.focusNode,
    this.autofocus = false,
    this.enableFeedback,
    this.isSelected,
    this.selectedIcon,
    this.onLongPress,
    this.mouseCursor,
  });
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double? iconSize;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final VisualDensity? visualDensity;
  final ButtonStyle? style;
  final AlignmentGeometry alignment;
  final Color? disabledColor;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool? enableFeedback;
  final bool? isSelected;
  final Widget? selectedIcon;
  final VoidCallback? onLongPress;
  final MouseCursor? mouseCursor;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      icon: icon,
      onPressed: onPressed,
      iconSize: iconSize,
      color: color,
      padding: padding,
      constraints: constraints,
      visualDensity: visualDensity,
      style: style,
      alignment: alignment,
      disabledColor: disabledColor,
      focusNode: focusNode,
      autofocus: autofocus,
      enableFeedback: enableFeedback,
      isSelected: isSelected,
      selectedIcon: selectedIcon,
      onLongPress: onLongPress,
      mouseCursor: mouseCursor,
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
