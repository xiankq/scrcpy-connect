import 'package:foldable/foldable.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';

/// Applies the foldable package's atomic iPhone Duo snapshot to the app's
/// cross-platform window contract.
///
/// UIKit's reserved-region API and Flutter's `MediaQuery` do not expose the
/// same facts on every engine. Keeping this conversion at the platform edge
/// means pages consume one environment and never need to guess from a device
/// name or from a fixed Duo breakpoint.
WindowEnvironment mergeFoldableWindowEnvironment(
  WindowEnvironment base,
  FoldableData? fold,
) {
  if (fold == null || !fold.isFoldable) return base;

  final divisions = <WindowDisplayFeature>[];
  final occlusions = <WindowDisplayFeature>[];
  for (final region in fold.regions) {
    if (region.kind == ReservedRegionKind.division) {
      // The foldable package keeps an inactive division in its snapshot so a
      // caller can reason about the device's shape. It is a layout boundary
      // only while the hinge is partially open; the active flag can lag the
      // hinge by a frame on iOS.
      if (fold.status != HingeStatus.partiallyOpen) continue;
      final bounds = region.bounds;
      final vertical = bounds.height >= bounds.width;
      divisions.add(
        WindowDisplayFeature(
          left: bounds.left,
          top: bounds.top,
          width: bounds.width,
          height: bounds.height,
          type: WindowDisplayFeatureType.fold,
          state: vertical ? WindowPosture.book : WindowPosture.tabletop,
          separating: true,
        ),
      );
    } else if (region.kind == ReservedRegionKind.occlusion && region.isActive) {
      final bounds = region.bounds;
      occlusions.add(
        WindowDisplayFeature(
          left: bounds.left,
          top: bounds.top,
          width: bounds.width,
          height: bounds.height,
          type: WindowDisplayFeatureType.cutout,
          separating: false,
        ),
      );
    }
  }

  final posture = switch (fold.status) {
    HingeStatus.closed => WindowPosture.normal,
    HingeStatus.fullyOpen => WindowPosture.flat,
    HingeStatus.partiallyOpen =>
      divisions.isEmpty ? base.posture : divisions.first.state ?? base.posture,
    HingeStatus.unknown => base.posture,
  };
  return WindowEnvironment(
    width: base.width,
    height: base.height,
    insets: base.insets,
    displayFeatures: <WindowDisplayFeature>[...divisions, ...occlusions],
    windowId: base.windowId,
    mode: base.mode,
    posture: posture,
    input: base.input,
    insetsProvided: base.insetsProvided,
    postureProvided: true,
    // An empty list is meaningful here: it clears a stale division when the
    // hinge reaches fully open or moves to the cover display.
    displayFeaturesProvided: true,
  );
}
