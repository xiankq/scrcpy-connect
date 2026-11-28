import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 应用原图标默认边长：沿用既有调用方（远控窗口占位）的 52；页面内宫格与行按设计稿传入 48 或 36。
const _defaultSize = 52.0;

/// 小于此边长时占位图形用区块档（20），否则用页头档（24）。
const _largeIconSize = 48.0;

/// 圆角档位，取不超过短边三分之一的最大档（design.md「形状与间距」：36 → 8，48/52 → 16；
/// Ardot 应用行 37:915、通知卡 37:1111 的 36 点图标圆角 8）。
const _radii = [
  DesignTokens.roundedXxl,
  DesignTokens.roundedXl,
  DesignTokens.roundedLg,
  DesignTokens.roundedMd,
  DesignTokens.roundedSm,
  DesignTokens.roundedXs,
];

/// 图标属于目标设备与包名，不使用主控设备的图标集合。原图按尺寸档位裁成连续圆角。
class PhoneAppIcon extends ConsumerWidget {
  const PhoneAppIcon({
    super.key,
    required this.deviceId,
    required this.packageName,
    this.refreshKey,
    this.userId,
    this.size = _defaultSize,
  });
  final String deviceId;
  final String packageName;
  final Object? refreshKey;
  final int? userId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(
      deviceAppIconProvider((
        deviceId: deviceId,
        packageName: packageName,
        userId: userId,
      ), revision: refreshKey),
    );
    final icon = result.asData?.value;
    Widget placeholder() => Icon(
      !result.isLoading ? LucideIcons.imageOff : LucideIcons.image,
      color: AppColors.of(context).textSecondary,
      size: size < _largeIconSize
          ? DesignTokens.componentSectionGlyphSize
          : DesignTokens.componentBarGlyphSize,
      semanticLabel: !result.isLoading ? '图标暂不可用' : '正在读取图标',
    );
    return SizedBox.square(
      dimension: size,
      child: icon == null
          ? Center(child: placeholder())
          : ClipRSuperellipse(
              borderRadius: BorderRadius.all(
                Radius.circular(
                  _radii.firstWhere(
                    (radius) => radius <= size / 3,
                    orElse: () => DesignTokens.roundedXs,
                  ),
                ),
              ),
              child: Image.memory(
                icon.bytes,
                fit: BoxFit.contain,
                gaplessPlayback: false,
                errorBuilder: (_, _, _) => Center(child: placeholder()),
              ),
            ),
    );
  }
}
