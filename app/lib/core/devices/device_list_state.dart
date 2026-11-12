import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

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
