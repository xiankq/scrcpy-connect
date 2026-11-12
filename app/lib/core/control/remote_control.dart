import 'package:scrcpy_connect/core/control/models/control_action.dart';

export 'package:scrcpy_connect/core/control/models/control_action.dart';

/// 仅向已有捕获提交控制，不负责窗口启动、画质、播放器或导航。
abstract interface class RemoteControl {
  Future<ControlReceipt> sendControl(
    ControlTarget target,
    ControlAction action,
  );
}
