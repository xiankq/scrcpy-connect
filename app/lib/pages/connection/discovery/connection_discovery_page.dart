import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/services/connection/connection_validation.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DiscoveryPage extends HookWidget {
  const DiscoveryPage({
    super.key,
    required this.controller,
    this.returnSelection = false,
  });
  final AppController controller;
  final bool returnSelection;

  @override
  Widget build(BuildContext context) {
    final revision = useState(0);
    return PageFrame(
      title: '发现设备',
      actions: [
        GlassActionIcon(
          onPressed: () => revision.value++,
          tooltip: '刷新',
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
      child: ConnectionContent(
        child: CommandView(
          controller: controller,
          command: 'devices.discover',
          refreshKey: revision.value,
          emptyTitle: '暂时无法发现设备',
          builder: (context, data, refresh) {
            final list = objects(data['devices']);
            if (list.isEmpty) {
              return GroupedListView(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                children: [
                  EmptyContent(
                    icon: LucideIcons.radar,
                    title: '未发现设备',
                    message: '检查手机无线调试与网络后重新查找。',
                    action: FilledButton(
                      onPressed: refresh,
                      child: const Text('重新查找'),
                    ),
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
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _endpointLabel(endpoint),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        pairingService
                            ? '等待配对'
                            : d['trusted'] == true
                            ? '已有配对信任'
                            : '需确认授权',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  onTap: () {
                    if (returnSelection) {
                      Navigator.of(context)
                          .pop(<String, dynamic>{'service': d});
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
}

String _endpointLabel(Json endpoint) {
  final address = value(endpoint, 'address');
  final port = value(endpoint, 'port');
  if (address.isEmpty || port.isEmpty) return '端点未获取';
  final host = address.contains(':') && !address.startsWith('[')
      ? '[$address]'
      : address;
  return '$host:$port';
}
