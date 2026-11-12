import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/core/devices/device_discovery_provider.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

class DeviceDiscoveryPage extends ConsumerWidget {
  const DeviceDiscoveryPage({super.key, this.returnSelection = false});
  final bool returnSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deviceDiscoveryProvider);
    void refresh() => ref.invalidate(deviceDiscoveryProvider);
    return PageFrame(
      title: '发现设备',
      actions: [
        GlassActionIcon(
          onPressed: refresh,
          tooltip: '刷新',
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
      child: ConnectionContent(
        child: AsyncContent<List<DiscoveredDevice>>(
          loading: state.isLoading,
          data: state.value,
          error: state.error,
          onRefresh: refresh,
          emptyTitle: '暂时无法发现设备',
          builder: (context, list) {
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
                final endpoint = d.endpoints.firstOrNull;
                final pairingService = d.kind == .pairing;
                return ListTile(
                  leading: const Icon(LucideIcons.smartphone),
                  title: Text(
                    d.instance.isEmpty ? '附近 Android 设备' : d.instance,
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
                            : d.trusted
                            ? '已有配对信任'
                            : '需确认授权',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  onTap: () {
                    if (returnSelection) {
                      Navigator.of(context).pop(d);
                      return;
                    }
                    ConnectionFormRoute(
                      pairing: pairingService,
                      transport: pairingService
                          ? null
                          : d.kind == .tcp
                          ? ConnectionTransport.tcp
                          : ConnectionTransport.tls,
                      address: endpoint?.address ?? '',
                      port: endpoint?.port.toString() ?? '',
                      deviceId: d.deviceId,
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

String _endpointLabel(DiscoveredEndpoint? endpoint) {
  if (endpoint == null) return '端点未获取';
  final (:address, :port) = endpoint;
  final host = address.contains(':') && !address.startsWith('[')
      ? '[$address]'
      : address;
  return '$host:$port';
}
