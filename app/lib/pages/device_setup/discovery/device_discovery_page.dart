import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/core/devices/device_discovery_provider.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
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
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      child: ConnectionContent(
        child: AsyncContent<List<DiscoveredDevice>>(
          loadingPlaceholder: const GroupedListView(
            padding: _listPadding,
            children: [
              SkeletonRows(
                cardRadius: DesignTokens.componentListGroupRounded,
                trailing: true,
              ),
            ],
          ),
          loading: state.isLoading,
          data: state.value,
          error: state.error,
          onRefresh: refresh,
          emptyTitle: '暂时无法发现设备',
          failure: '请让手机和本机连着同一 Wi-Fi，并打开手机的无线调试。',
          builder: (context, list) {
            if (list.isEmpty) {
              return GroupedListView(
                padding: _listPadding,
                children: [
                  EmptyContent(
                    icon: AppIcons.connectionDiscovery,
                    title: '未发现设备',
                    message: '检查手机无线调试与网络后重新查找。',
                    action: AppButton(
                      role: AppButtonRole.primary,
                      onPressed: refresh,
                      label: '重新查找',
                    ),
                  ),
                ],
              );
            }
            return GroupedListView(
              padding: _listPadding,
              children: [
                SettingsGroup(
                  children: [
                    for (final d in list)
                      _DiscoveredRow(
                        device: d,
                        onTap: () {
                          if (returnSelection) {
                            Navigator.of(context).pop(d);
                            return;
                          }
                          final endpoint = d.endpoints.firstOrNull;
                          final pairingService = d.kind == .pairing;
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
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 正文从页头下 12 开始，左右 16（design.md「页面结构」）。
const _listPadding = EdgeInsets.fromLTRB(
  DesignTokens.componentPagePadding,
  DesignTokens.spacingMd,
  DesignTokens.componentPagePadding,
  DesignTokens.componentPagePadding,
);

/// 附近设备行（Ardot A1 2:942）：设备色块、名称与端点，行尾为配对状态和箭头。
class _DiscoveredRow extends StatelessWidget implements GroupedRow {
  const _DiscoveredRow({required this.device, required this.onTap});

  final DiscoveredDevice device;
  final VoidCallback onTap;

  @override
  double get separatorIndent => tileRowSeparatorIndent;

  @override
  Widget build(BuildContext context) => AppListRow(
    leading: const ListIconBadge(
      icon: LucideIcons.smartphone,
      backgroundColor: FunctionTone.device,
    ),
    title: Text(device.instance.isEmpty ? '附近 Android 设备' : device.instance),
    subtitle: Text(_endpointLabel(device.endpoints.firstOrNull)),
    value: device.kind == .pairing
        ? '等待配对'
        : device.trusted
        ? '已有配对信任'
        : '需确认授权',
    chevron: true,
    onTap: onTap,
  );
}

String _endpointLabel(DiscoveredEndpoint? endpoint) {
  if (endpoint == null) return '端点未获取';
  final (:address, :port) = endpoint;
  final host = address.contains(':') && !address.startsWith('[')
      ? '[$address]'
      : address;
  return '$host:$port';
}
