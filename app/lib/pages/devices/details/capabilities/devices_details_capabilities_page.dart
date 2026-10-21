import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CapabilitiesPage extends StatelessWidget {
  const CapabilitiesPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '功能支持状态',
    child: CommandView(
      controller: controller,
      command: 'device.capabilities',
      params: {'deviceId': device['id']},
      emptyTitle: '尚未获得功能支持状态',
      builder: (context, data, refresh) {
        final capabilities = objects(data['capabilities']);
        final footer = <Widget>[
          if (capabilities.isEmpty) const StateNote('尚未检查这台设备的功能。请连接后重新检查。'),
          const SizedBox(height: DesignTokens.spacingMd),
          OutlinedButton.icon(
            onPressed: refresh,
            icon: const Icon(
              LucideIcons.refreshCw,
              size: DesignTokens.componentIconActionSize,
            ),
            label: const Text('重新检查'),
          ),
        ];
        return GroupedListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            const StateNote('已连接不代表每项功能都可用。支持状态以这台设备的实际检查结果为准。'),
            if (capabilities.isNotEmpty)
              SettingsGroup(
                children: [
                  for (final (item, cap) in capabilities.indexed)
                    _CapabilityRow(
                      key: ValueKey((
                        'capability',
                        value(device, 'id'),
                        value(cap, 'id', value(cap, 'key')),
                        item,
                      )),
                      capability: cap,
                    ),
                ],
              ),
            ...footer,
          ],
        );
      },
    ),
  );
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({super.key, required this.capability});
  final Json capability;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (value(
      capability,
      'id',
      value(capability, 'key'),
    )) {
      'shell' => (LucideIcons.terminal, DesignTokens.colorListIconSlate),
      'files' => (LucideIcons.folder, DesignTokens.colorListIconAmber),
      'wirelessPairing' => (LucideIcons.wifi, DesignTokens.colorListIconBlue),
      'screen' => (LucideIcons.monitor, DesignTokens.colorListIconPurple),
      'clipboard' => (LucideIcons.clipboard, DesignTokens.colorListIconMint),
      'apps' => (LucideIcons.layoutGrid, DesignTokens.colorListIconCoral),
      'audio' => (LucideIcons.volume2, DesignTokens.colorListIconPurple),
      _ => (LucideIcons.circleHelp, DesignTokens.colorListIconSlate),
    };
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListIconBadge(icon: icon, backgroundColor: color),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value(capability, 'name', value(capability, 'id')),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                Text(
                  statusText(value(capability, 'status')),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (value(capability, 'reason').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: DesignTokens.spacingXs),
                    child: Text(value(capability, 'reason')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
