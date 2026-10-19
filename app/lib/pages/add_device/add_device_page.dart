import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AddDevicePage extends HookWidget {
  const AddDevicePage({
    super.key,
    required this.controller,
    this.initialDevice,
  });
  final AppController controller;
  final Json? initialDevice;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: initialDevice == null ? '添加设备' : '重新授权',
    child: GroupedListView(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      children: [
        Text(
          initialDevice == null
              ? '在另一台 Android 手机上完成调试设置与授权。本机无需开启调试。'
              : '${deviceName(initialDevice!)} 的旧记录不代表当前授权。请在被控手机重新确认。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: DesignTokens.spacingLg),
        ContentPanel(
          child: Column(
            children: [
              ActionRow(
                icon: LucideIcons.wifi,
                title: '无线连接',
                onTap: () => WirelessGuideRoute(
                  address: value(initialDevice ?? {}, 'address'),
                  deviceId: responseDeviceId(initialDevice),
                ).push<void>(context),
              ),
              ActionRow(
                icon: LucideIcons.usb,
                title: 'USB 数据线',
                onTap: () => UsbGuideRoute().push<void>(context),
              ),
            ],
          ),
        ),
        const SectionTitle('已有连接信息'),
        ActionRow(
          icon: LucideIcons.radar,
          title: '发现附近设备',

          onTap: () => DiscoveryRoute().push<void>(context),
        ),
        ActionRow(
          icon: LucideIcons.network,
          title: '手动填写地址',

          onTap: () => ConnectionFormRoute(
            address: value(initialDevice ?? {}, 'address'),
            deviceId: responseDeviceId(initialDevice),
          ).push<void>(context),
        ),
        const StateNote('仅连接你拥有或获准使用的手机。配对信任与当前设备连接分别建立。'),
      ],
    ),
  );
}
