// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'device_observation_snapshot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DeviceObservationSnapshot _$DeviceObservationSnapshotFromJson(
  Map<String, dynamic> json,
) => _DeviceObservationSnapshot(
  deviceId: json['deviceId'] as String,
  wanted: json['wanted'] as bool,
  phase: $enumDecode(_$DeviceObservationPhaseEnumMap, json['phase']),
  generation: (json['generation'] as num).toInt(),
  notificationsLive: json['notificationsLive'] as bool? ?? false,
  callsLive: json['callsLive'] as bool? ?? false,
);

Map<String, dynamic> _$DeviceObservationSnapshotToJson(
  _DeviceObservationSnapshot instance,
) => <String, dynamic>{
  'deviceId': instance.deviceId,
  'wanted': instance.wanted,
  'phase': _$DeviceObservationPhaseEnumMap[instance.phase]!,
  'generation': instance.generation,
  'notificationsLive': instance.notificationsLive,
  'callsLive': instance.callsLive,
};

const _$DeviceObservationPhaseEnumMap = {
  DeviceObservationPhase.waitingConnection: 'waiting_connection',
  DeviceObservationPhase.stopped: 'stopped',
  DeviceObservationPhase.starting: 'starting',
  DeviceObservationPhase.observing: 'observing',
  DeviceObservationPhase.limited: 'limited',
  DeviceObservationPhase.failed: 'failed',
};
