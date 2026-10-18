import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Root tabs use the same compact title and header rhythm as pushed pages.
class RootPageHeader extends StatelessWidget {
  const RootPageHeader({super.key, required this.title, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(
      minHeight: DesignTokens.componentPageHeaderHeight,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}
