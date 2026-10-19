import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:design_system/design_system.dart';

class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.title,
    this.contentPadding,
  });
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget title;
  final EdgeInsetsGeometry? contentPadding;
  @override
  Widget build(BuildContext context) => Semantics(
    checked: value == groupValue,
    inMutuallyExclusiveGroup: true,
    child: ListTile(
      contentPadding: contentPadding,
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
