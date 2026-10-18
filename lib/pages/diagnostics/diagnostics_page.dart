import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '连接诊断',
    child: CommandView(
      controller: controller,
      command: 'device.diagnose',
      params: {'deviceId': device['id']},
      emptyTitle: '暂时无法完成诊断',
      builder: (context, data, refresh) {
        final current = data['device'] is Map<Object?, Object?>
            ? jsonObject(data['device'])
            : device;
        final connected = data['connected'];
        final unauthorized = current['status'] == 'unauthorized';
        final usb = current['transport'] == 'usb';
        final reachable = data['tcpReachable'];
        final identity = data['identityPresent'];
        final checks = <Json>[
          {
            'name': connected == true
                ? '设备连接正常'
                : unauthorized
                ? '需要重新授权'
                : connected == false
                ? '设备尚未连接'
                : '连接状态尚未确认',
            'ok': connected == true,
            'message': connected == true
                ? '当前已建立授权连接。各项功能的支持情况仍需分别检查。'
                : unauthorized
                ? '请在被控手机重新确认调试授权，再检查连接。'
                : '请结合下方网络或 USB 检查继续连接；未连接不等于授权已失效。',
          },
          if (usb)
            {
              'name': data['usbBackendAvailable'] == false
                  ? '当前平台无法使用 USB'
                  : connected == true
                  ? 'USB 连接已建立'
                  : 'USB 连接需要检查',
              'ok': connected == true,
              'message': data['usbBackendAvailable'] == false
                  ? '请改用无线连接；被控手机仍需完成相应的调试设置与授权。'
                  : '检查数据线与 USB 主机角色，并在本机允许 USB 访问、在被控手机允许调试授权。',
            }
          else
            {
              'name': reachable == true
                  ? '网络地址可达'
                  : reachable == false
                  ? '无法访问设备地址'
                  : '网络路径尚未检查',
              'ok': reachable == true,
              'message': reachable == true
                  ? '地址可以访问；这不代表配对信任或设备连接已经建立。'
                  : reachable == false
                  ? '确认两台设备的网络或已有 VPN 路径，并核对被控手机无线调试主页面的地址与连接端口。'
                  : '请核对设备地址与连接端口，然后重新检查。',
            },
          {
            'name': identity == true
                ? '本机授权身份已就绪'
                : identity == false
                ? '本机授权身份不可用'
                : '本机授权身份尚未确认',
            'ok': identity == true,
            'message': identity == true
                ? '本机保有授权身份；是否仍受被控手机信任，以实际授权连接为准。'
                : '请重新检查本机状态，并在被控手机完成需要的授权。恢复设备名称不会恢复授权。',
          },
        ];
        return GroupedListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            if (!usb && value(current, 'address').isNotEmpty)
              StateNote(
                '当前地址：${value(current, 'address')} · 连接端口：${value(current, 'port', '未记录')}',
              ),
            for (final check in checks)
              ActionRow(
                icon: check['ok'] == true
                    ? LucideIcons.circleCheck
                    : LucideIcons.circleAlert,
                title: value(check, 'name'),

                color: check['ok'] == true
                    ? ConnectTokens.mint
                    : ConnectTokens.amber,
              ),
            for (final check in checks.where((check) => check['ok'] != true))
              StateNote(value(check, 'message')),
            if (value(current, 'reason').isNotEmpty)
              StateNote(value(current, 'reason')),
            for (final note in strings(data['notes'])) StateNote(note),
            const SizedBox(height: DesignTokens.spacingMd),
            FilledButton(onPressed: refresh, child: const Text('重新检查')),
            if (unauthorized)
              TextButton(
                onPressed: () => AddDeviceRoute(
                  deviceId: value(current, 'id', value(device, 'id')),
                ).push<void>(context),
                child: const Text('重新授权'),
              ),
            const SizedBox(height: DesignTokens.spacingXs),
            OutlinedButton(
              onPressed: () => ConnectionFormRoute(
                address: value(current, 'address'),
                port: current['port'] == 0 ? '' : value(current, 'port'),
                deviceId: value(current, 'id', value(device, 'id')),
              ).push<void>(context),
              child: const Text('编辑地址与端口'),
            ),
            if (data['usbBackendAvailable'] != false)
              TextButton(
                onPressed: () => UsbGuideRoute().push<void>(context),
                child: const Text('改用 USB'),
              )
            else
              TextButton(
                onPressed: () => WirelessGuideRoute().push<void>(context),
                child: const Text('改用无线连接'),
              ),
          ],
        );
      },
    ),
  );
}
