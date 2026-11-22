import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/device_summary.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/devices/device_access.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

class DeviceHero extends HookConsumerWidget {
  const DeviceHero({super.key, required this.device, this.pane = false});
  final DeviceSnapshot device;
  final bool pane;

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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mainAction = FilledButton(
      onPressed: connecting
          ? busy.value && !deviceConnectionInProgress(device)
                ? null
                : () => stopDeviceConnection(context, ref, device)
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
                    feedback(
                      context,
                      failureMessage(error, fallback: '无法打开手机屏幕。请检查手机连接后重试。'),
                    );
                  }
                }
                if (!isCurrent()) return;
                await ref.read(deviceListProvider.notifier).refresh();
                if (isCurrent()) busy.value = false;
              }
            },
      child: Text(
        connecting
            ? '取消连接'
            : online
            ? '打开手机屏幕'
            : unauthorized
            ? '重新授权'
            : device.status == .failed
            ? '重试'
            : '连接',
      ),
    );
    final details = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      onPressed: () => DeviceDetailsRoute(deviceId: id).push<void>(context),
      child: const Text('设备详情'),
    );
    return Material(
      color: dark
          ? DesignTokens.componentDeviceHeroDarkBackgroundColor
          : DesignTokens.componentDeviceHeroBackgroundColor,
      borderRadius: BorderRadius.circular(
        DesignTokens.componentDeviceHeroRounded,
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DeviceSummary(device: device, connecting: busy.value, pane: pane),
            const SizedBox(height: DesignTokens.spacingMd),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                return constraints.maxWidth / scale < 240
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          mainAction,
                          const SizedBox(height: DesignTokens.spacingXs),
                          details,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(flex: 3, child: mainAction),
                          const SizedBox(width: DesignTokens.spacingXs),
                          Expanded(flex: 2, child: details),
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}
