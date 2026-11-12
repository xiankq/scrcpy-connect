import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';

part 'activity.freezed.dart';

/// 停止的是具体资源身份；组合列表的展示标识不能作为业务分发协议。
@freezed
sealed class ActivityTarget with _$ActivityTarget {
  const ActivityTarget._();
  const factory ActivityTarget.connection(String deviceId) = ConnectionActivity;
  const factory ActivityTarget.session(String sessionId) =
      SessionActivityTarget;
  const factory ActivityTarget.observation(String deviceId) =
      ObservationActivity;
  const factory ActivityTarget.transfer(String transferId) = TransferActivity;
  const factory ActivityTarget.audio(DeviceAudioTarget source) = AudioActivity;

  String get key => switch (this) {
    ConnectionActivity(:final deviceId) => 'connection:$deviceId',
    SessionActivityTarget(:final sessionId) => 'session:$sessionId',
    ObservationActivity(:final deviceId) => 'observation:$deviceId',
    TransferActivity(:final transferId) => 'transfer:$transferId',
    AudioActivity(:final source) => 'audio:${source.sourceId}',
  };
}

@freezed
abstract class ActivitySnapshot with _$ActivitySnapshot {
  const factory ActivitySnapshot({
    required ActivityTarget target,
    required String deviceId,
    required String deviceName,
    required String name,
    required String status,
    required String stopImpact,
  }) = _ActivitySnapshot;
}

@freezed
abstract class ActivityCollection with _$ActivityCollection {
  const factory ActivityCollection({
    required List<ActivitySnapshot> activities,
    required List<SessionActivity> pendingApplications,
  }) = _ActivityCollection;
}
