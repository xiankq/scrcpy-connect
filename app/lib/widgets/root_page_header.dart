import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Root destinations lead with a display title; short viewports stay compact.
class RootPageHeader extends StatelessWidget {
  const RootPageHeader({
    super.key,
    required this.title,
    this.action,
    this.compact = false,
  });
  final String title;
  final Widget? action;
  final bool compact;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(
      minHeight: DesignTokens.componentPageHeaderHeight,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: compact
                ? Theme.of(context).textTheme.titleLarge
                : Theme.of(context).textTheme.displaySmall,
          ),
        ),
        ?action,
      ],
    ),
  );
}
