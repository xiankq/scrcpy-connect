import 'package:flutter/material.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

class DeviceStatus extends StatelessWidget {
  const DeviceStatus({super.key, required this.device, this.compact = false});
  final Json device;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final status = value(device, 'status', 'offline');
    return Text(
      statusText(status),
      style: compact
          ? Theme.of(context).textTheme.bodySmall
          : Theme.of(context).textTheme.bodyMedium,
    );
  }
}
