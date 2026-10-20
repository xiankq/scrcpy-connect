import 'package:flutter/material.dart';
import 'package:scrcpy_connect/pages/connection/index/connection_index_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

/// Compatibility entry for the former wireless setup page.
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
  Widget build(BuildContext context) => AddDevicePage(
    controller: controller,
    deviceId: deviceId,
    address: address,
  );
}
