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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final connecting = deviceConnectionInProgress(device);
    if (showcase) {
      final (icon, color) = switch (device.status) {
        .connected => (LucideIcons.check, DesignTokens.colorSuccessDark),
        .failed => (LucideIcons.x, DesignTokens.colorDangerDark),
        .unauthorized => (
          LucideIcons.shieldAlert,
          DesignTokens.colorAccentAmber,
        ),
        _ => (
          LucideIcons.circle,
          DesignTokens.componentDeviceGlyphIdleBackgroundColor,
        ),
      };
      return ExcludeSemantics(
        child: Container(
          width: pane
              ? DesignTokens.componentDeviceIdentityPaneWidth
              : DesignTokens.componentWorkspacePhoneWidth,
          height: pane
              ? DesignTokens.componentDeviceIdentityPaneHeight
              : DesignTokens.componentWorkspacePhoneHeight,
          padding: const EdgeInsets.all(
            DesignTokens.componentWorkspacePhonePadding,
          ),
          decoration: BoxDecoration(
            color: DesignTokens.colorDeviceScreenRim,
            borderRadius: BorderRadius.circular(
              pane
                  ? DesignTokens.roundedLg
                  : DesignTokens.componentWorkspacePhoneRounded,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DesignTokens.colorDeviceScreen,
              borderRadius: BorderRadius.circular(
                pane
                    ? DesignTokens.roundedLg -
                          DesignTokens.componentWorkspacePhonePadding
                    : DesignTokens.componentWorkspacePhoneScreenRounded,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (connecting)
                  const ContentLoadingIndicator(
                    size: DesignTokens.componentIconSize,
                    color: DesignTokens.componentDeviceGlyphIdleBackgroundColor,
                  )
                else
                  Icon(
                    icon,
                    color: color,
                    size: DesignTokens.componentIconSize,
                  ),
                Positioned(
                  top: DesignTokens.spacingXs,
                  child: Container(
                    width: DesignTokens.componentIconSmallSize,
                    height: DesignTokens.spacingXxs,
                    decoration: BoxDecoration(
                      color: DesignTokens.componentDeviceGlyphIdleBorderColor,
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
      );
    }
    // ADB provides model names for saved records. Known tablet families can
    // use the landscape glyph while unknown models retain the handset glyph.
    final tablet = _tabletModel.hasMatch(device.model ?? device.name ?? '');
    final online = device.status == .connected;
    final background = dark
        ? DesignTokens.colorDevicePanelDark
        : DesignTokens.colorDevicePanel;
    final (mark, filled) = switch (device.status) {
      .connected => (DesignTokens.colorSuccess, true),
      .failed => (
        dark ? DesignTokens.colorDangerDark : DesignTokens.colorDanger,
        true,
      ),
      .unauthorized || .authorizing => (DesignTokens.colorWarning, true),
      _ => (
        dark
            ? DesignTokens.colorSecondaryDark
            : DesignTokens.componentDeviceGlyphIdleBorderColor,
        false,
      ),
    };
    return ExcludeSemantics(
      child: Container(
        width: DesignTokens.componentDeviceIdentityWidth,
        height: compact
            ? DesignTokens.componentDeviceIdentityCompactHeight
            : DesignTokens.componentDeviceIdentityHeight,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(
            DesignTokens.componentDeviceIdentityRounded,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Container(
                width: tablet ? 38 : 24,
                height: tablet ? 29 : 38,
                decoration: BoxDecoration(
                  color: online
                      ? DesignTokens.componentDeviceGlyphBackgroundColor
                      : DesignTokens.componentDeviceGlyphIdleBackgroundColor,
                  borderRadius: BorderRadius.circular(tablet ? 6 : 7),
                  border: Border.all(
                    color: DesignTokens.componentDeviceGlyphBorderColor,
                    width: DesignTokens.spacingMicro,
                  ),
                ),
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: DesignTokens.spacingMicro),
                child: Container(
                  width: tablet
                      ? DesignTokens.spacingMicro
                      : DesignTokens.spacingXs,
                  height: DesignTokens.spacingMicro,
                  decoration: BoxDecoration(
                    color: DesignTokens.componentDeviceGlyphIdleBorderColor
                        .withValues(alpha: .46),
                    borderRadius: BorderRadius.circular(
                      DesignTokens.roundedFull,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: DesignTokens.spacingXxs,
              bottom: DesignTokens.spacingXxs,
              child: Container(
                padding: const EdgeInsets.all(DesignTokens.spacingMicro),
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: connecting
                    ? ContentLoadingIndicator(
                        size: DesignTokens.componentDeviceIdentityStatusSize,
                        color: mark,
                      )
                    : Container(
                        width: DesignTokens.componentDeviceIdentityStatusSize,
                        height: DesignTokens.componentDeviceIdentityStatusSize,
                        decoration: BoxDecoration(
                          color: filled ? mark : background,
                          border: filled
                              ? null
                              : Border.all(color: mark, width: 1.5),
                          shape: BoxShape.circle,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final _tabletModel = RegExp(
    r'\b(tablet|pad|tab)\b|\bSM-[TX]\d',
    caseSensitive: false,
  );
}

String deviceConnectionLabel(DeviceSnapshot device) {
  if (device.status != .offline) return deviceStatusText(device);
  final seconds = device.lastSeen;
  if (seconds == null || seconds <= 0) return '离线 · 暂无最近连接时间';
  final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '离线 · 上次连接 ${time.year}/${two(time.month)}/${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
