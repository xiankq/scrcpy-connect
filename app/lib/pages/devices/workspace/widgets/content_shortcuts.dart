import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

/// 快捷入口色块边长（Ardot 快捷入口 37:1761「色块」52，圆角 16）。
const _tileSize = DesignTokens.componentDeviceTileSize;

/// 每列至少保留的宽度：色块加两侧各 12 点标签余量，按文字缩放放大。
const _minColumnWidth = _tileSize + 2 * DesignTokens.spacingMd;

/// 未连接时整项降到 38%（design.md「快捷入口」）。
const _unavailableOpacity = .38;

/// 工作台快捷入口（Ardot 37:1761）：一张 `card`，圆角 24、内距 16，四个 52 点功能色块
/// 加下方 `footnote` 标签等宽排列。未连接时降到 38%，点按给出无法打开的原因。
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
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final items = [
      (
        '文件',
        AppIcons.files,
        FunctionTone.file,
        () =>
            FilesRoute(deviceId: deviceId, path: '/sdcard').push<void>(context),
      ),
      (
        '相册',
        AppIcons.gallery,
        FunctionTone.media,
        () => GalleryRoute(deviceId: deviceId).push<void>(context),
      ),
      (
        '通知',
        AppIcons.notifications,
        FunctionTone.notification,
        () => NotificationsRoute(deviceId: deviceId).push<void>(context),
      ),
      (
        '电话',
        AppIcons.calls,
        FunctionTone.connection,
        () => CallsRoute(deviceId: deviceId).push<void>(context),
      ),
    ];
    return Material(
      color: colors.card,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(DesignTokens.componentListGroupRounded),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final columns =
                (constraints.maxWidth / (_minColumnWidth * scale.clamp(1, 2)))
                    .floor()
                    .clamp(1, items.length);
            final balancedColumns = columns == 3 ? 2 : columns;
            return Wrap(
              runSpacing: DesignTokens.spacingMd,
              children: [
                for (final (label, icon, tone, open) in items)
                  SizedBox(
                    width: constraints.maxWidth / balancedColumns,
                    child: Semantics(
                      button: true,
                      label: label,
                      child: Tooltip(
                        excludeFromSemantics: true,
                        message: label,
                        child: InkWell(
                          onTap: enabled ? open : onUnavailable,
                          customBorder: const RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(DesignTokens.roundedMd),
                            ),
                          ),
                          splashFactory: NoSplash.splashFactory,
                          highlightColor: colors.pressed,
                          child: Opacity(
                            opacity: enabled ? 1 : _unavailableOpacity,
                            child: ExcludeSemantics(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FeatureIcon(
                                    icon,
                                    color: tone,
                                    size: _tileSize,
                                  ),
                                  const SizedBox(
                                    height: DesignTokens.spacingSm,
                                  ),
                                  Text(
                                    label,
                                    style: type.footnote,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
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
}
