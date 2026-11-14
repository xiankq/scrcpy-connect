import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';

/// Projects the live Flutter view into the platform-neutral window contract.
///
/// This is deliberately kept at the widget boundary: [MediaQueryData] is a
/// view concern, while [WindowEnvironment] remains usable by platform hosts
/// and pure layout code without importing Flutter view types.
WindowEnvironment windowEnvironmentFromMedia(MediaQueryData media) {
  final displayFeatures = <WindowDisplayFeature>[];
  var posture = WindowPosture.normal;
  for (final feature in media.displayFeatures) {
    final featurePosture = switch (feature.state) {
      ui.DisplayFeatureState.postureFlat => WindowPosture.flat,
      ui.DisplayFeatureState.postureHalfOpened => WindowPosture.book,
      _ => null,
    };
    if (featurePosture != null) posture = featurePosture;
    displayFeatures.add(
      WindowDisplayFeature(
        left: feature.bounds.left,
        top: feature.bounds.top,
        width: feature.bounds.width,
        height: feature.bounds.height,
        type: switch (feature.type) {
          ui.DisplayFeatureType.fold => WindowDisplayFeatureType.fold,
          ui.DisplayFeatureType.hinge => WindowDisplayFeatureType.hinge,
          ui.DisplayFeatureType.cutout => WindowDisplayFeatureType.cutout,
          _ => WindowDisplayFeatureType.fold,
        },
        state: featurePosture,
        // Flutter's DisplayFeature does not expose Android's separating flag.
        // Keep the crease reserved but continuous until a native host projects
        // an explicit separating=true fact.
        separating: false,
      ),
    );
  }
  return WindowEnvironment(
    width: media.size.width,
    height: media.size.height,
    insets: WindowInsets(
      left: media.padding.left,
      top: media.padding.top,
      right: media.padding.right,
      bottom: media.padding.bottom,
    ),
    displayFeatures: displayFeatures,
    posture: posture,
  );
}
