import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';
import 'package:scrcpy_connect/core/platform/foldable_window_environment.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/widgets/window_environment_scope.dart';
import 'package:scrcpy_connect/widgets/window_environment_media.dart';

export 'package:scrcpy_connect/core/platform/window_environment.dart'
    show WindowEnvironment, WindowMode, WindowPosture, WindowSizeClass;
export 'package:scrcpy_connect/core/platform/window_environment_codec.dart'
    show WindowEnvironmentCodec;
export 'package:scrcpy_connect/widgets/window_environment_scope.dart'
    show WindowEnvironmentScope;
export 'package:scrcpy_connect/widgets/window_pane_host.dart'
    show WindowPaneHost;

/// Reads the current Flutter view rather than a device or screen singleton.
WindowEnvironment windowEnvironmentOf(BuildContext context) {
  final override = windowEnvironmentOverrideOf(context);
  final base = override ?? windowEnvironmentFromMedia(MediaQuery.of(context));
  return mergeFoldableWindowEnvironment(base, DuoMediaQuery.maybeOf(context));
}

extension AdaptiveWindowContext on BuildContext {
  WindowEnvironment get windowEnvironment => windowEnvironmentOf(this);
}
