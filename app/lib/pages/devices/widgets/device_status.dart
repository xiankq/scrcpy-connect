import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:flutter/material.dart';

class DeviceStatus extends StatelessWidget {
  const DeviceStatus({super.key, required this.device, this.compact = false});
  final Json device;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text(
      deviceStatusText(device),
      style: compact
          ? Theme.of(context).textTheme.bodySmall
          : Theme.of(context).textTheme.bodyMedium,
    );
  }
}

String deviceTransportLabel(Json device) =>
    switch (value(device, 'transport')) {
      'usb' => 'USB',
      'tls' => '无线调试',
      'tcp' || 'wireless' => 'IP 连接',
      _ => '连接方式未获取',
    };
