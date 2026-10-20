import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/router/app_router.dart';

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
        return Wrap(
          runSpacing: DesignTokens.spacingMd,
          children: [
            for (final item in [
              (
                '文件管理',
                LucideIcons.folder,
                DesignTokens.colorListIconAmber,
                () => FilesRoute(
                  deviceId: deviceId,
                  path: '/sdcard',
                ).push<void>(context),
              ),
              (
                '手机相册',
                LucideIcons.images,
                DesignTokens.colorListIconBlue,
                () => GalleryRoute(deviceId: deviceId).push<void>(context),
              ),
              (
                '实时通知',
                LucideIcons.bell,
                DesignTokens.colorListIconBlue,
                () =>
                    NotificationsRoute(deviceId: deviceId).push<void>(context),
              ),
              (
                '来电与通话',
                LucideIcons.phone,
                DesignTokens.colorListIconMint,
                () => CallsRoute(deviceId: deviceId).push<void>(context),
              ),
            ])
              SizedBox(
                width: constraints.maxWidth / columns,
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
                        ListIconBadge(icon: item.$2, backgroundColor: item.$3),
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
