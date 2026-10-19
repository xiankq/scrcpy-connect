import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceHero extends HookConsumerWidget {
  const DeviceHero({super.key, required this.controller, required this.device});
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = device['status'] == 'connected';
    final id = value(device, 'id');
    final stream = useMemoized(
      () => controller.eventStream().where(
        (event) =>
            (value(event, 'type').startsWith('session.') &&
                event['type'] != 'session.frame' &&
                (event['deviceId'] == null || event['deviceId'] == id)) ||
            value(event, 'type').startsWith('state.'),
      ),
      [controller, id],
    );
    final event = useStream(stream);
    // Both are existing read-only queries. A failed query remains unknown;
    // it must never become a fabricated zero or hide the screen action.
    final future = useMemoized(
      () => Future.wait<Json?>([
        _read(controller, 'device.capabilities', id),
        _read(controller, 'session.list', id),
      ]),
      [controller, id, device['status'], event.data],
    );
    final result = useFuture(future, preserveState: false);
    final data = result.data;
    final capabilities = data == null ? null : data[0];
    final sessionData = data == null ? null : data[1];
    final available = objects(capabilities?['capabilities'])
        .where((item) => item['status'] == 'available')
        .length;
    final total = objects(capabilities?['capabilities']).length;
    final sessions = objects(sessionData?['sessions'])
        .where((item) => item['deviceId'] == id && item['status'] != 'stopped')
        .toList();
    final checking = result.connectionState != ConnectionState.done;
    final capabilityLabel = checking
        ? '正在检查功能'
        : capabilities == null || total == 0
        ? '功能状态待核验'
        : '$available / $total 项功能可用';
    final sessionLabel = checking
        ? '正在读取会话'
        : sessionData == null
        ? '会话状态待核验'
        : sessions.isEmpty
        ? '暂无已保留会话'
        : '${sessions.length} 个已保留会话';
    return ContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const DeviceIdentity(showcase: true),
              const SizedBox(width: DesignTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName(device),
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: DesignTokens.spacingXxs),
                    if (value(device, 'model').isNotEmpty) ...[
                      Text(
                        value(device, 'model'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: DesignTokens.spacingSm),
                    ],
                    Text(
                      deviceConnectionLabel(device),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          Divider(
            height: DesignTokens.spacingHairline,
            thickness: DesignTokens.spacingHairline,
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SummaryLine(
                  icon: LucideIcons.shieldCheck,
                  label: capabilityLabel,
                ),
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              Expanded(
                child: _SummaryLine(
                  icon: LucideIcons.panelsTopLeft,
                  label: sessionLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => online
                  ? openRemoteRoute(context, deviceId: id)
                  : AddDeviceRoute(deviceId: id).push<void>(context),
              icon: Icon(
                online ? LucideIcons.arrowUpRight : LucideIcons.link,
                size: DesignTokens.componentIconActionSize,
              ),
              label: Text(online ? '打开手机屏幕' : '恢复连接'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<Json?> _read(AppController controller, String command, String id) async {
  try {
    return await controller.request(command, {'deviceId': id});
  } catch (_) {
    return null;
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: DesignTokens.componentIconSmallSize,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: DesignTokens.spacingXs),
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}
