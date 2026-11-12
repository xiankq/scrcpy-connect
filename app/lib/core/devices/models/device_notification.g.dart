// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'device_notification.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DeviceNotification _$DeviceNotificationFromJson(Map<String, dynamic> json) =>
    _DeviceNotification(
      id: json['id'] as String,
      key: json['key'] as String?,
      revision: json['revision'] as String?,
      packageName: json['packageName'] as String? ?? '',
      appName: json['appName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      userId: (json['userId'] as num?)?.toInt(),
      postedAt: (json['postedAt'] as num?)?.toInt(),
      groupSummary: json['groupSummary'] as bool? ?? false,
      canOpen: json['canOpen'] as bool?,
      canDismiss: json['canDismiss'] as bool?,
    );

Map<String, dynamic> _$DeviceNotificationToJson(_DeviceNotification instance) =>
    <String, dynamic>{
      'id': instance.id,
      'key': instance.key,
      'revision': instance.revision,
      'packageName': instance.packageName,
      'appName': instance.appName,
      'title': instance.title,
      'body': instance.body,
      'userId': instance.userId,
      'postedAt': instance.postedAt,
      'groupSummary': instance.groupSummary,
      'canOpen': instance.canOpen,
      'canDismiss': instance.canDismiss,
    };

_DeviceNotificationsSnapshot _$DeviceNotificationsSnapshotFromJson(
  Map<String, dynamic> json,
) => _DeviceNotificationsSnapshot(
  deviceId: json['deviceId'] as String,
  status:
      $enumDecodeNullable(
        _$DeviceNotificationAvailabilityEnumMap,
        json['status'],
        unknownValue: DeviceNotificationAvailability.unknown,
      ) ??
      DeviceNotificationAvailability.unknown,
  live: json['live'] as bool? ?? false,
  observationEpoch: (json['observationEpoch'] as num?)?.toInt(),
  observationEnabled: json['observationEnabled'] as bool? ?? false,
  truncated: json['truncated'] as bool? ?? false,
  notifications:
      (json['notifications'] as List<dynamic>?)
          ?.map((e) => DeviceNotification.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  reason: json['reason'] as String?,
);

Map<String, dynamic> _$DeviceNotificationsSnapshotToJson(
  _DeviceNotificationsSnapshot instance,
) => <String, dynamic>{
  'deviceId': instance.deviceId,
  'status': _$DeviceNotificationAvailabilityEnumMap[instance.status]!,
  'live': instance.live,
  'observationEpoch': instance.observationEpoch,
  'observationEnabled': instance.observationEnabled,
  'truncated': instance.truncated,
  'notifications': instance.notifications,
  'reason': instance.reason,
};

const _$DeviceNotificationAvailabilityEnumMap = {
  DeviceNotificationAvailability.unknown: 'unknown',
  DeviceNotificationAvailability.available: 'available',
  DeviceNotificationAvailability.limited: 'limited',
  DeviceNotificationAvailability.needsSetup: 'needsSetup',
  DeviceNotificationAvailability.stopped: 'stopped',
  DeviceNotificationAvailability.checking: 'checking',
  DeviceNotificationAvailability.starting: 'starting',
};
