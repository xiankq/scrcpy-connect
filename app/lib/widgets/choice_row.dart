import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.title,
    this.leading,
    this.contentPadding,
  });
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget title;
  final Widget? leading;
  final EdgeInsetsGeometry? contentPadding;
  @override
  Widget build(BuildContext context) => Semantics(
    checked: value == groupValue,
    inMutuallyExclusiveGroup: true,
    child: ListTile(
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
      minLeadingWidth: DesignTokens.componentListIconSize,
      leading: leading,
      titleTextStyle: Theme.of(context).textTheme.bodyLarge,
      enabled: onChanged != null,
      trailing: value == groupValue
          ? Icon(
              LucideIcons.check,
              color: Theme.of(context).colorScheme.primary,
              size: DesignTokens.componentIconSize,
            )
          : null,
      title: title,

      onTap: onChanged == null ? null : () => onChanged!(value),
    ),
  );
}
