import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_battery.dart';
import 'package:scrcpy_connect/core/devices/models/device_record.dart'
    show DeviceTransport;

part 'device_details.freezed.dart';

@freezed
abstract class DeviceReading<T> with _$DeviceReading<T> {
  const factory DeviceReading({
    required String deviceId,
    required T value,
    String? connectionId,
    int? observedAt,
    @Default(false) bool stale,
  }) = _DeviceReading<T>;
}

enum DeviceDetailSection {
  system,
  battery,
  display,
  power,
  network,
  memory,
  storage,
}

typedef DeviceCapacity = ({int? totalBytes, int? availableBytes});

@freezed
abstract class DeviceReadFailure with _$DeviceReadFailure {
  const factory DeviceReadFailure({
    required String code,
    required String message,
  }) = _DeviceReadFailure;
}

@freezed
abstract class DeviceDetails with _$DeviceDetails {
  const factory DeviceDetails({
    @Default(DeviceSystemInfo()) DeviceSystemInfo system,
    @Default(DeviceBattery()) DeviceBattery battery,
    @Default(DeviceDisplayInfo()) DeviceDisplayInfo display,
    @Default(DeviceNetworkInfo()) DeviceNetworkInfo network,
    @Default((totalBytes: null, availableBytes: null)) DeviceCapacity memory,
    @Default((totalBytes: null, availableBytes: null)) DeviceCapacity storage,
    int? cpuCores,
    @Default({}) Map<DeviceDetailSection, DeviceReadFailure> failures,
  }) = _DeviceDetails;
}

@freezed
abstract class DeviceSystemInfo with _$DeviceSystemInfo {
  const factory DeviceSystemInfo({
    String? model,
    String? brand,
    String? product,
    String? hardware,
    String? androidVersion,
    int? apiLevel,
    String? securityPatch,
    String? build,
    String? serial,
    String? abi,
  }) = _DeviceSystemInfo;
}

@freezed
abstract class DeviceDisplayInfo with _$DeviceDisplayInfo {
  const factory DeviceDisplayInfo({
    int? width,
    int? height,
    int? densityDpi,
    double? refreshRate,
    @Default(DeviceScreenState()) DeviceScreenState screen,
  }) = _DeviceDisplayInfo;
}

@freezed
abstract class DeviceScreenState with _$DeviceScreenState {
  const factory DeviceScreenState({bool? screenOn, bool? locked}) =
      _DeviceScreenState;
}

@freezed
abstract class DeviceNetworkAddress with _$DeviceNetworkAddress {
  const factory DeviceNetworkAddress({
    required String interface,
    required String address,
  }) = _DeviceNetworkAddress;
}

@freezed
abstract class DeviceNetworkInfo with _$DeviceNetworkInfo {
  const factory DeviceNetworkInfo({
    @Default([]) List<DeviceNetworkAddress> addresses,
    DeviceTransport? transport,
    String? address,
    int? port,
  }) = _DeviceNetworkInfo;
}
