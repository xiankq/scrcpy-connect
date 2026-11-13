/// The platform-neutral projection of the window that currently owns a view.
///
/// Platform adapters may add richer posture data, but widgets should only
/// make layout decisions from this value. In particular, a device model or
/// physical display must never be used as a proxy for the available window.
enum WindowSizeClass { compact, medium, expanded }

enum WindowMode { fullScreen, split, floating, freeform }

enum WindowPosture { normal, flat, book, tabletop }

enum WindowDisplayFeatureType { fold, hinge, cutout }

final class WindowInsets {
  const WindowInsets({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}

final class WindowDisplayFeature {
  const WindowDisplayFeature({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.type,
    this.state,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final WindowDisplayFeatureType type;
  final WindowPosture? state;

  bool contains(double x, double y) =>
      x >= left && x <= left + width && y >= top && y <= top + height;
}

final class WindowEnvironment {
  const WindowEnvironment({
    required this.width,
    required this.height,
    this.insets = const WindowInsets(),
    this.displayFeatures = const [],
    this.windowId = 'primary',
    this.mode = WindowMode.fullScreen,
    this.posture = WindowPosture.normal,
    this.input = const WindowInputCapabilities(),
  });

  final double width;
  final double height;
  final WindowInsets insets;
  final List<WindowDisplayFeature> displayFeatures;
  final String windowId;
  final WindowMode mode;
  final WindowPosture posture;
  final WindowInputCapabilities input;

  WindowSizeClass get sizeClass => sizeClassFor(width);

  bool get isCompact => sizeClass == WindowSizeClass.compact;
  bool get isMedium => sizeClass == WindowSizeClass.medium;
  bool get isExpanded => sizeClass == WindowSizeClass.expanded;

  /// Expanded desktop workspaces use their content toolbar rather than a
  /// phone-style status/header strip.
  bool get usesWorkspaceToolbar => isExpanded && height >= 480;

  /// A feature that physically divides or blocks content must be treated as a
  /// reserved region by pane layout.
  bool get hasReservedDisplayFeature => displayFeatures.any(
    (feature) =>
        feature.type == WindowDisplayFeatureType.fold ||
        feature.type == WindowDisplayFeatureType.hinge ||
        feature.type == WindowDisplayFeatureType.cutout,
  );

  /// A full-height fold or hinge that can divide a two-pane workspace.
  ///
  /// Cutouts and small camera regions are handled by [insets]; they must not
  /// turn the whole workspace into two columns.
  WindowDisplayFeature? get verticalPaneDivider {
    for (final feature in displayFeatures) {
      final spansHeight =
          feature.top <= 0 &&
          feature.top + feature.height >= height &&
          feature.height > feature.width;
      final isFoldOrHinge =
          feature.type == WindowDisplayFeatureType.fold ||
          feature.type == WindowDisplayFeatureType.hinge;
      if (spansHeight && isFoldOrHinge) return feature;
    }
    return null;
  }

  static WindowSizeClass sizeClassFor(double width) {
    if (width < 600) return WindowSizeClass.compact;
    if (width < 840) return WindowSizeClass.medium;
    return WindowSizeClass.expanded;
  }
}

final class WindowInputCapabilities {
  const WindowInputCapabilities({
    this.touch = true,
    this.keyboard = false,
    this.pointer = false,
    this.stylus = false,
  });

  final bool touch;
  final bool keyboard;
  final bool pointer;
  final bool stylus;
}
