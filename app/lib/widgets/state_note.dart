import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 说明图形与 footnote 行高（18）对齐的大小。
const _noteGlyphSize = DesignTokens.componentChevronSize;

/// 就地状态说明：`footnote` + `text-secondary`，起始一个状态图形。
///
/// 状态文字沿用次要色，着色交给图形（design.md「文字与状态」）；[color] 只作用于图形。
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
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: _noteGlyphSize,
            color: color ?? colors.textSecondary,
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.of(context).footnote
                  .copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
