import 'package:flutter/services.dart';

enum DesktopWindowState { normal, maximized, fullscreen }

abstract final class DesktopWindow {
  static const channel = MethodChannel('dev.scrcpyconnect/desktop_window');

  static Future<void> command(String name, [String? argument]) =>
      channel.invokeMethod<void>(name, argument);
}
