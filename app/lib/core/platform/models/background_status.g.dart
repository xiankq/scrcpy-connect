// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'background_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BackgroundStatus _$BackgroundStatusFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_BackgroundStatus', json, ($checkedConvert) {
      final val = _BackgroundStatus(
        supported: $checkedConvert('supported', (v) => v as bool? ?? false),
        canRequest: $checkedConvert('canRequest', (v) => v as bool? ?? false),
        running: $checkedConvert('running', (v) => v as bool? ?? false),
        stopped: $checkedConvert('stopped', (v) => v as bool? ?? false),
        connectionRequested: $checkedConvert(
          'connectionRequested',
          (v) => v as bool?,
        ),
        audioRequested: $checkedConvert('audioRequested', (v) => v as bool?),
        mediaPlaybackReady: $checkedConvert(
          'mediaPlaybackReady',
          (v) => v as bool?,
        ),
        notificationPermission: $checkedConvert(
          'notificationPermission',
          (v) => v as bool?,
        ),
        requested: $checkedConvert('requested', (v) => v as bool?),
        platform: $checkedConvert('platform', (v) => v as String?),
        title: $checkedConvert('title', (v) => v as String? ?? '系统后台条件'),
        reason: $checkedConvert(
          'reason',
          (v) => v as String? ?? '尚未确认本机后台能力。请保持 App 在前台，并核对活动的实际状态。',
        ),
      );
      return val;
    });

Map<String, dynamic> _$BackgroundStatusToJson(_BackgroundStatus instance) =>
    <String, dynamic>{
      'supported': instance.supported,
      'canRequest': instance.canRequest,
      'running': instance.running,
      'stopped': instance.stopped,
      'connectionRequested': instance.connectionRequested,
      'audioRequested': instance.audioRequested,
      'mediaPlaybackReady': instance.mediaPlaybackReady,
      'notificationPermission': instance.notificationPermission,
      'requested': instance.requested,
      'platform': instance.platform,
      'title': instance.title,
      'reason': instance.reason,
    };
