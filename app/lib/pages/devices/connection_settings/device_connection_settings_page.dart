import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/connection_form_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

class DeviceConnectionSettingsPage extends HookConsumerWidget {
  const DeviceConnectionSettingsPage({super.key, required this.device});
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      deviceListProvider.select(
        (state) =>
            state.devices.where((entry) => entry.id == device.id).firstOrNull,
      ),
    );
    return ConnectionFormPage(
      key: ValueKey(device.id),
      configuring: true,
      additionalContent:
          current?.status == DeviceConnectionStatus.connected &&
              current?.transport != DeviceTransport.tcp
          ? Padding(
              padding: const EdgeInsets.only(
                top: DesignTokens.componentListSectionGap,
              ),
              child: SettingsGroup(
                children: [
                  ActionRow(
                    icon: AppIcons.connectionIp,
                    color: FunctionTone.device,
                    title: '转为 IP 连接',
                    onTap: () =>
                        DeviceIpRoute(deviceId: device.id).push<void>(context),
                  ),
                ],
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
