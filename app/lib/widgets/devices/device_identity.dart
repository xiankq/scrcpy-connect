import 'package:scrcpy_connect/widgets/content.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';

/// 只表示设备身份，不作为远端手机当前画面的预览。
class DeviceIdentity extends StatelessWidget {
  const DeviceIdentity({
    super.key,
    required this.device,
    this.compact = false,
    this.showcase = false,
    this.pane = false,
  });
  final DeviceSnapshot device;
  final bool compact;
  final bool showcase;
  final bool pane;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final connecting = deviceConnectionInProgress(device);
    final (statusIcon, statusColor) = switch (device.status) {
      .connected => (LucideIcons.check, DesignTokens.colorSuccessDark),
      .failed => (LucideIcons.circleX, DesignTokens.colorAccentCoral),
      .unauthorized => (LucideIcons.shieldAlert, DesignTokens.colorAccentAmber),
      _ => (LucideIcons.circle, DesignTokens.colorWhite.withValues(alpha: .62)),
    };
    final iconSize = showcase
        ? DesignTokens.componentIconLargeSize
        : DesignTokens.componentIconActionSize;
    final width = pane
        ? DesignTokens.componentDeviceIdentityPaneWidth
        : showcase
        ? DesignTokens.componentDeviceIdentityShowcaseWidth
        : DesignTokens.componentDeviceIdentityWidth;
    final height = pane
        ? DesignTokens.componentDeviceIdentityPaneHeight
        : showcase
        ? DesignTokens.componentDeviceIdentityShowcaseHeight
        : compact
        ? DesignTokens.componentDeviceIdentityCompactHeight
        : DesignTokens.componentDeviceIdentityHeight;
    if (!showcase) {
      final color = switch (device.status) {
        .connected => DesignTokens.colorSuccess,
        .failed => colors.error,
        .unauthorized => DesignTokens.componentConnectionIconUsbTextColor,
        _ => colors.onSurfaceVariant,
      };
      return ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? DesignTokens.componentDeviceHeroDarkBackgroundColor
                  : DesignTokens.componentDeviceIdentityBackgroundColor,
              borderRadius: BorderRadius.circular(
                DesignTokens.componentDeviceIdentityRounded,
              ),
            ),
            child: Stack(
              children: [
                const Center(
                  child: Icon(
                    LucideIcons.smartphone,
                    size: DesignTokens.componentIconFeatureSize,
                  ),
                ),
                Positioned(
                  right: DesignTokens.spacingXs,
                  bottom: DesignTokens.spacingXs,
                  child: connecting
                      ? ContentLoadingIndicator(
                          size: DesignTokens.componentDeviceIdentityStatusSize,
                          color: colors.primary,
                        )
                      : Icon(
                          switch (device.status) {
                            .connected => LucideIcons.check,
                            .failed => LucideIcons.x,
                            .unauthorized => LucideIcons.circleAlert,
                            _ => LucideIcons.circle,
                          },
                          size: DesignTokens.componentDeviceIdentityStatusSize,
                          color: color,
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingXxs,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color:
                  DesignTokens.componentDeviceIdentityShowcaseBackgroundColor,
              border: Border.all(
                color: DesignTokens.componentDeviceIdentityRimBackgroundColor,
                width: DesignTokens.spacingMicro,
              ),
              borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
            ),
            child: Padding(
              padding: const EdgeInsets.all(
                DesignTokens.spacingMicro + DesignTokens.spacingHairline,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DesignTokens.spacingXs),
                child: ColoredBox(
                  color: DesignTokens
                      .componentDeviceIdentityShowcaseBackgroundColor,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (connecting)
                        ContentLoadingIndicator(
                          size: iconSize,
                          color: DesignTokens.colorWhite,
                        )
                      else
                        Icon(statusIcon, color: statusColor, size: iconSize),
                      Positioned(
                        top: DesignTokens.spacingXxs,
                        child: Container(
                          width: DesignTokens.spacingSm,
                          height: DesignTokens.spacingMicro,
                          decoration: BoxDecoration(
                            color: colors.outlineVariant,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.roundedFull,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String deviceConnectionLabel(DeviceSnapshot device) {
  if (device.status != .offline) return deviceStatusText(device);
  final seconds = device.lastSeen;
  if (seconds == null || seconds <= 0) return '离线 · 暂无最近连接时间';
  final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '离线 · 上次连接 ${time.year}/${two(time.month)}/${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
