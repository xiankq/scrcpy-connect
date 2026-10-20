import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

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
    title: '附近设备',
    actions: [
      GlassActionIcon(
        onPressed: () => chooseMode(context, 'ip'),
        tooltip: 'IP连接',
        icon: const Icon(LucideIcons.plus),
      ),
    ],
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
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.wifiOff,
                          color: ConnectTokens.amber,
                          size: 32,
                        ),
                        const SizedBox(width: DesignTokens.spacingSm),
                        Expanded(
                          child: Text(
                            '没有发现可连接的手机',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spacingMd),
                    const Text('检查被控手机是否开启无线调试。网络隔离可能影响发现，也可以手动输入可达地址。'),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.spacingMd),
              FilledButton(onPressed: refresh, child: const Text('重新查找')),
              const SizedBox(height: DesignTokens.spacingMd),
              OutlinedButton(
                onPressed: () => chooseMode(context, 'ip'),
                child: const Text('IP连接'),
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
        return GroupedListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            const StateNote('发现设备不表示已经获得授权。请核对设备并完成配对。'),
            ...list.map((d) {
              final endpoints = objects(d['endpoints']);
              final endpoint = endpoints.isEmpty ? d : endpoints.first;
              final pairingService = d['kind'] == 'pairing';
              return ListTile(
                leading: const Icon(LucideIcons.smartphone),
                title: Text(
                  value(d, 'name', value(d, 'instance', '附近 Android 设备')),
                ),
                subtitle: Text(
                  pairingService
                      ? '等待配对'
                      : d['trusted'] == true
                      ? '已有配对信任，仍需检查连接'
                      : '需要核对授权',
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
            }),
          ],
        );
      },
    ),
  );
}
