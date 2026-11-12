import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';

class WorkspaceCallCard extends ConsumerWidget {
  const WorkspaceCallCard({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppNotifier controller;
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = device.id;
    final online = device.status == DeviceConnectionStatus.connected;
    final query = online ? ref.watch(deviceCallsProvider(id)) : null;
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
      child: ContentPanel(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const ListIconBadge(
            icon: LucideIcons.phone,
            backgroundColor: DesignTokens.colorListIconMint,
          ),
          title: Text(
            call.aggregate ? '来电者未知' : call.name ?? call.number ?? '来电者未知',
          ),
          subtitle: Text(
            '${deviceName(device)} · ${statusText(call.state.name)}\n声音仍在手机',
          ),
          trailing: const Icon(LucideIcons.chevronRight),
          onTap: () => CallsRoute(deviceId: id).push<void>(context),
        ),
      ),
    );
  }
}
