import 'package:flutter/material.dart';

import 'design_tokens.g.dart';

/// A compact functional leading icon for a content list row.
class ListIconBadge extends StatelessWidget {
  const ListIconBadge({
    super.key,
    required this.icon,
    required this.backgroundColor,
  });

  final IconData icon;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: DesignTokens.componentListIconSize,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignTokens.componentListIconRounded,
        ),
      ),
      child: Icon(
        icon,
        size: DesignTokens.componentListIconGlyphSize,
        color: DesignTokens.componentListIconTextColor,
      ),
    ),
  );
}
