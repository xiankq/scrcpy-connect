import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/widgets/content_arrival.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/pages/apps/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';

class WorkspaceAppGrid extends StatelessWidget {
  const WorkspaceAppGrid({
    super.key,
    required this.title,
    required this.deviceId,
    required this.apps,
    required this.onOpen,
    required this.empty,
    this.actionLabel,
    this.onAction,
    this.loading = false,
    this.muted = false,
  });

  final String title;
  final String deviceId;
  final List<DeviceApp> apps;
  final void Function(BuildContext source, DeviceApp app) onOpen;
  final Widget empty;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const topPadding = DesignTokens.spacingXxs;
    const bottomPadding = DesignTokens.spacingSm - DesignTokens.spacingMicro;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(
        DesignTokens.componentWorkspaceAppPanelRounded,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacingMd,
          topPadding,
          DesignTokens.spacingMd,
          bottomPadding,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight:
                DesignTokens.componentWorkspaceAppPanelHeight -
                topPadding -
                bottomPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DesignTokens.componentWorkspaceAppHeaderHeight,
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight:
                            DesignTokens.componentWorkspaceAppHeaderHeight,
                      ),
                      child: Align(
                        widthFactor: 1,
                        heightFactor: 1,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(title, style: theme.textTheme.titleMedium),
                      ),
                    ),
                    if (actionLabel case final label?)
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: onAction,
                        child: Text(label),
                      ),
                  ],
                ),
              ),
              ContentArrival(
                state: loading,
                waiting: loading,
                child: apps.isEmpty && !loading
                    ? Padding(
                        padding: const EdgeInsets.only(
                          top: DesignTokens.spacingMicro,
                        ),
                        child: empty,
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final columns =
                              (constraints.maxWidth /
                                      DesignTokens.componentAppCellWidth)
                                  .floor()
                                  .clamp(1, 6);
                          if (loading) {
                            return LoadingSkeleton(
                              child: Row(
                                children: [
                                  for (var index = 0; index < columns; index++)
                                    const Expanded(
                                      child: SizedBox(
                                        height:
                                            DesignTokens.componentAppIconSize,
                                        child: Center(
                                          child: SkeletonBlock(
                                            width: DesignTokens
                                                .componentWorkspaceAppEmptySize,
                                            height: DesignTokens
                                                .componentWorkspaceAppEmptySize,
                                            radius: DesignTokens
                                                .componentAppIconRounded,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }
                          return Wrap(
                            children: [
                              for (final app in apps)
                                SizedBox(
                                  width: constraints.maxWidth / columns,
                                  child: Builder(
                                    builder: (source) => Tooltip(
                                      message: app.name,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(
                                          DesignTokens.roundedMd,
                                        ),
                                        onTap: () => onOpen(source, app),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            minHeight: DesignTokens
                                                .componentAppIconSize,
                                          ),
                                          child: Center(
                                            child: Opacity(
                                              opacity: muted ? .55 : 1,
                                              child: PhoneAppIcon(
                                                deviceId: deviceId,
                                                packageName: app.packageName,
                                                userId: app.userId,
                                                size: DesignTokens
                                                    .componentWorkspaceAppEmptySize,
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
            ],
          ),
        ),
      ),
    );
  }
}
