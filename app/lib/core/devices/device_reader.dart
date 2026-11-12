import 'dart:async';

import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';

/// 本机设备记录与当前连接的只读投影；读取不连接设备，也不启动发现或观察。
abstract interface class DeviceReader {
  FutureOr<List<DeviceSnapshot>> readDevices();
  FutureOr<DeviceSnapshot> readDevice(String id);
}
