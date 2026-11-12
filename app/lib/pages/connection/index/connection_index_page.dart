import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';

class AddDevicePage extends StatelessWidget {
  const AddDevicePage({
    super.key,
    required this.controller,
    this.initialDevice,
    this.initialMode = AddDeviceMode.pairing,
    this.address = '',
    this.port = '',
    this.transport,
    this.deviceId,
  });
  final AppNotifier controller;
  final DeviceSnapshot? initialDevice;
  final AddDeviceMode initialMode;
  final String address;
  final String port;
  final ConnectionTransport? transport;
  final String? deviceId;

  @override
  Widget build(BuildContext context) => ConnectionFormPage(
    controller: controller,
    reauthorizing: initialDevice != null,
    initialMode: initialMode,
    pairing: initialMode == AddDeviceMode.pairing,
    address: address.isNotEmpty ? address : initialDevice?.address ?? '',
    port: port,
    deviceId: deviceId ?? initialDevice?.id,
    transport: initialDevice == null
        ? transport
        : connectionTransportForRecord(initialDevice!),
  );
}
