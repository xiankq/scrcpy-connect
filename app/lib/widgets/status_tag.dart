import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';

enum StatusTagTone { neutral, success, warning, error }

/// 状态标签上下内距（Ardot 37:652：上下 2）。
const _tagVerticalPadding = DesignTokens.spacingXxs;

/// 状态标签（Ardot 37:661）：圆角 8，`caption-emphasis`，按语气使用对应容器色。
class StatusTag extends StatelessWidget {
  const StatusTag(this.label, {super.key, this.tone = StatusTagTone.neutral});

  final String label;
  final StatusTagTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (fill, foreground) = switch (tone) {
      StatusTagTone.neutral => (colors.block, colors.textSecondary),
      StatusTagTone.success => (
        colors.successContainer,
        colors.onSuccessContainer,
      ),
      StatusTagTone.warning => (
        colors.warningContainer,
        colors.onWarningContainer,
      ),
      StatusTagTone.error => (colors.errorContainer, colors.onErrorContainer),
    };
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: fill,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.componentTagRounded),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.componentTagPadding,
          vertical: _tagVerticalPadding,
        ),
        child: Text(
          label,
          style: AppTypography.of(context).captionEmphasis
              .copyWith(color: foreground),
        ),
      ),
    );
  }
}
