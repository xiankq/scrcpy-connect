import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// designs/design.md「功能色」：功能入口色块的底色，明暗主题相同。
abstract final class FunctionTone {
  /// 设备、远控、窗口比例、导航键。
  static const device = DesignTokens.componentIconTileDeviceBackgroundColor;

  /// 连接、授权、电话。
  static const connection =
      DesignTokens.componentIconTileConnectionBackgroundColor;

  /// 文件与目录。
  static const file = DesignTokens.componentIconTileFileBackgroundColor;

  /// 照片、视频、清晰度、帧率。
  static const media = DesignTokens.componentIconTileMediaBackgroundColor;

  /// 传输与交付。
  static const transfer = DesignTokens.componentIconTileTransferBackgroundColor;

  /// 通知、清空与重置类入口。
  static const notification =
      DesignTokens.componentIconTileNotificationBackgroundColor;

  /// 显示、外观、点亮与熄屏。
  static const display = DesignTokens.componentIconTileDisplayBackgroundColor;

  /// 归档、记录与恢复。
  static const archive = DesignTokens.componentIconTileArchiveBackgroundColor;

  /// 通用设置、日志、诊断、关于、保持唤醒。
  static const utility = DesignTokens.componentIconTileUtilityBackgroundColor;
}

/// 紧凑色块用于宫格入口（Ardot「文件类型入口」37:2267），尺寸取不超过列表色块的档位。
const _compactTileSize = 26.0;
const _compactGlyphSize = 16.0;

/// 功能色块（Ardot 37:570）：30 点连续圆角方块，图形一律白色。
class ListIconBadge extends StatelessWidget {
  const ListIconBadge({
    super.key,
    required this.icon,
    required this.backgroundColor,
    this.compact = false,
  });

  final IconData icon;

  /// 取 [FunctionTone] 中的功能色；禁用时由调用方传 `AppColors.disabled`。
  final Color backgroundColor;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: compact ? _compactTileSize : DesignTokens.componentIconTileSize,
    child: DecoratedBox(
      decoration: ShapeDecoration(
        color: backgroundColor,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.componentIconTileRounded),
          ),
        ),
      ),
      child: Icon(
        icon,
        size: compact
            ? _compactGlyphSize
            : DesignTokens.componentIconTileGlyphSize,
        color: DesignTokens.componentIconTileTextColor,
      ),
    ),
  );
}
