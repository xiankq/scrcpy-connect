import 'package:flutter/material.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/connection_form_page.dart';

class AddDevicePage extends StatelessWidget {
  const AddDevicePage({
    super.key,
    this.initialDevice,
    this.initialMode = AddDeviceMode.pairing,
    this.address = '',
    this.port = '',
    this.transport,
    this.deviceId,
  });
  final DeviceSnapshot? initialDevice;
  final AddDeviceMode initialMode;
  final String address;
  final String port;
  final ConnectionTransport? transport;
  final String? deviceId;

  @override
  Widget build(BuildContext context) => ConnectionFormPage(
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
