import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/observed_device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/models/incoming_share.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';
import 'package:scrcpy_connect/core/media/models/recovered_video_session.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

/// 借用业务所有者的只读事实，不建立连接、部署助手或取得资源关闭权。
/// 等待期间业务版本变化时重读；媒体帧不改变版本，避免持续播放使读取饥饿。
final class RuntimeSnapshotReader {
  RuntimeSnapshotReader({
    required this.readCursor,
    required this.readDevices,
    required this.readSessions,
    required this.readAudio,
    required this.readShares,
    required this.readObservations,
    required this.readSettings,
  });

  final ({int sequence, int revision}) Function() readCursor;
  final List<DeviceSnapshot> Function() readDevices;
  final Future<List<RecoveredVideoSession>> Function() readSessions;
  final List<DeviceAudioSnapshot> Function() readAudio;
  final Future<List<IncomingShare>> Function() readShares;
  final List<ObservedDeviceSnapshot> Function() readObservations;
  final Preferences Function() readSettings;

  Future<RuntimeSnapshot> readSnapshot() async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final before = readCursor();
      final sessions = await readSessions();
      final shares = await readShares();
      final devices = readDevices();
      final sources = readAudio();
      final observations = readObservations();
      final settings = readSettings();
      final after = readCursor();
      if (before.revision != after.revision) continue;
      return RuntimeSnapshot(
        sequence: after.sequence,
        settings: settings,
        devices: devices,
        sessions: sessions,
        sources: sources,
        shares: shares,
        observations: observations,
      );
    }
    throw const RequestFailure('state_busy', '应用状态持续变化，尚未取得完整快照，请重试。');
  }
}
