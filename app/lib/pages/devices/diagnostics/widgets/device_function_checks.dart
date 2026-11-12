import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_assessment.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class DeviceFunctionChecks extends ConsumerWidget {
  const DeviceFunctionChecks({
    super.key,
    required this.device,
    this.refreshKey = 0,
  });
  final DeviceSnapshot device;
  final int refreshKey;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = deviceCapabilitiesProvider(
      device.id,
      revision: refreshKey,
    );
    final query = ref.watch(provider);
    return AsyncContent(
      loading: query.isLoading,
      data: query.value,
      error: query.error,
      onRefresh: () => ref.invalidate(provider),
      emptyTitle: '暂时无法检查功能',
      builder: (context, data) {
        final capabilities = data.capabilities;
        return SettingsGroup(
          children: [
            if (capabilities.isEmpty) const StateNote('尚未检查这台设备的功能，请连接后重新检查。'),
            for (final cap in capabilities)
              ListTile(
                leading: ListIconBadge(
                  icon: cap.status == DeviceFeatureStatus.available
                      ? LucideIcons.circleCheck
                      : LucideIcons.circleAlert,
                  backgroundColor: cap.status == DeviceFeatureStatus.available
                      ? DesignTokens.colorListIconMint
                      : DesignTokens.colorListIconAmber,
                ),
                title: Text(
                  '${_featureName(cap.feature)} · ${_statusText(cap.status)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                subtitle: cap.reason.isEmpty
                    ? null
                    : Text(
                        cap.reason,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
          ],
        );
      },
    );
  }
}

String _statusText(DeviceFeatureStatus status) => switch (status) {
  .available => '可用',
  .limited => '受限',
  .unavailable => '不可用',
  .needsSetup => '需要设置',
  .unknown => '尚未检查',
  .stopped => '已停止',
  .unverified => '状态待核验',
};

String _featureName(DeviceFeature feature) => switch (feature) {
  .shell => '设备授权',
  .files => '文件',
  .wirelessPairing => '无线连接',
  .screen => '手机画面',
  .clipboard => '文字剪贴板',
  .apps => '手机应用',
  .audio => '设备声音',
  .notifications => '实时通知',
  .calls => '电话',
  .background => '后台保持',
};
