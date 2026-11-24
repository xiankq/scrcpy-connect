import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.value,
    required this.selected,
    required this.onChanged,
    required this.title,
    this.leading,
    this.contentPadding,
    this.disabledReason,
  });
  final T value;
  final bool selected;
  final ValueChanged<T>? onChanged;
  final Widget title;
  final Widget? leading;
  final EdgeInsetsGeometry? contentPadding;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: ListTile(
        contentPadding:
            contentPadding ??
            const EdgeInsets.symmetric(
              horizontal: DesignTokens.componentPickerOptionPadding,
            ),
        minTileHeight: DesignTokens.componentPickerOptionHeight,
        minVerticalPadding: DesignTokens.spacingXxs,
        minLeadingWidth: DesignTokens.componentPickerOptionSize,
        leading: leading,
        selected: selected,
        selectedTileColor: theme.brightness == Brightness.dark
            ? DesignTokens.colorGlassSelectedDark
            : DesignTokens.colorGlassSelected,
        selectedColor: theme.colorScheme.onSurface,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.componentPickerOptionRounded),
          ),
        ),
        titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
          color: onChanged != null
              ? theme.colorScheme.onSurface
              : theme.disabledColor,
        ),
        enabled: onChanged != null,
        trailing: SizedBox.square(
          dimension: DesignTokens.componentPickerOptionSize,
          child: selected
              ? Icon(
                  LucideIcons.check,
                  color: onChanged != null
                      ? theme.colorScheme.onSurface
                      : theme.disabledColor,
                  size: DesignTokens.componentPickerOptionSize,
                )
              : null,
        ),
        title: title,
        subtitle: disabledReason == null || disabledReason!.isEmpty
            ? null
            : Text(disabledReason!),
        onTap: onChanged == null ? null : () => onChanged!(value),
      ),
    );
  }
}
