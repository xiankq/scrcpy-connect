import 'package:flutter/material.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// 填充式选择字段在同一表面呈现标签和所选值。
class ConnectSelectionField<T> extends StatelessWidget {
  const ConnectSelectionField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
    this.readOnly = false,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Widget icon;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      constraints: const BoxConstraints(
        minHeight: DesignTokens.componentSelectionFieldHeight,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.componentSelectionFieldPadding,
        vertical: DesignTokens.componentSelectionFieldVerticalPadding,
      ),
      // InputDecorator 将浮动标签缩放为 0.75；可见字号保持 caption 尺寸，不继承 Material 默认值。
      floatingLabelStyle: Theme.of(context).textTheme.bodySmall
          ?.copyWith(fontSize: DesignTokens.typographyCaptionFontSize / 0.75),
      border: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(
          DesignTokens.componentSelectionFieldRounded,
        ),
        borderSide: BorderSide.none,
      ),
    );
    if (readOnly) {
      final selected = items.where((item) => item.value == value).firstOrNull;
      return Semantics(
        enabled: false,
        child: InputDecorator(
          decoration: decoration.copyWith(enabled: false),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyLarge!
                .copyWith(color: Theme.of(context).disabledColor),
            child: selected?.child ?? const SizedBox.shrink(),
          ),
        ),
      );
    }
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      // 菜单选项独立于紧凑的已选值字段扩展。
      itemHeight: null,
      style: Theme.of(context).textTheme.bodyLarge,
      icon: icon,
      decoration: decoration,
      items: items,
      onChanged: onChanged,
    );
  }
}

/// 紧凑视觉尺寸与独立的无障碍触摸目标。
class ConnectSwitch extends StatelessWidget {
  const ConnectSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final toggle = onChanged == null ? null : () => onChanged!(!value);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : kThemeAnimationDuration;
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      onTap: toggle,
      child: SizedBox.square(
        dimension: DesignTokens.componentIconButtonSize,
        child: InkWell(
          onTap: toggle,
          excludeFromSemantics: true,
          customBorder: const StadiumBorder(),
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              width: DesignTokens.componentSwitchTrackWidth,
              height: DesignTokens.componentSwitchTrackHeight,
              padding: const EdgeInsets.all(
                (DesignTokens.componentSwitchTrackHeight -
                        DesignTokens.componentSwitchThumbSize) /
                    2,
              ),
              decoration: BoxDecoration(
                color: onChanged == null
                    ? colors.outlineVariant
                    : value
                    ? colors.primary
                    : colors.outlineVariant,
                borderRadius: BorderRadius.circular(
                  DesignTokens.componentSwitchTrackRounded,
                ),
              ),
              child: AnimatedAlign(
                duration: duration,
                alignment: value
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: SizedBox.square(
                  dimension: DesignTokens.componentSwitchThumbSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: value && onChanged != null
                          ? colors.onPrimary
                          : colors.brightness == Brightness.dark
                          ? colors.onSurface
                          : colors.surface,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
