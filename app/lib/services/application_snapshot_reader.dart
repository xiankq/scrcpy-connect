import 'package:scrcpy_connect/services/application_events.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/device_service.dart';
import 'package:scrcpy_connect/services/companion_service.dart';
import 'package:scrcpy_connect/services/device_observation_service.dart';
import 'package:scrcpy_connect/services/file_transfer_service.dart';
import 'package:scrcpy_connect/services/file_share_service.dart';
import 'package:scrcpy_connect/services/device_audio_service.dart';
import 'package:scrcpy_connect/services/device_wake_service.dart';
import 'package:scrcpy_connect/services/screen_capture_service.dart';
import 'package:scrcpy_connect/stores/settings_store.dart';

/// 借用业务所有者组合只读快照；不建立连接、部署助手或取得资源关闭权。
/// 等待任一异步读取期间业务版本变化时重读，媒体帧不使读取持续饥饿。
final class ApplicationSnapshotReader {
  ApplicationSnapshotReader({
    required this.events,
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
  final DeviceService devices;
  final ScreenCaptureService sessions;
  final DeviceAudioService audio;
  final DeviceWakeService keepAwake;
  final DeviceObservationService observations;
  final CompanionService companion;
  final FileTransferService transfers;
  final SettingsStore preferences;
  final FileShareService? sharing;

  Future<Map<String, dynamic>> readSnapshot() async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final before = events.cursor;
      final sessionStates = await sessions.snapshots();
      final shares = await sharing?.command('sharing.pending', const {});
      final sessionItems = [
        for (final session in sessionStates) projectSession(session),
      ];
      final deviceItems = devices.projectDevices();
      final sources = audio.snapshots();
      final observationItems = observations.list();
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
        'shares': shares?['shares'] ?? <Object?>[],
        'observations': observationItems,
        'companions': [
          for (final device in deviceItems)
            {
              'deviceId': device['id'],
              'state': {
                ...companion.capabilityState(device['id'] as String),
                'notifications': observations.status(
                  device['id'] as String,
                )['notifications'],
                'calls': observations.status(device['id'] as String)['calls'],
              },
            },
        ],
        'activities': _activities(
          deviceItems,
          sessionItems,
          sources,
          observationItems,
        ),
      };
    }
    throw const RequestFailure('state_busy', '应用状态持续变化，尚未取得完整快照，请重试。');
  }

  /// 快照与实时窗口事件共用同一投影；读取不启动或关闭保持唤醒服务。
  Map<String, Object?> projectSession(Map<String, Object?> session) =>
      sessionWithKeepAwake(
        session,
        keepAwake.projection(session['deviceId']! as String),
      );

  List<Map<String, Object?>> _activities(
    List<Map<String, Object?>> deviceItems,
    List<Map<String, Object?>> sessions,
    List<Map<String, Object?>> sources,
    List<Map<String, Object?>> observations,
  ) {
    final names = {
      for (final device in deviceItems)
        device['id'] as String: device['name'] as String,
    };
    Map<String, Object?> activity(
      String kind,
      String id,
      String device,
      String name,
      Object? status,
      String impact,
    ) => {
      'id': '$kind:$id',
      'deviceId': device,
      'deviceName': names[device] ?? 'Android 设备',
      'name': name,
      'status': status,
      'canStop': true,
      'stopImpact': impact,
    };
    return [
      for (final device in deviceItems)
        if (devices.current(device['id'] as String) != null)
          activity(
            'connection',
            device['id'] as String,
            device['id'] as String,
            '设备连接',
            'connected',
            '断开这台设备，并停止它的控制会话和传输任务；其他设备不受影响。',
          ),
      for (final session in sessions)
        activity(
          'session',
          session['sessionId'] as String,
          session['deviceId'] as String,
          session['name'] as String? ?? '控制窗口',
          session['status'],
          '仅关闭这个控制会话，手机应用任务交回设备，不会强停应用。',
        ),
      for (final observation in observations)
        if (observation['wanted'] == true)
          activity(
            'observation',
            observation['deviceId'] as String,
            observation['deviceId'] as String,
            '通知与来电观察',
            observation['phase'],
            '仅停止这台设备的通知与来电观察。',
          ),
      for (final source in sources)
        if (!const {
          'stopped',
          'failed',
          'error',
          'closed',
        }.contains(source['status']))
          {
            ...activity(
              'audio',
              source['sourceId'] as String,
              source['deviceId'] as String,
              '设备声音',
              source['status'],
              '仅停止这台设备的这一代音源；设备连接及其他活动保持运行。',
            ),
            'sourceId': source['sourceId'],
          },
      ...transfers.activities(deviceNames: names),
    ];
  }
}

/// 保持唤醒属于设备共享控制服务，其关闭证明不能覆盖窗口捕获自身的证明。
Map<String, Object?> sessionWithKeepAwake(
  Map<String, Object?> session,
  Map<String, Object?> keepAwake,
) {
  if (session['deviceId'] != keepAwake['deviceId']) {
    throw ArgumentError('保持唤醒投影必须属于同一台设备。');
  }
  return {
    ...session,
    for (final key in const [
      'keepActive',
      'keepActiveApplied',
      'keepActiveLeaseActive',
      'keepActiveLeaseId',
      'keepActivePid',
      'keepActiveProcessStarted',
      'keepActiveConnectionId',
      'keepActiveError',
    ])
      key: keepAwake[key],
    'keepActiveCleanup': {
      'leaseId': keepAwake['keepActiveLeaseId'],
      'pid': keepAwake['keepActivePid'],
      'processStarted': keepAwake['keepActiveProcessStarted'],
      'connectionId': keepAwake['keepActiveConnectionId'],
      'error': keepAwake['keepActiveError'],
      'releasePending': keepAwake['releasePending'] == true,
      'localCleanupConfirmed': keepAwake['localCleanupConfirmed'] == true,
      'cleanupConfirmed': keepAwake['cleanupConfirmed'] == true,
      'remoteExitVerified': keepAwake['remoteExitVerified'] == true,
      'remoteRestoreVerified': keepAwake['remoteRestoreVerified'] == true,
      'pendingCleanup': keepAwake['pendingCleanup'] ?? <Object?>[],
    },
  };
}
