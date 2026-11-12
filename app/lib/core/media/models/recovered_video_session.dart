import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/video_output_snapshot.dart';

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

  /// 控制画面的既有视图协议适配；校准与清理直接消费类型字段。
  Map<String, dynamic> toViewSnapshot() => sessionWithVideoOutput({
    ...session.toSnapshot(),
    ...?keepAwake?.sessionSnapshot,
  }, output?.toSnapshot());

  bool get live => session.live;
}

KeepAwakeSnapshot _freezeWake(KeepAwakeSnapshot value) => value.copyWith(
  pendingCleanup: List.unmodifiable(value.pendingCleanup.map(_freezeWake)),
);
