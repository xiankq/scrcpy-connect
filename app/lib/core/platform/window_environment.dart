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

  @override
  bool operator ==(Object other) =>
      other is WindowInsets &&
      left == other.left &&
      top == other.top &&
      right == other.right &&
      bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

final class WindowDisplayFeature {
  const WindowDisplayFeature({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.type,
    this.state,
    this.separating = false,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final WindowDisplayFeatureType type;
  final WindowPosture? state;

  /// Whether this feature divides the app window into separate panes.
  ///
  /// Android's FoldingFeature distinguishes a separating hinge from a crease
  /// that remains one continuous surface. Flutter's DisplayFeature has no
  /// equivalent field. MediaQuery-only projections therefore keep the feature
  /// as a reserved region without splitting panes; native hosts must explicitly
  /// project `true` when their window manager reports a separating feature.
  final bool separating;

  @override
  bool operator ==(Object other) =>
      other is WindowDisplayFeature &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height &&
      type == other.type &&
      state == other.state &&
      separating == other.separating;

  @override
  int get hashCode =>
      Object.hash(left, top, width, height, type, state, separating);
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
    this.insetsProvided = false,
    this.postureProvided = false,
    this.displayFeaturesProvided = false,
  });

  final double width;
  final double height;
  final WindowInsets insets;
  final List<WindowDisplayFeature> displayFeatures;
  final String windowId;
  final WindowMode mode;
  final WindowPosture posture;
  final WindowInputCapabilities input;

  /// Whether a native host explicitly supplied [insets].
  ///
  /// An explicit zero inset clears stale Flutter view padding after a window
  /// mode or posture change; a missing inset payload keeps MediaQuery as the
  /// live fallback.
  final bool insetsProvided;

  /// Whether a native host explicitly supplied [posture].
  ///
  /// A missing posture is a neutral projection and lets the live Flutter view
  /// remain authoritative. An explicit `normal` posture clears a stale fold.
  final bool postureProvided;

  /// Whether a native host explicitly supplied [displayFeatures].
  ///
  /// An explicit empty list clears a stale hinge when a fold closes. A missing
  /// field keeps the live Flutter display features as the fallback.
  final bool displayFeaturesProvided;

  @override
  bool operator ==(Object other) {
    if (other is! WindowEnvironment ||
        width != other.width ||
        height != other.height ||
        insets != other.insets ||
        windowId != other.windowId ||
        mode != other.mode ||
        posture != other.posture ||
        input != other.input ||
        insetsProvided != other.insetsProvided ||
        postureProvided != other.postureProvided ||
        displayFeaturesProvided != other.displayFeaturesProvided ||
        displayFeatures.length != other.displayFeatures.length) {
      return false;
    }
    for (var index = 0; index < displayFeatures.length; index++) {
      if (displayFeatures[index] != other.displayFeatures[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    width,
    height,
    insets,
    windowId,
    mode,
    posture,
    input,
    insetsProvided,
    postureProvided,
    displayFeaturesProvided,
    Object.hashAll(displayFeatures),
  );

  WindowSizeClass get sizeClass => sizeClassFor(width);

  bool get isCompact => sizeClass == WindowSizeClass.compact;
  bool get isMedium => sizeClass == WindowSizeClass.medium;
  bool get isExpanded => sizeClass == WindowSizeClass.expanded;

  /// Expanded and desktop workspaces use their content toolbar rather than a
  /// phone-style status/header strip. A desktop window can be narrower than
  /// the expanded breakpoint or report `fullScreen`, so its identity must
  /// take precedence over a width- or mode-only classification.
  bool get isDesktopWindow =>
      windowId.startsWith('desktop:') ||
      windowId.startsWith('macos:') ||
      windowId.startsWith('windows:') ||
      windowId.startsWith('linux:');

  bool get usesWorkspaceToolbar =>
      isExpanded ||
      isDesktopWindow ||
      mode == WindowMode.freeform ||
      mode == WindowMode.floating;

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
      if (spansHeight && isFoldOrHinge && feature.separating) return feature;
    }
    return null;
  }

  /// A full-width fold or hinge that divides a tabletop or stacked layout.
  WindowDisplayFeature? get horizontalPaneDivider {
    for (final feature in displayFeatures) {
      final spansWidth =
          feature.left <= 0 &&
          feature.left + feature.width >= width &&
          feature.width > feature.height;
      final isFoldOrHinge =
          feature.type == WindowDisplayFeatureType.fold ||
          feature.type == WindowDisplayFeatureType.hinge;
      if (spansWidth && isFoldOrHinge && feature.separating) return feature;
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

  @override
  bool operator ==(Object other) =>
      other is WindowInputCapabilities &&
      touch == other.touch &&
      keyboard == other.keyboard &&
      pointer == other.pointer &&
      stylus == other.stylus;

  @override
  int get hashCode => Object.hash(touch, keyboard, pointer, stylus);
}
