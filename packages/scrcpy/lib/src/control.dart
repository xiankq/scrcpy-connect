/// 与 Android KeyEvent 一致的按键动作。
enum ScrcpyKeyAction { down, up }

/// 与 Android MotionEvent 一致的触控动作。
enum ScrcpyTouchAction { down, up, move, cancel, hoverMove }

/// 控制完成的证据层级；写出应用启动消息不证明应用已经打开。
enum ScrcpyControlCompletion {
  /// 进入有界控制队列；后续传输失败仍可能终止会话。
  admitted,

  /// 完成 ADB 控制写入回执；不证明 Android 应用已处理动作。
  written,

  /// 收到对应 SET_CLIPBOARD 序列号的协议 ACK。
  clipboardAcknowledged,
}

final class ScrcpyControlReceipt {
  const ScrcpyControlReceipt(this.completion);
  final ScrcpyControlCompletion completion;
}

/// 类型化上游控制消息；完成层级由 [ScrcpyControlReceipt] 明确返回。
sealed class ScrcpyControlMessage {
  const ScrcpyControlMessage();
}

final class ScrcpyKey extends ScrcpyControlMessage {
  const ScrcpyKey({
    required this.action,
    required this.keycode,
    this.repeat = 0,
    this.metaState = 0,
  });
  final ScrcpyKeyAction action;
  final int keycode;
  final int repeat;
  final int metaState;
}

final class ScrcpyText extends ScrcpyControlMessage {
  const ScrcpyText(this.text);
  final String text;
}

final class ScrcpyTouch extends ScrcpyControlMessage {
  const ScrcpyTouch({
    required this.action,
    required this.pointerId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.pressure = 1,
    this.actionButton = 0,
    this.buttons = 0,
  });
  final ScrcpyTouchAction action;
  final int pointerId;
  final int x;
  final int y;
  final int width;
  final int height;
  final double pressure;
  final int actionButton;
  final int buttons;
}

final class ScrcpyScroll extends ScrcpyControlMessage {
  const ScrcpyScroll({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.horizontal,
    required this.vertical,
    this.buttons = 0,
  });
  final int x;
  final int y;
  final int width;
  final int height;
  final double horizontal;
  final double vertical;
  final int buttons;
}

final class ScrcpyClipboard extends ScrcpyControlMessage {
  const ScrcpyClipboard(this.text, {this.paste = false});
  final String text;
  final bool paste;
}

final class ScrcpyRotate extends ScrcpyControlMessage {
  const ScrcpyRotate();
}

/// 请求上游改变显示电源；written 回执不证明屏幕状态已经改变。
final class ScrcpySetDisplayPower extends ScrcpyControlMessage {
  const ScrcpySetDisplayPower({required this.on});
  final bool on;
}

/// 调整启用 flexDisplay 的新显示；宽高为 1..65535，最终尺寸仍受编码器约束。
///
/// 此消息不修改物理屏幕 wm size 或显示密度。
final class ScrcpyResizeDisplay extends ScrcpyControlMessage {
  const ScrcpyResizeDisplay({required this.width, required this.height});
  final int width;
  final int height;
}

final class ScrcpyResetVideo extends ScrcpyControlMessage {
  const ScrcpyResetVideo();
}

final class ScrcpyStartApp extends ScrcpyControlMessage {
  const ScrcpyStartApp(this.packageName);
  final String packageName;
}
