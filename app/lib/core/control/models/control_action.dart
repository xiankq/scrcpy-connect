import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy/scrcpy.dart' show ScrcpyControlCompletion;

part 'control_action.freezed.dart';

/// 会话及设备联合限定目标；无会话标识时只能选择唯一窗口。
/// 输入必须携带捕获代际，精确的释放事件在状态核验期间仍可提交。
@freezed
abstract class ControlTarget with _$ControlTarget {
  const factory ControlTarget({
    String? sessionId,
    String? deviceId,
    int? captureGeneration,
    String? captureRef,
  }) = _ControlTarget;
}

typedef ControlPoint = ({int x, int y, int width, int height});

enum ControlKeyAction { down, up, press }

enum ControlTouchAction { down, up, move, cancel, hover }

@freezed
sealed class ControlAction with _$ControlAction {
  const ControlAction._();
  const factory ControlAction.key(
    int keyCode, {
    @Default(ControlKeyAction.press) ControlKeyAction action,
    @Default(0) int repeat,
    @Default(0) int metaState,
  }) = ControlKey;
  const factory ControlAction.text(String text) = ControlText;
  const factory ControlAction.touch(
    ControlPoint point, {
    required ControlTouchAction action,
    required int pointerId,
    double? pressure,
    @Default(false) bool mouse,
    @Default(0) int buttons,
    @Default(0) int actionButton,
  }) = ControlTouch;
  const factory ControlAction.scroll(
    ControlPoint point, {
    required double horizontal,
    required double vertical,
    @Default(0) int buttons,
  }) = ControlScroll;
  const factory ControlAction.rotate() = ControlRotate;
  const factory ControlAction.screenPower({required bool on}) =
      ControlScreenPower;
  const factory ControlAction.launchApplication(String packageName) =
      ControlLaunchApplication;

  bool get isInput => switch (this) {
    ControlKey() || ControlText() || ControlTouch() || ControlScroll() => true,
    ControlRotate() ||
    ControlScreenPower() ||
    ControlLaunchApplication() => false,
  };
  bool get isRelease => switch (this) {
    ControlKey(action: .up) || ControlTouch(action: .up || .cancel) => true,
    _ => false,
  };
}

/// 分别表达 SDK 接纳、写入、剪贴板确认或应用打开消息已提交；不声称远端动作已经完成。
@freezed
sealed class ControlReceipt with _$ControlReceipt {
  const factory ControlReceipt.delivered(ScrcpyControlCompletion completion) =
      ControlDelivered;
  const factory ControlReceipt.emptyText() = ControlEmptyText;
  const factory ControlReceipt.applicationSubmitted({
    required String sessionId,
    required String operationId,
  }) = ControlApplicationSubmitted;
}
