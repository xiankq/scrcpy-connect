import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/core/platform/platform_channels.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/core/platform/window_environment_codec.dart';

/// Loads optional native window metadata once and merges it with Flutter's
/// live MediaQuery geometry.
///
/// The native payload supplies identity, mode and vendor-specific posture;
/// MediaQuery remains authoritative for the current Flutter view dimensions.
final class WindowEnvironmentScope extends StatefulWidget {
  const WindowEnvironmentScope({
    super.key,
    required this.child,
    this.readHostEnvironment = _readHostEnvironment,
  });

  final Widget child;
  final Future<WindowEnvironment?> Function() readHostEnvironment;

  @override
  State<WindowEnvironmentScope> createState() => _WindowEnvironmentScopeState();
}

final class _WindowEnvironmentScopeState extends State<WindowEnvironmentScope> {
  WindowEnvironment? _hostEnvironment;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHostEnvironment());
  }

  Future<void> _loadHostEnvironment() async {
    final environment = await widget.readHostEnvironment();
    if (mounted && environment != null) {
      setState(() => _hostEnvironment = environment);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaEnvironment = _mediaEnvironmentOf(context);
    final environment = _hostEnvironment == null
        ? mediaEnvironment
        : _merge(mediaEnvironment, _hostEnvironment!);
    return _WindowEnvironmentInherited(
      environment: environment,
      child: widget.child,
    );
  }

  static WindowEnvironment _mediaEnvironmentOf(BuildContext context) {
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
      displayFeatures: media.displayFeatures
          .map(
            (feature) => WindowDisplayFeature(
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
              state: switch (feature.state) {
                ui.DisplayFeatureState.postureFlat => WindowPosture.flat,
                ui.DisplayFeatureState.postureHalfOpened => WindowPosture.book,
                _ => null,
              },
            ),
          )
          .toList(growable: false),
    );
  }

  static WindowEnvironment _merge(
    WindowEnvironment media,
    WindowEnvironment host,
  ) {
    final hostHasInsets =
        host.insets.left != 0 ||
        host.insets.top != 0 ||
        host.insets.right != 0 ||
        host.insets.bottom != 0;
    return WindowEnvironment(
      width: media.width,
      height: media.height,
      insets: hostHasInsets ? host.insets : media.insets,
      displayFeatures: host.displayFeatures.isNotEmpty
          ? host.displayFeatures
          : media.displayFeatures,
      windowId: host.windowId,
      mode: host.mode,
      posture: host.posture,
      input: host.input,
    );
  }
}

final class _WindowEnvironmentInherited extends InheritedWidget {
  const _WindowEnvironmentInherited({
    required this.environment,
    required super.child,
  });

  final WindowEnvironment environment;

  @override
  bool updateShouldNotify(_WindowEnvironmentInherited oldWidget) =>
      environment != oldWidget.environment;
}

/// Returns a host projection when a [WindowEnvironmentScope] is present.
WindowEnvironment? windowEnvironmentOverrideOf(BuildContext context) {
  return context
      .dependOnInheritedWidgetOfExactType<_WindowEnvironmentInherited>()
      ?.environment;
}

Future<WindowEnvironment?> _readHostEnvironment() async {
  try {
    final payload = await const PlatformChannels().requestOptional(
      'window.readEnvironment',
      const {},
    );
    return payload == null ? null : WindowEnvironmentCodec.decode(payload);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
