import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/device_summary.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

class DeviceHero extends HookConsumerWidget {
  const DeviceHero({super.key, required this.device});
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(deviceConnectionsProvider);
    final busy = useValueNotifier(false, [connections, device.id]);
    useListenable(busy);
    final currentBusy = useRef(busy);
    currentBusy.value = busy;
    bool isCurrent() =>
        context.mounted &&
        identical(currentBusy.value, busy) &&
        identical(connections, ref.read(deviceConnectionsProvider));
    final online = device.status == DeviceConnectionStatus.connected;
    final unauthorized = device.status == DeviceConnectionStatus.unauthorized;
    final connecting = busy.value || deviceConnectionInProgress(device);
    final id = device.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContentPanel(
          child: InkWell(
            onTap: () => DeviceDetailsRoute(deviceId: id).push<void>(context),
            borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
            child: Row(
              children: [
                Expanded(
                  child: DeviceSummary(device: device, connecting: busy.value),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  size: DesignTokens.componentIconSmallSize,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        FilledButton.icon(
          onPressed: connecting
              ? null
              : () async {
                  if (online) {
                    await openRemoteRoute(context, deviceId: id);
                  } else if (device.transport == DeviceTransport.usb) {
                    await UsbGuideRoute(deviceId: id).push<void>(context);
                  } else if (unauthorized) {
                    await AddDeviceRoute(deviceId: id).push<void>(context);
                  } else {
                    busy.value = true;
                    try {
                      await connections.connectDevice(id);
                    } catch (error) {
                      if (context.mounted && isCurrent()) {
                        feedback(context, '$error');
                      }
                    }
                    if (!isCurrent()) return;
                    await ref.read(deviceListProvider.notifier).refresh();
                    if (isCurrent()) busy.value = false;
                  }
                },
          icon: Icon(
            online
                ? LucideIcons.smartphone
                : unauthorized
                ? LucideIcons.shieldCheck
                : LucideIcons.link,
            size: DesignTokens.componentIconActionSize,
          ),
          label: Text(
            connecting
                ? '正在连接'
                : online
                ? '打开手机屏幕'
                : unauthorized
                ? '重新授权'
                : '连接手机',
          ),
        ),
      ],
    );
  }
}
