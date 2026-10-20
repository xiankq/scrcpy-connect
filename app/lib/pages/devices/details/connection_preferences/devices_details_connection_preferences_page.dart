import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:design_system/design_system.dart';

class DeviceConnectionPreferencesPage extends StatelessWidget {
  const DeviceConnectionPreferencesPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '连接偏好',
    child: ConnectionContent(
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          const StateNote('切换连接方式可能重建会话；未确认的操作不会自动重试。'),
          ActionRow(
            icon: LucideIcons.wifi,
            title: '编辑地址与端口',

            onTap: () => ConnectionFormRoute(
              address: value(device, 'address'),
              port: device['port'] == 0 ? '' : value(device, 'port'),
              deviceId: value(device, 'id'),
            ).push<void>(context),
          ),
          ActionRow(
            icon: LucideIcons.usb,
            title: '使用 USB 连接',
            onTap: () =>
                UsbGuideRoute(deviceId: value(device, 'id'))
                    .push<void>(context),
          ),
          ListTile(
            leading: const ListIconBadge(
              icon: LucideIcons.keyRound,
              backgroundColor: DesignTokens.colorListIconBlue,
            ),
            title: const Text('ADB 私钥'),
            subtitle: const Text('继承全局私钥或为此设备设置专用私钥。'),
            onTap: () =>
                DeviceIdentityRoute(deviceId: value(device, 'id'))
                    .push<void>(context),
          ),
          ListTile(
            leading: const ListIconBadge(
              icon: LucideIcons.radio,
              backgroundColor: DesignTokens.colorListIconBlue,
            ),
            title: const Text('转为 IP 连接'),
            subtitle: const Text('通过当前连接启用 IP 调试并验证新连接。'),
            onTap: () =>
                DeviceIpRoute(deviceId: value(device, 'id'))
                    .push<void>(context),
          ),
        ],
      ),
    ),
  );
}
