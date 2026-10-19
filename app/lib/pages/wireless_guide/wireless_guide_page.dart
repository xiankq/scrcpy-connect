import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';

import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class WirelessGuidePage extends StatelessWidget {
  const WirelessGuidePage({
    super.key,
    required this.controller,
    this.deviceId,
    this.address = '',
  });
  final AppController controller;
  final String? deviceId;
  final String address;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '开启无线调试',
    child: GroupedListView(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      children: [
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: FeatureIcon(
            LucideIcons.wifi,
            size: DesignTokens.componentFeatureIconSize,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        Text('在被控手机上操作', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: DesignTokens.spacingMd),
        for (final entry in const [
          ('1', '开启开发者选项', '设置 → 关于手机，连续点击版本号；具体入口可能因系统不同。'),
          ('2', '打开无线调试', '设置 → 开发者选项 → 无线调试。让两台设备处于可互相访问的网络。'),
          ('3', '选择配对方式', '点击“使用配对码配对设备”，将地址、配对端口和六位配对码填写到下一页。'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: DesignTokens.spacingSm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: Text(entry.$1),
                ),
                const SizedBox(width: DesignTokens.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: DesignTokens.spacingTight),
                      Text(
                        entry.$3,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: DesignTokens.spacingMd),
        FilledButton(
          onPressed: () => ConnectionFormRoute(
            pairing: true,
            address: address,
            deviceId: deviceId,
          ).push<void>(context),
          child: const Text('使用配对码'),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        OutlinedButton(
          onPressed: () => QrPairRoute().push<void>(context),
          child: const Text('让被控手机扫码配对'),
        ),
        const SectionTitle('旧版 IP 与端口连接'),
        const Text('已通过 USB 授权并开启 TCP 的设备，可直接填写 IP 地址与端口。'),
        const SizedBox(height: DesignTokens.spacingSm),
        OutlinedButton(
          onPressed: () => ConnectionFormRoute(
            address: address,
            deviceId: deviceId,
            transport: ConnectionTransport.tcp,
          ).push<void>(context),
          child: const Text('使用 IP 与端口连接'),
        ),
        const SectionTitle('没有无线调试？'),
        const Text('较旧系统需要先通过 USB 完成授权。连接成功后，可检查该设备是否支持切换到无线。'),
        const SizedBox(height: DesignTokens.spacingSm),
        TextButton(
          onPressed: () => UsbGuideRoute().push<void>(context),
          child: const Text('使用 USB 连接'),
        ),
      ],
    ),
  );
}
