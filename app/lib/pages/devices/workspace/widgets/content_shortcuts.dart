import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

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
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(
      DesignTokens.componentWorkspaceShortcutsRounded,
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingXxs,
        vertical: DesignTokens.spacingTight,
      ),
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
                  AppIcons.files,
                  DesignTokens.colorListIconDocument,
                  () => FilesRoute(
                    deviceId: deviceId,
                    path: '/sdcard',
                  ).push<void>(context),
                ),
                (
                  '相册',
                  AppIcons.gallery,
                  DesignTokens.colorListIconSlate,
                  () => GalleryRoute(deviceId: deviceId).push<void>(context),
                ),
                (
                  '通知',
                  AppIcons.notifications,
                  DesignTokens.colorListIconCoral,
                  () =>
                      NotificationsRoute(deviceId: deviceId)
                          .push<void>(context),
                ),
                (
                  '电话',
                  AppIcons.calls,
                  DesignTokens.colorListIconMint,
                  () => CallsRoute(deviceId: deviceId).push<void>(context),
                ),
              ])
                SizedBox(
                  width: constraints.maxWidth / balancedColumns,
                  child: Semantics(
                    button: true,
                    label: item.$1,
                    child: Tooltip(
                      excludeFromSemantics: true,
                      message: item.$1,
                      child: InkWell(
                        onTap: enabled ? item.$4 : onUnavailable,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.roundedMd,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.spacingXxs,
                            vertical: DesignTokens.spacingXs,
                          ),
                          child: Center(
                            child: Container(
                              width:
                                  DesignTokens.componentWorkspaceShortcutSize,
                              height:
                                  DesignTokens.componentWorkspaceShortcutSize,
                              decoration: BoxDecoration(
                                color: enabled
                                    ? item.$3
                                    : DesignTokens
                                          .componentDeviceShortcutDisabledBackgroundColor,
                                borderRadius: BorderRadius.circular(
                                  DesignTokens
                                      .componentWorkspaceShortcutRounded,
                                ),
                              ),
                              child: Icon(
                                item.$2,
                                color: DesignTokens.colorWhite,
                                size: DesignTokens.componentIconSize,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
