import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/widgets/window_environment_scope.dart';

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
  final media = MediaQuery.of(context);
  return WindowEnvironment(
    width: media.size.width,
    height: media.size.height,
    insets: WindowInsets(
      left: media.padding.left,
      top: media.padding.top,
      right: media.padding.right,
      bottom: media.padding.bottom,
    ),
    displayFeatures: [
      for (final feature in media.displayFeatures)
        WindowDisplayFeature(
          left: feature.bounds.left,
          top: feature.bounds.top,
          width: feature.bounds.width,
          height: feature.bounds.height,
          type: switch (feature.type) {
            DisplayFeatureType.fold => WindowDisplayFeatureType.fold,
            DisplayFeatureType.hinge => WindowDisplayFeatureType.hinge,
            DisplayFeatureType.cutout => WindowDisplayFeatureType.cutout,
            _ => WindowDisplayFeatureType.fold,
          },
          state: switch (feature.state) {
            DisplayFeatureState.postureFlat => WindowPosture.flat,
            DisplayFeatureState.postureHalfOpened => WindowPosture.book,
            _ => null,
          },
        ),
    ],
  );
}

extension AdaptiveWindowContext on BuildContext {
  WindowEnvironment get windowEnvironment => windowEnvironmentOf(this);
}
