import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: DesignTokens.spacingSectionTitle,
      bottom: DesignTokens.spacingSm,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.bodySmall),
        ),
        ?action,
      ],
    ),
  );
}
