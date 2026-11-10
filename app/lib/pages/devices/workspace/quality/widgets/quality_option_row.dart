import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class QualityOptionRow extends StatelessWidget {
  const QualityOptionRow({
    super.key,
    required this.title,
    required this.icon,
    required this.currentValue,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final String currentValue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context).textTheme;
      final titleStyle = theme.bodyLarge!;
      final valueStyle = theme.bodySmall!;
      double textWidth(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      final stacked =
          textWidth(title, titleStyle) + textWidth(currentValue, valueStyle) >
          constraints.maxWidth -
              DesignTokens.spacingMd * 2 -
              DesignTokens.componentListIconSize -
              DesignTokens.spacingSm -
              DesignTokens.componentIconSmallSize -
              DesignTokens.spacingSm * 2;
      const chevron = Icon(
        LucideIcons.chevronRight,
        size: DesignTokens.componentIconSmallSize,
      );
      return ListTile(
        minTileHeight: DesignTokens.componentRowHeight,
        minLeadingWidth: DesignTokens.componentListIconSize,
        leading: ListIconBadge(
          icon: icon,
          backgroundColor: functionalIconColor(icon),
        ),
        title: Text(title, style: titleStyle),
        subtitle: stacked ? Text(currentValue, style: valueStyle) : null,
        trailing: stacked
            ? chevron
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(currentValue, style: valueStyle),
                  const SizedBox(width: DesignTokens.spacingSm),
                  chevron,
                ],
              ),
        onTap: onTap,
      );
    },
  );
}
