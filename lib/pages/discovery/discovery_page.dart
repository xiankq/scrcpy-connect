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
  const DiscoveryPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '附近设备',
    actions: [
      IconButton(
        onPressed: () => ConnectionFormRoute().push<void>(context),
        tooltip: '手动连接',
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
          return EmptyContent(
            icon: LucideIcons.radar,
            title: '未发现设备',
            message: '确认被控手机已打开无线调试，并处于可达网络。没有发现设备不代表无法连接。',
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(onPressed: refresh, child: const Text('重新发现')),
                TextButton(
                  onPressed: () => ConnectionFormRoute().push<void>(context),
                  child: const Text('手动填写地址'),
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const StateNote('发现设备不表示已经获得授权。请核对设备并完成配对。'),
            ...list.map((d) {
              final endpoints = objects(d['endpoints']);
              final endpoint = endpoints.isEmpty ? d : endpoints.first;
              final trusted = d['trusted'] == true || d['paired'] == true;
              final pairingService = d['kind'] == 'pairing';
              return ActionRow(
                icon: LucideIcons.smartphone,
                title: value(d, 'name', value(d, 'instance', '附近 Android 设备')),
                subtitle:
                    '${value(endpoint, 'address')}:${value(endpoint, 'port')} · ${trusted
                        ? '已有信任'
                        : pairingService
                        ? '等待配对'
                        : '等待核验授权'}',
                onTap: () => ConnectionFormRoute(
                  pairing: pairingService,
                  transport: pairingService
                      ? null
                      : d['kind'] == 'tcp'
                      ? ConnectionTransport.tcp
                      : ConnectionTransport.tls,
                  address: value(endpoint, 'address'),
                  port: value(endpoint, 'port'),
                  deviceId: responseDeviceId(d),
                ).push<void>(context),
              );
            }),
          ],
        );
      },
    ),
  );
}
