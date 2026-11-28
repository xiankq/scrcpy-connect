import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_assessment.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
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
        final colors = AppColors.of(context);
        if (capabilities.isEmpty) {
          return const StateNote('请先连接手机，再检查哪些功能可用。');
        }
        // 功能检查行（Ardot 诊断行 37:925）：功能名、原因副标题，行尾状态文字加状态图形。
        return SettingsGroup(
          children: [
            for (final cap in capabilities)
              AppListRow(
                title: Text(_featureName(cap.feature)),
                subtitle: cap.reason.isEmpty ? null : Text(cap.reason),
                value: _statusText(cap.status),
                trailing: Icon(
                  switch (cap.status) {
                    .available => LucideIcons.circleCheck,
                    .unavailable => LucideIcons.circleX,
                    .limited || .needsSetup => LucideIcons.triangleAlert,
                    _ => LucideIcons.circleDashed,
                  },
                  size: DesignTokens.componentSectionGlyphSize,
                  color: switch (cap.status) {
                    .available => colors.success,
                    .unavailable => colors.error,
                    .limited || .needsSetup => colors.warning,
                    _ => colors.textSecondary,
                  },
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
  .unverified => '待检查',
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
