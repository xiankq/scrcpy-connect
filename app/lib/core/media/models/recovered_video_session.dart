import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/models/video_session_view.dart';

/// 核验时借用的捕获事实、设备唤醒事实及本机输出证据；不取得资源所有权。
final class RecoveredVideoSession {
  RecoveredVideoSession({
    required this.session,
    KeepAwakeSnapshot? keepAwake,
    VideoOutputReceipt? output,
  }) : keepAwake = keepAwake == null ? null : _freezeWake(keepAwake),
       output = output?.copyWith(
         startupTimingMs: Map.unmodifiable(output.startupTimingMs),
       );

  final VideoSessionSnapshot session;
  final KeepAwakeSnapshot? keepAwake;
  final VideoOutputReceipt? output;

  VideoSessionView toView() => VideoSessionView(
    session: session,
    wake:
        keepAwake ??
        KeepAwakeSnapshot.withoutLease(
          deviceId: session.deviceId,
          enabled: false,
          hasWindowOwner: session.live,
        ),
    output: output,
  );

  bool get live => session.live;
}

KeepAwakeSnapshot _freezeWake(KeepAwakeSnapshot value) => value.copyWith(
  pendingCleanup: List.unmodifiable(value.pendingCleanup.map(_freezeWake)),
);
