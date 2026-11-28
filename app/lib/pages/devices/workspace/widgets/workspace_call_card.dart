import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

class WorkspaceCallCard extends ConsumerWidget {
  const WorkspaceCallCard({super.key, required this.device});
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = device.id;
    final online = device.status == DeviceConnectionStatus.connected;
    final query = online ? ref.watch(deviceCallsSnapshotProvider(id)) : null;
    final data = query?.asData?.value;
    final call = data?.verified == true && query?.hasError != true
        ? data!.calls
              .where(
                (call) => switch (call.state) {
                  .ringing || .active || .dialing || .connecting => true,
                  .unknown => false,
                },
              )
              .firstOrNull
        : null;
    if (call == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spacingMd),
      child: SettingsGroup(
        children: [
          ActionRow(
            icon: LucideIcons.phone,
            color: FunctionTone.connection,
            title: call.aggregate
                ? '来电者未知'
                : call.name ?? call.number ?? '来电者未知',
            subtitle:
                '${deviceName(device)} · ${statusText(call.state.name)}\n声音仍在手机',
            onTap: () => CallsRoute(deviceId: id).push<void>(context),
          ),
        ],
      ),
    );
  }
}
