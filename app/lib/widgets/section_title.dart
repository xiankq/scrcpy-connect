import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(
            top: DesignTokens.spacingSectionTitle,
            bottom: DesignTokens.spacingSm,
          ),
          child: Text(title, style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
      if (action != null)
        Padding(
          // Match the caption's asymmetric whitespace while letting the full
          // action hit area share that space and grow with larger content.
          padding: const EdgeInsets.only(
            top: DesignTokens.spacingSectionTitle - DesignTokens.spacingSm,
          ),
          child: action,
        ),
    ],
  );
}
