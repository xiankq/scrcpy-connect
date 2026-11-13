import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/widgets/window_environment_media.dart';
import 'package:scrcpy_connect/widgets/window_environment_scope.dart';

/// Keeps a single-window layout inside one safe sub-screen when a horizontal
/// fold or hinge divides the view (for example, tabletop posture).
///
/// Vertical folds are handled by the workspace's list/sidebar split. A
/// horizontal fold has no second page owner to render, so the app chooses the
/// top sub-screen for tabletop posture and removes the hinge from the child's
/// coordinate space instead of allowing content to cross it.
final class WindowPaneHost extends StatelessWidget {
  const WindowPaneHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final environment =
        windowEnvironmentOverrideOf(context) ??
        windowEnvironmentFromMedia(media);
    final divider = environment.horizontalPaneDivider;
    if (divider == null) return child;

    final topPane = environment.posture == WindowPosture.tabletop;
    final paneTop = topPane ? 0.0 : divider.top + divider.height;
    final paneBottom = topPane ? divider.top : media.size.height;
    final paneHeight = math.max(0.0, paneBottom - paneTop).toDouble();
    final data = media.copyWith(
      size: Size(media.size.width, paneHeight),
      padding: EdgeInsets.only(
        left: media.padding.left,
        top: topPane ? media.padding.top : 0,
        right: media.padding.right,
        bottom: topPane ? 0 : media.padding.bottom,
      ),
      viewPadding: EdgeInsets.only(
        left: media.viewPadding.left,
        top: topPane ? media.viewPadding.top : 0,
        right: media.viewPadding.right,
        bottom: topPane ? 0 : media.viewPadding.bottom,
      ),
      viewInsets: EdgeInsets.only(
        left: media.viewInsets.left,
        top: topPane ? media.viewInsets.top : 0,
        right: media.viewInsets.right,
        bottom: topPane ? 0 : media.viewInsets.bottom,
      ),
      displayFeatures: _featuresInPane(
        media.displayFeatures,
        paneTop,
        paneBottom,
      ),
    );
    return Align(
      alignment: topPane ? Alignment.topCenter : Alignment.bottomCenter,
      child: SizedBox(
        width: media.size.width,
        height: paneHeight,
        child: MediaQuery(data: data, child: child),
      ),
    );
  }

  static List<ui.DisplayFeature> _featuresInPane(
    List<ui.DisplayFeature> features,
    double paneTop,
    double paneBottom,
  ) => [
    for (final feature in features)
      if (feature.bounds.top >= paneTop && feature.bounds.bottom <= paneBottom)
        ui.DisplayFeature(
          bounds: feature.bounds.shift(Offset(0, -paneTop)),
          type: feature.type,
          state: feature.state,
        ),
  ];
}
