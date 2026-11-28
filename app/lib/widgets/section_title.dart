import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 组头（Ardot 37:683）：卡片外，`headline` + `text-secondary`，内距左右 16、上 24、下 8。
///
/// 根页标题下的第一组传 [first] 省略上 24。[action] 一般为区块尺寸的文字按钮。
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.first = false});
  final String title;
  final Widget? action;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: DesignTokens.componentListHeaderPadding,
        right: action == null
            ? DesignTokens.componentListHeaderPadding
            : DesignTokens.spacingXs,
        top: first ? 0 : DesignTokens.componentListSectionGap,
        bottom: DesignTokens.spacingSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: AppTypography.of(context).headline
                    .copyWith(color: colors.textSecondary),
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: DesignTokens.spacingSm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 组脚（Ardot 37:685）：卡片下方的 `footnote` + `text-secondary` 说明，内距左右 16、上 8。
class SectionFooter extends StatelessWidget {
  const SectionFooter(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      left: DesignTokens.componentListHeaderPadding,
      right: DesignTokens.componentListHeaderPadding,
      top: DesignTokens.spacingSm,
    ),
    child: Text(
      text,
      style: AppTypography.of(context).footnote
          .copyWith(color: AppColors.of(context).textSecondary),
    ),
  );
}
