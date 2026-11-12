import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';

import '../models/add_device_mode.dart';

export '../models/add_device_mode.dart';

class ConnectionModeSelector extends HookWidget {
  const ConnectionModeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AddDeviceMode selected;
  final ValueChanged<AddDeviceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final modeKeys = useMemoized(
      () => {for (final mode in AddDeviceMode.values) mode: GlobalKey()},
    );
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final selectedContext = modeKeys[selected]?.currentContext;
        if (selectedContext != null) {
          Scrollable.ensureVisible(selectedContext, alignment: .5);
        }
      });
      return null;
    }, [selected]);

    return ContentPanel(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in const [
                (
                  AddDeviceMode.pairing,
                  '配对码',
                  LucideIcons.keyRound,
                  ConnectTokens.blue,
                ),
                (
                  AddDeviceMode.qr,
                  '扫码',
                  LucideIcons.qrCode,
                  ConnectTokens.mint,
                ),
                (
                  AddDeviceMode.usb,
                  'USB',
                  LucideIcons.usb,
                  ConnectTokens.amber,
                ),
                (
                  AddDeviceMode.ip,
                  'IP 连接',
                  LucideIcons.network,
                  ConnectTokens.coral,
                ),
              ])
                _ModeTab(
                  key: modeKeys[entry.$1],
                  label: entry.$2,
                  icon: entry.$3,
                  color: entry.$4,
                  selected: selected == entry.$1,
                  minWidth: constraints.maxWidth / AddDeviceMode.values.length,
                  onTap: () => onChanged(entry.$1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.minWidth,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final double minWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minWidth,
            minHeight: DesignTokens.componentNavigationHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingXs,
              vertical: DesignTokens.spacingTight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: DesignTokens.componentIconSize, color: color),
                const SizedBox(height: DesignTokens.spacingXxs),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: DesignTokens.typographyCaptionFontSize,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingXxs),
                Container(
                  width: DesignTokens.componentIconSize,
                  height: DesignTokens.spacingHairline * 2,
                  color: selected
                      ? theme.colorScheme.onSurface
                      : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
