import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

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
        LucideIcons.chevronDown,
        size: DesignTokens.componentIconSmallSize,
      );
      return ListTile(
        minTileHeight: DesignTokens.componentRowHeight,
        minLeadingWidth: DesignTokens.componentListIconSize,
        leading: ListIconBadge(
          icon: icon,
          backgroundColor: DesignTokens.colorListIconSlate,
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
