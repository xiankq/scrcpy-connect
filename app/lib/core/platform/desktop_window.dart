import 'package:flutter/services.dart';

typedef DesktopWindowLayout = ({double left, double right, double top});

abstract final class DesktopWindow {
  static const channel = MethodChannel('dev.scrcpyconnect/desktop_window');

  static DesktopWindowLayout decodeLayout(Map<Object?, Object?> value) => (
    left: (value['left'] as num).toDouble(),
    right: (value['right'] as num).toDouble(),
    top: (value['top'] as num).toDouble(),
  );

  static Future<DesktopWindowLayout> readLayout() async => decodeLayout(
    (await channel.invokeMapMethod<Object?, Object?>('layout'))!,
  );

  static Future<void> command(String name) => channel.invokeMethod<void>(name);
}
