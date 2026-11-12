import 'package:adb/adb.dart' show AdbCancellation;
import 'package:scrcpy_connect/core/devices/models/device_call.dart';

export 'package:scrcpy_connect/core/devices/models/device_call.dart';

abstract interface class DeviceCalls {
  /// 读取当前观察，不部署服务，也不恢复已停止的观察。
  Future<DeviceCallsSnapshot> readCalls(
    String deviceId, {
    AdbCancellation? cancellation,
  });

  /// 返回仅表示手机系统接受请求；实际界面由 Widget 中的远控画面确认。
  /// 当前只请求打开系统通话界面，不能指定或控制某一通电话。
  Future<void> requestCurrentCallUi(
    String deviceId, {
    AdbCancellation? cancellation,
  });
  Future<void> requestPhoneApp(
    String deviceId, {
    AdbCancellation? cancellation,
  });
}
