import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';

/// 已核验媒体回执产生的视图工作；事件归属及状态转换由窗口判定。
final class RemoteVideoUpdate {
  const RemoteVideoUpdate({
    this.changed = true,
    this.geometryChanged = false,
    this.releaseInputs = false,
    this.previousBinding,
    this.wake,
  });

  final bool changed;
  final bool geometryChanged;
  final bool releaseInputs;
  // 未指定旧绑定时撤销当前输入；指定时只排空事件接受前的绑定。
  final (String, int)? previousBinding;
  final KeepAwakeSnapshot? wake;
}
