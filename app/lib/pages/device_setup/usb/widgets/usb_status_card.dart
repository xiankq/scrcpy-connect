import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';

/// USB 状态卡的状态槽：沿用状态点规则（design.md「添加设备与连接」）。
enum UsbStatus { waiting, checking, detected, unsupported }

/// USB 状态卡（Ardot 37:2317）：内距 16/24、间距 12；示意为本机接口、线、状态槽、线、手机，
/// 各 24 点、间距 8，线 24×2；下方 `headline` 标题与 `subheadline` 次要色说明，间距 4。
const _cardPadding = EdgeInsets.symmetric(
  horizontal: DesignTokens.componentCardPadding,
  vertical: DesignTokens.spacingXxl,
);
const _lineWidth = DesignTokens.componentBarGlyphSize;
const _lineHeight = DesignTokens.spacingXxs;

class UsbStatusCard extends StatelessWidget {
  const UsbStatusCard({
    super.key,
    required this.title,
    required this.message,
    required this.status,
  });

  final String title;
  final String message;
  final UsbStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final lineColor = status == UsbStatus.detected
        ? colors.success
        : colors.separator;
    Widget line() => Container(
      width: _lineWidth,
      height: _lineHeight,
      decoration: ShapeDecoration(
        color: lineColor,
        shape: const StadiumBorder(),
      ),
    );
    const glyph = DesignTokens.componentBarGlyphSize;
    final slot = switch (status) {
      UsbStatus.checking => const ContentLoadingIndicator(),
      UsbStatus.detected => Icon(
        LucideIcons.circleCheck,
        size: glyph,
        color: colors.success,
      ),
      UsbStatus.unsupported => Icon(
        LucideIcons.circleAlert,
        size: glyph,
        color: colors.warning,
      ),
      UsbStatus.waiting => Icon(
        LucideIcons.circleDashed,
        size: glyph,
        color: colors.outline,
      ),
    };
    return ContentPanel(
      padding: _cardPadding,
      child: Column(
        children: [
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  AppIcons.connectionUsb,
                  size: glyph,
                  color: DesignTokens.colorAccentOrange,
                ),
                const SizedBox(width: DesignTokens.spacingSm),
                line(),
                const SizedBox(width: DesignTokens.spacingSm),
                SizedBox.square(dimension: glyph, child: slot),
                const SizedBox(width: DesignTokens.spacingSm),
                line(),
                const SizedBox(width: DesignTokens.spacingSm),
                Icon(LucideIcons.smartphone, size: glyph, color: colors.text),
              ],
            ),
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          Semantics(
            liveRegion: true,
            child: Text(
              title,
              style: type.headline,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingXs),
          Text(
            message,
            style: type.subheadline.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
