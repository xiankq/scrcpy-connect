import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';

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
  int? get textureId => output?.textureId ?? session.textureId;

  /// 旧像素可供占位显示，不能证明当前捕获已可呈现或控制。
  bool get outputRetained =>
      output != null &&
      (output!.sessionId != sessionId ||
          output!.deviceId != deviceId ||
          output!.captureGeneration != session.captureGeneration ||
          output!.generation < session.generation);

  bool get hasDecodedFrame =>
      output != null &&
      !outputRetained &&
      output!.generation == session.generation &&
      output!.decodedReceipts > 0 &&
      output!.decodedWidth > 0 &&
      output!.decodedHeight > 0;
}
