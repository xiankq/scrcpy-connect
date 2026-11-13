import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/widgets/window_environment_scope.dart';
import 'package:scrcpy_connect/widgets/window_environment_media.dart';

export 'package:scrcpy_connect/core/platform/window_environment.dart'
    show WindowEnvironment, WindowMode, WindowPosture, WindowSizeClass;
export 'package:scrcpy_connect/core/platform/window_environment_codec.dart'
    show WindowEnvironmentCodec;
export 'package:scrcpy_connect/widgets/window_environment_scope.dart'
    show WindowEnvironmentScope;

/// Reads the current Flutter view rather than a device or screen singleton.
WindowEnvironment windowEnvironmentOf(BuildContext context) {
  final override = windowEnvironmentOverrideOf(context);
  if (override != null) return override;
  return windowEnvironmentFromMedia(MediaQuery.of(context));
}

extension AdaptiveWindowContext on BuildContext {
  WindowEnvironment get windowEnvironment => windowEnvironmentOf(this);
}
