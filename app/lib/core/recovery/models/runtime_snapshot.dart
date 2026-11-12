import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/observed_device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/models/incoming_share.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';
import 'package:scrcpy_connect/core/media/models/recovered_video_session.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

/// 同一业务版本内读取的校准事实。功能查询与资源仍由所属模块维护。
final class RuntimeSnapshot {
  RuntimeSnapshot({
    required this.sequence,
    required this.settings,
    List<DeviceSnapshot> devices = const [],
    List<RecoveredVideoSession> sessions = const [],
    List<DeviceAudioSnapshot> sources = const [],
    List<IncomingShare> shares = const [],
    List<ObservedDeviceSnapshot> observations = const [],
  }) : devices = immutableDeviceSnapshots(devices),
       sessions = List.unmodifiable(sessions),
       sources = List.unmodifiable(sources),
       shares = List.unmodifiable([
         for (final share in shares)
           share.copyWith(
             files: List.unmodifiable(share.files),
             errors: List.unmodifiable(share.errors),
           ),
       ]),
       observations = List.unmodifiable(observations) {
    if (sequence < 0) {
      throw const RequestFailure('invalid_snapshot', '状态快照缺少有效版本。');
    }
    _checkIds(this.sessions.map((item) => item.session.sessionId));
    _checkIds(this.sources.map((item) => item.sourceId));
  }

  final int sequence;
  final Preferences settings;
  final List<DeviceSnapshot> devices;
  final List<RecoveredVideoSession> sessions;
  final List<DeviceAudioSnapshot> sources;
  final List<IncomingShare> shares;
  final List<ObservedDeviceSnapshot> observations;

  RuntimeSnapshot withSessions(List<RecoveredVideoSession> value) =>
      RuntimeSnapshot(
        sequence: sequence,
        settings: settings,
        devices: devices,
        sessions: value,
        sources: sources,
        shares: shares,
        observations: observations,
      );
}

void _checkIds(Iterable<String> values) {
  final ids = <String>{};
  for (final id in values) {
    if (id.isEmpty || !ids.add(id)) {
      throw const RequestFailure('invalid_snapshot', '状态快照包含无效或重复的媒体标识。');
    }
  }
}
