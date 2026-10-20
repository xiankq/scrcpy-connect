import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';

import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DiscoveryPage extends StatelessWidget {
  const DiscoveryPage({
    super.key,
    required this.controller,
    this.returnSelection = false,
  });
  final AppController controller;
  final bool returnSelection;

  void chooseMode(BuildContext context, String mode) {
    if (returnSelection) {
      Navigator.of(context).pop(<String, dynamic>{'mode': mode});
    } else if (mode == 'usb') {
      UsbGuideRoute().push<void>(context);
    } else if (mode == 'pairing') {
      WirelessGuideRoute().push<void>(context);
    } else {
      const ConnectionFormRoute(transport: ConnectionTransport.tcp)
          .push<void>(context);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '发现设备',
    actions: [
      GlassActionIcon(
        onPressed: () => chooseMode(context, 'ip'),
        tooltip: 'IP 连接',
        icon: const Icon(LucideIcons.plus),
      ),
    ],
    child: ConnectionContent(
      child: CommandView(
        controller: controller,
        command: 'devices.discover',
        emptyTitle: '暂时无法发现设备',
        builder: (context, data, refresh) {
          final list = objects(data['devices']);
          if (list.isEmpty) {
            return GroupedListView(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              children: [
                ContentPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '未发现设备',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: DesignTokens.spacingXs),
                      Text(
                        '检查手机无线调试与网络，或改用其他连接方式。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingMd),
                FilledButton(onPressed: refresh, child: const Text('重新查找')),
                const SizedBox(height: DesignTokens.spacingMd),
                OutlinedButton(
                  onPressed: () => chooseMode(context, 'ip'),
                  child: const Text('IP 连接'),
                ),
                const SizedBox(height: DesignTokens.spacingMd),
                ActionRow(
                  icon: LucideIcons.info,
                  title: '使用无线配对码',
                  onTap: () => chooseMode(context, 'pairing'),
                ),
                ActionRow(
                  icon: LucideIcons.usb,
                  title: '改用 USB',
                  onTap: () => chooseMode(context, 'usb'),
                ),
              ],
            );
          }
          return GroupedListView.builder(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final d = list[index];
              final endpoints = objects(d['endpoints']);
              final endpoint = endpoints.isEmpty ? d : endpoints.first;
              final pairingService = d['kind'] == 'pairing';
              return ListTile(
                leading: const Icon(LucideIcons.smartphone),
                title: Text(
                  value(d, 'name', value(d, 'instance', '附近 Android 设备')),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                subtitle: Text(
                  pairingService
                      ? '等待配对'
                      : d['trusted'] == true
                      ? '已配对，检查连接'
                      : '需确认授权',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                onTap: () {
                  if (returnSelection) {
                    Navigator.of(context).pop(<String, dynamic>{'service': d});
                    return;
                  }
                  ConnectionFormRoute(
                    pairing: pairingService,
                    transport: pairingService
                        ? null
                        : d['kind'] == 'tcp'
                        ? ConnectionTransport.tcp
                        : ConnectionTransport.tls,
                    address: value(endpoint, 'address'),
                    port: value(endpoint, 'port'),
                    deviceId: responseDeviceId(d),
                  ).push<void>(context);
                },
              );
            },
          );
        },
      ),
    ),
  );
}
