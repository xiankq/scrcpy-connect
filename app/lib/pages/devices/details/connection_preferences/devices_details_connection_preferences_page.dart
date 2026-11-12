import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';

class DeviceConnectionPreferencesPage extends HookConsumerWidget {
  const DeviceConnectionPreferencesPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppNotifier controller;
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      appProvider.select(
        (state) =>
            state.devices.where((entry) => entry.id == device.id).firstOrNull,
      ),
    );
    return ConnectionFormPage(
      key: ValueKey(device.id),
      controller: controller,
      configuring: true,
      additionalContent:
          current?.status == DeviceConnectionStatus.connected &&
              current?.transport != DeviceTransport.tcp
          ? Padding(
              padding: const EdgeInsets.only(top: DesignTokens.spacingLg),
              child: ContentPanel(
                child: ActionRow(
                  icon: LucideIcons.wifi,
                  title: '转为 IP 连接',
                  onTap: () =>
                      DeviceIpRoute(deviceId: device.id).push<void>(context),
                ),
              ),
            )
          : null,
      deviceId: device.id,
      initialMode: device.transport == DeviceTransport.usb
          ? AddDeviceMode.usb
          : AddDeviceMode.ip,
      address: device.transport == DeviceTransport.usb
          ? ''
          : (device.address ?? ''),
      port: device.port == 0 ? '' : (device.port?.toString() ?? ''),
      transport: connectionTransportForRecord(device),
    );
  }
}
