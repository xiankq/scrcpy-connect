import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.contentPadding,
  });
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  @override
  Widget build(BuildContext context) => Semantics(
    checked: value == groupValue,
    inMutuallyExclusiveGroup: true,
    child: ListTile(
      contentPadding: contentPadding,
      enabled: onChanged != null,
      leading: Icon(
        value == groupValue ? LucideIcons.circleDot : LucideIcons.circle,
        color: onChanged == null
            ? Theme.of(context).disabledColor
            : Theme.of(context).colorScheme.primary,
        size: 22,
      ),
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(value),
    ),
  );
}
