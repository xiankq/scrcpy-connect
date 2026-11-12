// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'device_call.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DeviceCall _$DeviceCallFromJson(Map<String, dynamic> json) => _DeviceCall(
  id: json['id'] as String?,
  state:
      $enumDecodeNullable(
        _$DeviceCallStateEnumMap,
        json['state'],
        unknownValue: DeviceCallState.unknown,
      ) ??
      DeviceCallState.unknown,
  name: json['name'] as String?,
  number: json['number'] as String?,
  deviceName: json['deviceName'] as String?,
  aggregate: json['aggregate'] as bool? ?? false,
);

Map<String, dynamic> _$DeviceCallToJson(_DeviceCall instance) =>
    <String, dynamic>{
      'id': instance.id,
      'state': _$DeviceCallStateEnumMap[instance.state]!,
      'name': instance.name,
      'number': instance.number,
      'deviceName': instance.deviceName,
      'aggregate': instance.aggregate,
    };

const _$DeviceCallStateEnumMap = {
  DeviceCallState.unknown: 'unknown',
  DeviceCallState.ringing: 'ringing',
  DeviceCallState.active: 'active',
  DeviceCallState.dialing: 'dialing',
  DeviceCallState.connecting: 'connecting',
};

_DeviceCallsSnapshot _$DeviceCallsSnapshotFromJson(Map<String, dynamic> json) =>
    _DeviceCallsSnapshot(
      deviceId: json['deviceId'] as String,
      status:
          $enumDecodeNullable(
            _$DeviceCallAvailabilityEnumMap,
            json['status'],
            unknownValue: DeviceCallAvailability.unknown,
          ) ??
          DeviceCallAvailability.unknown,
      live: json['live'] as bool? ?? false,
      calls:
          (json['calls'] as List<dynamic>?)
              ?.map((e) => DeviceCall.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      reason: json['reason'] as String?,
      canOpenSystemCallUi: json['canOpenSystemCallUi'] as bool? ?? false,
      canRetrySystemCallUi: json['canRetrySystemCallUi'] as bool? ?? false,
    );

Map<String, dynamic> _$DeviceCallsSnapshotToJson(
  _DeviceCallsSnapshot instance,
) => <String, dynamic>{
  'deviceId': instance.deviceId,
  'status': _$DeviceCallAvailabilityEnumMap[instance.status]!,
  'live': instance.live,
  'calls': instance.calls,
  'reason': instance.reason,
  'canOpenSystemCallUi': instance.canOpenSystemCallUi,
  'canRetrySystemCallUi': instance.canRetrySystemCallUi,
};

const _$DeviceCallAvailabilityEnumMap = {
  DeviceCallAvailability.unknown: 'unknown',
  DeviceCallAvailability.available: 'available',
  DeviceCallAvailability.limited: 'limited',
  DeviceCallAvailability.stopped: 'stopped',
};
