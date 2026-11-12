import 'activities.dart';

import 'package:scrcpy_connect/core/application/application_events.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';
import 'package:scrcpy_connect/core/devices/device_service.dart';
import 'package:scrcpy_connect/core/companion/companion_service.dart';
import 'package:scrcpy_connect/core/devices/device_observation_service.dart';
import 'package:scrcpy_connect/core/files/file_transfer_service.dart';
import 'package:scrcpy_connect/core/files/file_share_service.dart';
import 'package:scrcpy_connect/core/media/device_audio_service.dart';
import 'package:scrcpy_connect/core/control/device_wake_service.dart';
import 'package:scrcpy_connect/core/control/control_session_service.dart';
import 'package:scrcpy_connect/core/settings/settings_storage.dart';

/// 借用业务所有者组合只读快照；不建立连接、部署助手或取得资源关闭权。
/// 等待任一异步读取期间业务版本变化时重读，媒体帧不使读取持续饥饿。
final class ApplicationSnapshotReader {
  ApplicationSnapshotReader({
    required this.events,
    required this.activities,
    required this.devices,
    required this.sessions,
    required this.audio,
    required this.keepAwake,
    required this.observations,
    required this.companion,
    required this.transfers,
    required this.preferences,
    this.sharing,
  });
  final ApplicationEvents events;
  final ActivityManagement activities;
  final DeviceService devices;
  final ControlSessionService sessions;
  final DeviceAudioService audio;
  final DeviceWakeService keepAwake;
  final DeviceObservationService observations;
  final CompanionService companion;
  final FileTransferService transfers;
  final SettingsStorage preferences;
  final FileShareService? sharing;

  Future<Map<String, dynamic>> readSnapshot() async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final before = events.cursor;
      final sessionStates = await sessions.readSessions();
      final shares = await sharing?.readIncomingShares();
      final activityItems = await activities.readActivities();
      final sessionItems = [
        for (final session in sessionStates)
          keepAwake.projectSession(session.toSnapshot()),
      ];
      final deviceItems = devices.projectDevices();
      final sources = [for (final source in audio.snapshots()) source.toJson()];
      final observationItems = [
        for (final observation in observations.currentSnapshots())
          observations.statusProjection(observation.deviceId),
      ];
      final after = events.cursor;
      if (before.revision != after.revision) continue;
      return {
        'sequence': after.sequence,
        'consistency': 'event-fenced',
        'settings': preferences.current.toMap(),
        'devices': deviceItems,
        'sessions': sessionItems,
        'sources': sources,
        'transfers': transfers.transfers()['transfers'],
        'shares': [for (final share in shares ?? []) share.toJson()],
        'observations': observationItems,
        'companions': [
          for (final device in deviceItems)
            {
              'deviceId': device['id'],
              'state': {
                ...companion.capabilityState(device['id'] as String),
                'notifications': observations.statusProjection(
                  device['id'] as String,
                )['notifications'],
                'calls': observations.statusProjection(
                  device['id'] as String,
                )['calls'],
              },
            },
        ],
        'activities': [
          for (final activity in activityItems.activities)
            {
              'id': activity.target.key,
              'deviceId': activity.deviceId,
              'deviceName': activity.deviceName,
              'name': activity.name,
              'status': activity.status,
              'canStop': true,
              'stopImpact': activity.stopImpact,
              if (activity.target case AudioActivity(:final source))
                'sourceId': source.sourceId,
            },
        ],
      };
    }
    throw const RequestFailure('state_busy', '应用状态持续变化，尚未取得完整快照，请重试。');
  }
}
