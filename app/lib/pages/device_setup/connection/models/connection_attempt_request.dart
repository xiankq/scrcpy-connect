import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_endpoint.dart';

part 'connection_attempt_request.freezed.dart';

@freezed
sealed class ConnectionAttemptRequest with _$ConnectionAttemptRequest {
  const ConnectionAttemptRequest._();
  const factory ConnectionAttemptRequest.pair({
    required String address,
    required int port,
    required String code,
    String? deviceId,
  }) = PairDeviceRequest;
  const factory ConnectionAttemptRequest.connect({
    required DeviceEndpoint endpoint,
    String? deviceId,
    @Default(false) bool configure,
  }) = ConnectDeviceRequest;

  String get address => switch (this) {
    PairDeviceRequest(:final address) => address,
    ConnectDeviceRequest(:final endpoint) => endpoint.address,
  };
}
