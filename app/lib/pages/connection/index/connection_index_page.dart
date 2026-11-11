import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/models/connection_validation.dart';

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
  final AppStore controller;
  final Json? initialDevice;
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
    address: address.isNotEmpty
        ? address
        : value(initialDevice ?? {}, 'address'),
    port: port,
    deviceId: deviceId ?? responseDeviceId(initialDevice),
    transport: initialDevice == null
        ? transport
        : connectionTransportForRecord(initialDevice!),
  );
}
