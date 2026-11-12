import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/video_output_snapshot.dart';

part 'video_session_view.freezed.dart';

/// 只读组合窗口、输出和设备共享租约；三个事实仍各由原所有者持有。
@freezed
abstract class VideoSessionView with _$VideoSessionView {
  const VideoSessionView._();
  const factory VideoSessionView({
    required VideoSessionSnapshot session,
    required KeepAwakeSnapshot wake,
    VideoOutputReceipt? output,
  }) = _VideoSessionView;

  String get sessionId => session.sessionId;
  String get deviceId => session.deviceId;
  Map<String, dynamic> toSnapshot() => {
    ...sessionWithVideoOutput(session.toSnapshot(), output?.toSnapshot()),
    ...wake.sessionSnapshot,
  };
}
