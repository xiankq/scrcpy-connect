import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';

/// 设备连接状态文字，`subheadline`（紧凑时 `footnote`）+ `text-secondary`。
class DeviceStatus extends StatelessWidget {
  const DeviceStatus({super.key, required this.device, this.compact = false});
  final DeviceSnapshot device;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final type = AppTypography.of(context);
    return Text(
      deviceStatusText(device),
      style: (compact ? type.footnote : type.subheadline).copyWith(
        color: AppColors.of(context).textSecondary,
      ),
    );
  }
}

String deviceTransportLabel(DeviceSnapshot device) =>
    switch (device.transport) {
      .usb => 'USB',
      .tls => '无线调试',
      .tcp || .wireless => 'IP 连接',
      null => '连接方式未获取',
    };
