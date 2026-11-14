import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:scrcpy_connect/core/platform/platform_channels.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/core/platform/window_environment_codec.dart';
import 'package:scrcpy_connect/widgets/window_environment_media.dart';

/// Tracks optional native window metadata and merges it with Flutter's live
/// MediaQuery geometry as the window or application lifecycle changes.
///
/// The native payload supplies identity, mode and vendor-specific posture;
/// MediaQuery remains authoritative for the current Flutter view dimensions.
final class WindowEnvironmentScope extends StatefulWidget {
  const WindowEnvironmentScope({
    super.key,
    required this.child,
    this.readHostEnvironment = _readHostEnvironment,
    this.readDesktopWindowIdentity = _readDesktopWindowIdentity,
    this.watchHostEnvironment = _watchHostEnvironment,
  });

  final Widget child;
  final Future<WindowEnvironment?> Function() readHostEnvironment;
  final Future<WindowEnvironment?> Function() readDesktopWindowIdentity;
  final Stream<WindowEnvironment?> Function() watchHostEnvironment;

  @override
  State<WindowEnvironmentScope> createState() => _WindowEnvironmentScopeState();
}

final class _WindowEnvironmentScopeState extends State<WindowEnvironmentScope>
    with WidgetsBindingObserver {
  WindowEnvironment? _hostEnvironment;
  StreamSubscription<WindowEnvironment?>? _hostEnvironmentSubscription;
  int _requestGeneration = 0;
  bool _reloadQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hostEnvironmentSubscription = widget.watchHostEnvironment().listen(
      _applyHostEnvironment,
      onError: (_, _) {},
    );
    unawaited(_loadHostEnvironment());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_hostEnvironmentSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeMetrics() => _queueHostEnvironmentReload();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queueHostEnvironmentReload();
    }
  }

  void _queueHostEnvironmentReload() {
    if (_reloadQueued) return;
    _reloadQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadQueued = false;
      if (mounted) unawaited(_loadHostEnvironment());
    });
  }

  Future<void> _loadHostEnvironment() async {
    final requestGeneration = ++_requestGeneration;
    final environment =
        await widget.readHostEnvironment() ??
        await widget.readDesktopWindowIdentity();
    if (!mounted || requestGeneration != _requestGeneration) return;
    _applyHostEnvironment(environment, requestGeneration: requestGeneration);
  }

  void _applyHostEnvironment(
    WindowEnvironment? environment, {
    int? requestGeneration,
  }) {
    if (!mounted) return;
    if (requestGeneration != null && requestGeneration != _requestGeneration) {
      return;
    }
    // An event is a newer host fact than every in-flight metrics read.
    if (requestGeneration == null) _requestGeneration++;
    if (_sameEnvironment(_hostEnvironment, environment)) return;
    setState(() {
      _hostEnvironment = environment;
    });
  }

  static bool _sameEnvironment(
    WindowEnvironment? left,
    WindowEnvironment? right,
  ) => left == right;

  @override
  Widget build(BuildContext context) {
    final mediaEnvironment = _mediaEnvironmentOf(context);
    final environment = _hostEnvironment == null
        ? mediaEnvironment
        : _merge(mediaEnvironment, _hostEnvironment!);
    final inherited = _WindowEnvironmentInherited(
      environment: environment,
      child: widget.child,
    );
    if (_hostEnvironment?.insetsProvided != true) return inherited;
    final hostInsets = _hostEnvironment!.insets;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final viewPadding = EdgeInsets.fromLTRB(
      hostInsets.left,
      hostInsets.top,
      hostInsets.right,
      hostInsets.bottom,
    );
    final padding = EdgeInsets.fromLTRB(
      math.max(0, viewPadding.left - viewInsets.left),
      math.max(0, viewPadding.top - viewInsets.top),
      math.max(0, viewPadding.right - viewInsets.right),
      math.max(0, viewPadding.bottom - viewInsets.bottom),
    );
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(padding: padding, viewPadding: viewPadding),
      child: inherited,
    );
  }

  static WindowEnvironment _mediaEnvironmentOf(BuildContext context) {
    return windowEnvironmentFromMedia(MediaQuery.of(context));
  }

  static WindowEnvironment _merge(
    WindowEnvironment media,
    WindowEnvironment host,
  ) {
    final hostHasDisplayFeatures =
        host.displayFeaturesProvided || host.displayFeatures.isNotEmpty;
    final hostHasInsets =
        host.insetsProvided ||
        host.insets.left != 0 ||
        host.insets.top != 0 ||
        host.insets.right != 0 ||
        host.insets.bottom != 0;
    return WindowEnvironment(
      width: media.width,
      height: media.height,
      insets: hostHasInsets ? host.insets : media.insets,
      displayFeatures: hostHasDisplayFeatures
          ? host.displayFeatures
          : media.displayFeatures,
      windowId: host.windowId,
      mode: host.mode,
      insetsProvided: host.insetsProvided,
      // A host that only knows its window identity decodes with the neutral
      // posture. Preserve the live Flutter display-feature posture until the
      // host supplies an explicit posture or feature projection.
      posture: host.postureProvided || hostHasDisplayFeatures
          ? host.posture
          : media.posture,
      input: host.input,
      postureProvided: host.postureProvided,
      displayFeaturesProvided: host.displayFeaturesProvided,
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

Stream<WindowEnvironment?> _watchHostEnvironment() {
  try {
    return const PlatformChannels().windowEnvironmentEvents.map((payload) {
      if (payload is! Map) return null;
      return WindowEnvironmentCodec.decode(Map<String, dynamic>.from(payload));
    });
  } on Exception {
    return const Stream<WindowEnvironment?>.empty();
  }
}

Future<WindowEnvironment?> _readDesktopWindowIdentity() async {
  const desktopPlatforms = {
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  };
  if (!desktopPlatforms.contains(defaultTargetPlatform)) return null;
  try {
    final controller = await WindowController.fromCurrentEngine();
    if (controller.windowId.isEmpty) return null;
    return WindowEnvironment(
      width: 1,
      height: 1,
      windowId: 'desktop:${controller.windowId}',
      mode: WindowMode.freeform,
    );
  } on Exception {
    return null;
  }
}
