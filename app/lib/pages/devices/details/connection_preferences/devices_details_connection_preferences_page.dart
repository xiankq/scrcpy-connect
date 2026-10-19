import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
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
    child: GroupedListView(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      children: [
        const StateNote('切换连接路径可能重建会话。未确认结果的发送、删除与回复不会自动重试。'),
        ActionRow(
          icon: LucideIcons.wifi,
          title: '编辑连接地址',

          onTap: () => ConnectionFormRoute(
            address: value(device, 'address'),
            deviceId: value(device, 'id'),
          ).push<void>(context),
        ),
        ActionRow(
          icon: LucideIcons.usb,
          title: '使用 USB 连接',
          onTap: () => UsbGuideRoute().push<void>(context),
        ),
        ActionRow(
          icon: LucideIcons.radio,
          title: '检查 USB 转无线',

          onTap: () async {
            final result = await perform(
              context,
              controller,
              'devices.wireless',
              {'deviceId': device['id']},
            );
            if (result != null && context.mounted) {
              feedback(context, value(result, 'message', '已完成检查，请确认实际连接状态'));
            }
          },
        ),
      ],
    ),
  );
}
