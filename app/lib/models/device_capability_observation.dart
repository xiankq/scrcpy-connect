enum DeviceObservationStatus { unknown, ok, error }

/// 一组实际查询事实；未知、执行失败与不支持由解释层分别处理。
final class DeviceCapabilityObservation {
  const DeviceCapabilityObservation.unknown()
    : status = DeviceObservationStatus.unknown,
      text = null,
      code = null,
      message = null;
  const DeviceCapabilityObservation.ok([this.text])
    : status = DeviceObservationStatus.ok,
      code = null,
      message = null;
  const DeviceCapabilityObservation.error(this.code, this.message)
    : status = DeviceObservationStatus.error,
      text = null;

  final DeviceObservationStatus status;
  final String? text, code, message;
  bool get succeeded => status == DeviceObservationStatus.ok;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'stdout': ?text,
    'code': ?code,
    'message': ?message,
  };
}
