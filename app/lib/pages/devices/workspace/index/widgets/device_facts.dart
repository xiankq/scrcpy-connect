import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

/// The route already resolves device.info; these fields remain readable offline.
class DeviceFacts extends StatelessWidget {
  const DeviceFacts({super.key, required this.device});
  final Json device;

  @override
  Widget build(BuildContext context) => ContentPanel(
    child: Column(
      children: [
        for (final pair in [
          ('型号', value(device, 'model', '未获取')),
          ('Android 版本', value(device, 'androidVersion', '未获取')),
          (
            '连接方式',
            switch (value(device, 'transport')) {
              'usb' => 'USB 数据线',
              'tls' => '无线调试',
              'tcp' || 'wireless' => 'IP 地址',
              _ => '未获取',
            },
          ),
          ('地址', value(device, 'address', '未记录')),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: DesignTokens.spacingXs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    pair.$1,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: DesignTokens.spacingMd),
                Expanded(child: Text(pair.$2, textAlign: TextAlign.end)),
              ],
            ),
          ),
        if (device['status'] != 'connected')
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '信息来自本机记录',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
      ],
    ),
  );
}
