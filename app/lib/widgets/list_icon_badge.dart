import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// 内容列表行的紧凑功能前导图标。
class ListIconBadge extends StatelessWidget {
  const ListIconBadge({
    super.key,
    required this.icon,
    required this.backgroundColor,
    this.compact = false,
  });

  final IconData icon;
  final Color backgroundColor;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: compact
        ? DesignTokens.componentListIconCompactSize
        : DesignTokens.componentListIconSize,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(
          compact
              ? DesignTokens.componentListIconCompactRounded
              : DesignTokens.componentListIconRounded,
        ),
      ),
      child: Icon(
        icon,
        size: compact
            ? DesignTokens.componentListIconGlyphCompactSize
            : DesignTokens.componentListIconGlyphSize,
        color: DesignTokens.componentListIconTextColor,
      ),
    ),
  );
}
