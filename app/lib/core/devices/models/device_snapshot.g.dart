// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'device_snapshot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DeviceSnapshot _$DeviceSnapshotFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_DeviceSnapshot', json, ($checkedConvert) {
      final val = _DeviceSnapshot(
        id: $checkedConvert('id', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String?),
        address: $checkedConvert('address', (v) => v as String?),
        port: $checkedConvert('port', (v) => (v as num?)?.toInt()),
        transport: $checkedConvert(
          'transport',
          (v) => $enumDecodeNullable(
            _$DeviceTransportEnumMap,
            v,
            unknownValue: JsonKey.nullForUndefinedEnumValue,
          ),
        ),
        status: $checkedConvert(
          'status',
          (v) =>
              $enumDecodeNullable(
                _$DeviceConnectionStatusEnumMap,
                v,
                unknownValue: DeviceConnectionStatus.unknown,
              ) ??
              DeviceConnectionStatus.unknown,
        ),
        connectionId: $checkedConvert('connectionId', (v) => v as String?),
        guid: $checkedConvert('guid', (v) => v as String?),
        serial: $checkedConvert('serial', (v) => v as String?),
        model: $checkedConvert('model', (v) => v as String?),
        androidVersion: $checkedConvert('androidVersion', (v) => v as String?),
        apiLevel: $checkedConvert('apiLevel', (v) => (v as num?)?.toInt()),
        battery: $checkedConvert('battery', (v) => (v as num?)?.toInt()),
        charging: $checkedConvert('charging', (v) => v as bool?),
        batteryUpdatedAt: $checkedConvert(
          'batteryUpdatedAt',
          (v) => (v as num?)?.toInt(),
        ),
        lastSeen: $checkedConvert('lastSeen', (v) => (v as num?)?.toInt()),
        reason: $checkedConvert('reason', (v) => v as String?),
        autoReconnect: $checkedConvert(
          'autoReconnect',
          (v) => v as bool? ?? false,
        ),
        observationWanted: $checkedConvert(
          'observationWanted',
          (v) => v as bool? ?? true,
        ),
      );
      return val;
    });

Map<String, dynamic> _$DeviceSnapshotToJson(_DeviceSnapshot instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'address': instance.address,
      'port': instance.port,
      'transport': _$DeviceTransportEnumMap[instance.transport],
      'status': _$DeviceConnectionStatusEnumMap[instance.status]!,
      'connectionId': ?instance.connectionId,
      'guid': instance.guid,
      'serial': instance.serial,
      'model': instance.model,
      'androidVersion': instance.androidVersion,
      'apiLevel': instance.apiLevel,
      'battery': instance.battery,
      'charging': instance.charging,
      'batteryUpdatedAt': instance.batteryUpdatedAt,
      'lastSeen': instance.lastSeen,
      'reason': instance.reason,
      'autoReconnect': instance.autoReconnect,
      'observationWanted': instance.observationWanted,
    };

const _$DeviceTransportEnumMap = {
  DeviceTransport.tcp: 'tcp',
  DeviceTransport.wireless: 'wireless',
  DeviceTransport.tls: 'tls',
  DeviceTransport.usb: 'usb',
};

const _$DeviceConnectionStatusEnumMap = {
  DeviceConnectionStatus.offline: 'offline',
  DeviceConnectionStatus.connecting: 'connecting',
  DeviceConnectionStatus.connected: 'connected',
  DeviceConnectionStatus.unauthorized: 'unauthorized',
  DeviceConnectionStatus.authorizing: 'authorizing',
  DeviceConnectionStatus.checking: 'checking',
  DeviceConnectionStatus.reconnecting: 'reconnecting',
  DeviceConnectionStatus.paired: 'paired',
  DeviceConnectionStatus.failed: 'failed',
  DeviceConnectionStatus.unknown: 'unknown',
};
