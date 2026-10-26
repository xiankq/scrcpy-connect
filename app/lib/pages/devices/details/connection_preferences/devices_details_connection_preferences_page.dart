import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:design_system/design_system.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/services/connection/connection_validation.dart';

class DeviceConnectionPreferencesPage extends HookConsumerWidget {
  const DeviceConnectionPreferencesPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      appControllerProvider.select(
        (state) => state.devices
            .where((entry) => entry['id'] == device['id'])
            .firstOrNull,
      ),
    );
    return ConnectionFormPage(
      key: ValueKey(value(device, 'id')),
      controller: controller,
      configuring: true,
      additionalContent:
          current?['status'] == 'connected' && current?['transport'] != 'tcp'
          ? Padding(
              padding: const EdgeInsets.only(top: DesignTokens.spacingLg),
              child: ContentPanel(
                child: ActionRow(
                  icon: LucideIcons.wifi,
                  title: '转为 IP 连接',
                  onTap: () =>
                      DeviceIpRoute(deviceId: value(device, 'id'))
                          .push<void>(context),
                ),
              ),
            )
          : null,
      deviceId: value(device, 'id'),
      initialMode: device['transport'] == 'usb'
          ? AddDeviceMode.usb
          : AddDeviceMode.ip,
      address: device['transport'] == 'usb' ? '' : value(device, 'address'),
      port: device['port'] == 0 ? '' : value(device, 'port'),
      transport: connectionTransportForRecord(device),
    );
  }
}
