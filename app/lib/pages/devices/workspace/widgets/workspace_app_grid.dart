import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/content_arrival.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/pages/apps/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';

/// 应用原图标边长与圆角（Ardot 应用卡 37:2963「应用图标」48，圆角 16）。
const appCardIconSize = 48.0;
const appCardIconRounded = DesignTokens.roundedMd;

/// 宫格每列至少保留的宽度（图标加两侧标签余量）；最多四列（Ardot 应用卡 37:1829）。
const _minColumnWidth = appCardIconSize + 2 * DesignTokens.spacingLg;
const _maxColumns = 4;

/// 工作台应用卡（Ardot 应用卡 37:2963）：`card` 圆角 24，上 12、下 16；标题行为 `headline`
/// 加尾部文字按钮（左 16、右 4），下方 12 为应用宫格或说明，左右 16。
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
  });

  final String title;
  final String deviceId;
  final List<DeviceApp> apps;
  final void Function(BuildContext source, DeviceApp app) onOpen;
  final Widget empty;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    return Material(
      color: colors.card,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(DesignTokens.componentListGroupRounded),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.only(
          top: DesignTokens.spacingMd,
          bottom: DesignTokens.spacingLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: DesignTokens.spacingLg,
                end: DesignTokens.spacingXs,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DesignTokens.componentSectionButtonSize,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  heightFactor: 1,
                  child: SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(title, style: type.headline),
                        ),
                        if (actionLabel case final label?)
                          AppButton(
                            role: AppButtonRole.text,
                            size: AppButtonSize.section,
                            onPressed: onAction,
                            label: label,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingLg,
              ),
              child: ContentArrival(
                state: loading,
                waiting: loading,
                child: apps.isEmpty && !loading
                    ? Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: empty,
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final scale = MediaQuery.textScalerOf(context)
                              .scale(1)
                              .clamp(1.0, 2.0);
                          final fit =
                              (constraints.maxWidth / (_minColumnWidth * scale))
                                  .floor()
                                  .clamp(1, _maxColumns);
                          if (loading) {
                            return LoadingSkeleton(
                              child: Row(
                                children: [
                                  for (var index = 0; index < fit; index++)
                                    const Expanded(
                                      child: Center(
                                        child: SkeletonBlock(
                                          width: appCardIconSize,
                                          height: appCardIconSize,
                                          radius: appCardIconRounded,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }
                          final columns = apps.length < fit ? apps.length : fit;
                          return Wrap(
                            runSpacing: DesignTokens.spacingMd,
                            children: [
                              for (final app in apps)
                                SizedBox(
                                  width: constraints.maxWidth / columns,
                                  child: Builder(
                                    builder: (source) => Tooltip(
                                      message: app.name,
                                      excludeFromSemantics: true,
                                      child: InkWell(
                                        customBorder:
                                            const RoundedSuperellipseBorder(
                                              borderRadius: BorderRadius.all(
                                                Radius.circular(
                                                  DesignTokens.roundedMd,
                                                ),
                                              ),
                                            ),
                                        splashFactory: NoSplash.splashFactory,
                                        highlightColor: colors.pressed,
                                        onTap: () => onOpen(source, app),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            PhoneAppIcon(
                                              deviceId: deviceId,
                                              packageName: app.packageName,
                                              userId: app.userId,
                                              size: appCardIconSize,
                                            ),
                                            const SizedBox(
                                              height: DesignTokens.spacingSm,
                                            ),
                                            Text(
                                              app.name,
                                              style: type.caption,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
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
            ),
          ],
        ),
      ),
    );
  }
}
