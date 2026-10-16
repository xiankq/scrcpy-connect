import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
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
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const FeatureIcon(LucideIcons.wifi, size: 72),
        const SizedBox(height: 24),
        Text('在被控手机上操作', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        for (final entry in const [
          ('1', '开启开发者选项', '设置 → 关于手机，连续点击版本号；具体入口可能因系统不同。'),
          ('2', '打开无线调试', '设置 → 开发者选项 → 无线调试。让两台设备处于可互相访问的网络。'),
          ('3', '选择配对方式', '点击“使用配对码配对设备”，将地址、配对端口和六位配对码填写到下一页。'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: Text(entry.$1),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
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
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => ConnectionFormRoute(
            pairing: true,
            address: address,
            deviceId: deviceId,
          ).push<void>(context),
          child: const Text('使用配对码'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => QrPairRoute().push<void>(context),
          child: const Text('让被控手机扫码配对'),
        ),
        const SectionTitle('没有无线调试？'),
        const Text('较旧系统需要先通过 USB 完成授权。连接成功后，可检查该设备是否支持切换到无线。'),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => UsbGuideRoute().push<void>(context),
          child: const Text('使用 USB 连接'),
        ),
      ],
    ),
  );
}
