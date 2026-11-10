import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

class StateNote extends StatelessWidget {
  const StateNote(
    this.message, {
    super.key,
    this.icon = LucideIcons.info,
    this.color,
  });
  final String message;
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: DesignTokens.componentIconActionSize,
          color: color ?? Theme.of(context).textTheme.bodySmall?.color,
        ),
        const SizedBox(width: DesignTokens.spacingXs),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}
