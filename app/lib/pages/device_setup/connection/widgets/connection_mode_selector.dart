import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/widgets/content.dart';

import '../models/add_device_mode.dart';

export '../models/add_device_mode.dart';

class ConnectionModeSelector extends StatelessWidget {
  const ConnectionModeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AddDeviceMode selected;
  final ValueChanged<AddDeviceMode> onChanged;

  static const _tabs = [
    (
      AddDeviceMode.pairing,
      '配对码',
      AppIcons.connectionPairing,
      DesignTokens.componentConnectionIconPairingTextColor,
    ),
    (
      AddDeviceMode.qr,
      '扫码',
      AppIcons.connectionScan,
      DesignTokens.componentConnectionIconQrTextColor,
    ),
    (
      AddDeviceMode.usb,
      'USB',
      AppIcons.connectionUsb,
      DesignTokens.componentConnectionIconUsbTextColor,
    ),
    (
      AddDeviceMode.ip,
      'IP 连接',
      AppIcons.connectionIp,
      DesignTokens.componentConnectionIconIpTextColor,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ContentPanel(
      radius: DesignTokens.componentConnectionTabsRounded,
      padding: const EdgeInsets.all(
        DesignTokens.componentConnectionTabsPadding,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) >=
                  288
              ? 4
              : 2;
          const gap = DesignTokens.spacingMicro;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final (mode, label, icon, color) in _tabs)
                SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * gap) / columns,
                  child: Semantics(
                    button: true,
                    selected: selected == mode,
                    child: Material(
                      animationDuration: reduceMotionOf(context)
                          ? Duration.zero
                          : shortTransitionDuration,
                      color: selected == mode
                          ? theme.colorScheme.surfaceContainerHigh
                          : DesignTokens.colorTransparent,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.componentConnectionTabSelectedRounded,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          DesignTokens.componentConnectionTabSelectedRounded,
                        ),
                        onTap: () => onChanged(mode),
                        child: Container(
                          alignment: Alignment.center,
                          constraints: const BoxConstraints(
                            minHeight:
                                DesignTokens.componentConnectionTabsHeight -
                                2 * DesignTokens.componentConnectionTabsPadding,
                          ),
                          padding: const EdgeInsets.all(DesignTokens.spacingXs),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icon,
                                size: DesignTokens.componentIconActionSize,
                                color: color,
                              ),
                              const SizedBox(height: DesignTokens.spacingXxs),
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: selected == mode
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: selected == mode
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
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
    );
  }
}
