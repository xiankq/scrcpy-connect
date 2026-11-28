import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 横幅语气：信息用浮层面，成功、警告、错误用对应容器色（design.md「菜单、确认框与抽屉」）。
enum BannerTone {
  info,
  success,
  warning,
  error;

  /// 停留时长，见 interaction-motion「导航与覆盖层」。
  Duration get duration => switch (this) {
    info || success => const Duration(seconds: 3),
    warning => const Duration(seconds: 5),
    error => const Duration(seconds: 6),
  };
}

/// 横幅退出淡出时长（interaction-motion「导航与覆盖层」）。
const bannerExitDuration = Duration(milliseconds: 170);

/// Ardot 横幅 37:796 上下内距与图形尺寸。
const _bannerVerticalPadding = 14.0;
const _bannerGlyphSize = DesignTokens.componentSectionGlyphSize;
const _bannerMaxLines = 3;

/// 横幅：最小高 52、圆角 24 的卡片，起始图形 + `label` 文字，最多 3 行。
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.message,
    this.tone = BannerTone.info,
    this.icon,
    this.action,
  });

  final String message;
  final BannerTone tone;
  final IconData? icon;

  /// 行尾文字按钮（例如「查看电话」）。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (background, foreground, glyphColor, glyph) = switch (tone) {
      BannerTone.info => (
        colors.card,
        colors.text,
        colors.primary,
        LucideIcons.info,
      ),
      BannerTone.success => (
        colors.successContainer,
        colors.onSuccessContainer,
        colors.success,
        LucideIcons.circleCheck,
      ),
      BannerTone.warning => (
        colors.warningContainer,
        colors.onWarningContainer,
        colors.warning,
        LucideIcons.triangleAlert,
      ),
      BannerTone.error => (
        colors.errorContainer,
        colors.onErrorContainer,
        colors.error,
        LucideIcons.circleAlert,
      ),
    };
    return Container(
      constraints: const BoxConstraints(
        minHeight: DesignTokens.componentBannerHeight,
      ),
      padding: EdgeInsetsDirectional.fromSTEB(
        DesignTokens.componentBannerPadding,
        _bannerVerticalPadding,
        action == null
            ? DesignTokens.componentBannerPadding
            : DesignTokens.spacingSm,
        _bannerVerticalPadding,
      ),
      decoration: ShapeDecoration(
        color: background,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.componentBannerRounded),
          ),
        ),
        // 容器色横幅在 Ardot 中不带阴影；信息横幅使用 floating-shadow。
        shadows: tone == BannerTone.info
            ? [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: DesignTokens.componentFloatingShadowShadowBlur,
                  offset: const Offset(
                    0,
                    DesignTokens.componentFloatingShadowShadowOffset,
                  ),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(
              icon ?? glyph,
              size: _bannerGlyphSize,
              color: glyphColor,
            ),
          ),
          const SizedBox(width: DesignTokens.spacingMd),
          Expanded(
            child: Text(
              message,
              maxLines: _bannerMaxLines,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.of(context).label
                  .copyWith(color: foreground),
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
