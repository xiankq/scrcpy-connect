import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/connection/connection_validation.dart';

class DeviceConnectionPreferencesPage extends StatelessWidget {
  const DeviceConnectionPreferencesPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;

  @override
  Widget build(BuildContext context) => ConnectionFormPage(
    key: ValueKey(value(device, 'id')),
    controller: controller,
    configuring: true,
    deviceId: value(device, 'id'),
    initialMode: device['transport'] == 'usb'
        ? AddDeviceMode.usb
        : AddDeviceMode.ip,
    address: device['transport'] == 'usb' ? '' : value(device, 'address'),
    port: device['port'] == 0 ? '' : value(device, 'port'),
    transport: connectionTransportForRecord(device),
  );
}
