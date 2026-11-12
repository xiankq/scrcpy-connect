import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';

part 'device_list_state.freezed.dart';

@freezed
class DeviceListState with _$DeviceListState {
  DeviceListState({
    List<DeviceSnapshot> devices = const [],
    this.loading = true,
    this.error,
  }) : devices = immutableDeviceSnapshots(devices);
  final List<DeviceSnapshot> devices;
  final bool loading;
  final String? error;
}
