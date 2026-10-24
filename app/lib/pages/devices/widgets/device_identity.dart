import 'package:scrcpy_connect/presentation/formatters.dart';
import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 只表示设备身份，不作为远端手机当前画面的预览。
class DeviceIdentity extends StatelessWidget {
  const DeviceIdentity({
    super.key,
    required this.device,
    this.compact = false,
    this.showcase = false,
  });
  final Json device;
  final bool compact;
  final bool showcase;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (statusIcon, statusColor) = switch (value(
      device,
      'status',
      'offline',
    )) {
      'connected' => (LucideIcons.circleCheck, ConnectTokens.mint),
      'connecting' ||
      'reconnecting' ||
      'checking' => (LucideIcons.loaderCircle, ConnectTokens.blue),
      'unauthorized' => (LucideIcons.shieldAlert, ConnectTokens.amber),
      _ => (LucideIcons.wifiOff, colors.onSurfaceVariant),
    };
    final width = showcase
        ? DesignTokens.componentDeviceIdentityShowcaseWidth
        : DesignTokens.componentDeviceIdentityWidth;
    final height = showcase
        ? DesignTokens.componentDeviceIdentityShowcaseHeight
        : compact
        ? DesignTokens.componentDeviceIdentityCompactHeight
        : DesignTokens.componentDeviceIdentityHeight;
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
              color: colors.onSurface,
              borderRadius: BorderRadius.circular(DesignTokens.roundedSm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(
                DesignTokens.spacingMicro + DesignTokens.spacingHairline,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DesignTokens.spacingXs),
                child: ColoredBox(
                  color: colors.surfaceContainerHigh,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        statusIcon,
                        color: statusColor,
                        size: showcase
                            ? DesignTokens.componentIconLargeSize
                            : DesignTokens.componentIconActionSize,
                      ),
                      Positioned(
                        top: DesignTokens.spacingXxs,
                        child: Container(
                          width: DesignTokens.spacingSm,
                          height: DesignTokens.spacingMicro,
                          decoration: BoxDecoration(
                            color: colors.onSurface,
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

String deviceConnectionLabel(Json device) {
  final status = value(device, 'status', 'offline');
  if (status != 'offline') return statusText(status);
  final seconds = int.tryParse(value(device, 'lastSeen'));
  if (seconds == null || seconds <= 0) return '离线 · 暂无最近连接时间';
  final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '离线 · 上次连接 ${time.year}/${two(time.month)}/${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
