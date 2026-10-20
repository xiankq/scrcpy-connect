import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_access.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class DeviceConvertIpPage extends HookWidget {
  const DeviceConvertIpPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) {
    final form = useMemoized(GlobalKey<FormState>.new);
    final host = useTextEditingController(
      text: device['transport'] == 'usb' ? '' : value(device, 'address'),
    );
    final port = useTextEditingController(text: '5555');
    final busy = useState(false);
    final error = useState<String?>(null);
    final done = useState(false);
    return PageFrame(
      title: '转为 IP 连接',
      child: ConnectionContent(
        child: GroupedListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            ContentPanel(
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '切换可能中断当前会话。仅在可信网络使用。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: DesignTokens.spacingMd),
                    TextFormField(
                      controller: host,
                      enabled: !busy.value,
                      validator: validateAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: '手机网络地址'),
                    ),
                    const SizedBox(height: DesignTokens.spacingMd),
                    TextFormField(
                      controller: port,
                      enabled: !busy.value,
                      validator: validatePort,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '连接端口'),
                    ),
                    if (error.value != null) StateNote(error.value!),
                    if (done.value) const StateNote('已转为 IP 连接'),
                    const SizedBox(height: DesignTokens.spacingMd),
                    FilledButton(
                      onPressed: busy.value
                          ? null
                          : () async {
                              if (!form.currentState!.validate()) return;
                              final current = controller.currentDevice(device);
                              if (current['status'] != 'connected') {
                                await offerDeviceConnection(
                                  context,
                                  controller,
                                  current,
                                );
                                return;
                              }
                              final address = host.text.trim();
                              final parsedPort = int.parse(port.text.trim());
                              if (!await confirmConnectionChange(
                                    context,
                                    '切换并连接？',
                                    '将通过当前连接启用 IP 调试，再连接 $address 的 $parsedPort 端口。当前会话可能中断；手机可能要求重新授权。连接验证失败会保留真实失败状态。',
                                    action: '切换并连接',
                                  ) ||
                                  !context.mounted) {
                                return;
                              }
                              busy.value = true;
                              error.value = null;
                              done.value = false;
                              try {
                                final result = await controller.request(
                                  'devices.wireless',
                                  {
                                    'deviceId': device['id'],
                                    'address': address,
                                    'port': parsedPort,
                                  },
                                );
                                if (result['enabled'] != true ||
                                    result['connected'] != true ||
                                    result['deviceId'] != device['id']) {
                                  throw const RequestFailure(
                                    'ip_switch_unverified',
                                    '尚未验证 IP 连接，请检查设备连接状态。',
                                  );
                                }
                                await controller.refreshDevices();
                                if (context.mounted) done.value = true;
                              } catch (failure) {
                                await controller.refreshDevices();
                                if (context.mounted) error.value = '$failure';
                              } finally {
                                if (context.mounted) busy.value = false;
                              }
                            },
                      child: Text(busy.value ? '正在切换…' : '切换并连接'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
