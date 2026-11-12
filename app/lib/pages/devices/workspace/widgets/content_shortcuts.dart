import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';

class ContentShortcuts extends StatelessWidget {
  const ContentShortcuts({
    super.key,
    required this.deviceId,
    required this.enabled,
    required this.onUnavailable,
  });
  final String deviceId;
  final bool enabled;
  final VoidCallback onUnavailable;

  @override
  Widget build(BuildContext context) => ContentPanel(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final scale =
            MediaQuery.textScalerOf(context)
                .scale(DesignTokens.typographyBodyFontSize) /
            DesignTokens.typographyBodyFontSize;
        final columns =
            (constraints.maxWidth /
                    (DesignTokens.componentAppCellWidth * scale.clamp(1, 2)))
                .floor()
                .clamp(1, 4);
        final balancedColumns = columns == 3 ? 2 : columns;
        return Wrap(
          runSpacing: DesignTokens.spacingMd,
          children: [
            for (final item in [
              (
                '文件',
                LucideIcons.folder,
                DesignTokens.colorListIconAmber,
                () => FilesRoute(
                  deviceId: deviceId,
                  path: '/sdcard',
                ).push<void>(context),
              ),
              (
                '相册',
                LucideIcons.images,
                DesignTokens.colorListIconPurple,
                () => GalleryRoute(deviceId: deviceId).push<void>(context),
              ),
              (
                '通知',
                LucideIcons.bell,
                DesignTokens.colorListIconBlue,
                () =>
                    NotificationsRoute(deviceId: deviceId).push<void>(context),
              ),
              (
                '电话',
                LucideIcons.phone,
                DesignTokens.colorListIconMint,
                () => CallsRoute(deviceId: deviceId).push<void>(context),
              ),
            ])
              SizedBox(
                width: constraints.maxWidth / balancedColumns,
                child: InkWell(
                  onTap: enabled ? item.$4 : onUnavailable,
                  borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacingXxs,
                      vertical: DesignTokens.spacingXs,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: DesignTokens.componentAppIconSize,
                          height: DesignTokens.componentAppIconSize,
                          decoration: BoxDecoration(
                            color: item.$3,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.roundedMd,
                            ),
                          ),
                          child: Icon(
                            item.$2,
                            color: DesignTokens.colorWhite,
                            size: DesignTokens.componentIconLargeSize,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacingXs),
                        Text(
                          item.$1,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
