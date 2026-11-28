import 'package:flutter/services.dart';

/// [titleBar] is set when the runner hid the system title bar and expects the
/// app to draw one; [maximized] then drives the maximize/restore glyph.
typedef DesktopWindowLayout = ({
  double left,
  double right,
  double top,
  bool titleBar,
  bool maximized,
});

abstract final class DesktopWindow {
  static const channel = MethodChannel('dev.scrcpyconnect/desktop_window');

  static const DesktopWindowLayout nativeLayout = (
    left: 0,
    right: 0,
    top: 0,
    titleBar: false,
    maximized: false,
  );

  static DesktopWindowLayout decodeLayout(Map<Object?, Object?> value) => (
    left: (value['left'] as num).toDouble(),
    right: (value['right'] as num).toDouble(),
    top: (value['top'] as num).toDouble(),
    titleBar: value['titleBar'] == true,
    maximized: value['maximized'] == true,
  );

  static Future<DesktopWindowLayout> readLayout() async => decodeLayout(
    (await channel.invokeMapMethod<Object?, Object?>('layout'))!,
  );

  static Future<void> command(String name) => channel.invokeMethod<void>(name);
}

/// Window operations behind the app-drawn title bar on Windows and Linux.
abstract interface class DesktopWindowControls {
  Future<void> minimize();
  Future<void> toggleMaximized();
  Future<void> close();

  /// Hands the pressed pointer to the system move loop.
  Future<void> startMove();
}

final class PlatformDesktopWindowControls implements DesktopWindowControls {
  const PlatformDesktopWindowControls();

  @override
  Future<void> minimize() => DesktopWindow.command('minimize');

  @override
  Future<void> toggleMaximized() => DesktopWindow.command('toggleMaximized');

  @override
  Future<void> close() => DesktopWindow.command('close');

  @override
  Future<void> startMove() => DesktopWindow.command('move');
}
