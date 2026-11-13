import 'package:flutter/services.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 与平台宿主交换协议消息；业务策略和资源归属由所属功能维护。
final class PlatformChannels {
  const PlatformChannels();
  static const _methods = MethodChannel('dev.scrcpyconnect/platform');
  static const _events = EventChannel('dev.scrcpyconnect/media_events');
  static const _windowEnvironmentEvents = EventChannel(
    'dev.scrcpyconnect/window_environment/events',
  );

  Stream<dynamic> get events => _events.receiveBroadcastStream();

  Stream<dynamic> get windowEnvironmentEvents =>
      _windowEnvironmentEvents.receiveBroadcastStream();

  Future<Json?> requestOptional(String command, Json params) async {
    final result = await _methods.invokeMethod<Map<dynamic, dynamic>>(
      command,
      params,
    );
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  Future<Json> request(String command, Json params) async {
    final result = await _methods.invokeMethod<Object?>(command, params);
    return result is Map<Object?, Object?>
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }
}
