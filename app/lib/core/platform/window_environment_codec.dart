import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';

/// Decodes the small, platform-neutral window payload used by native hosts.
///
/// Android WindowManager, iPhone Duo scene geometry and HarmonyOS
/// FoldSplitContainer can all project into this shape without making the
/// widget layer depend on a vendor SDK. HarmonyOS WindowStatusType names and
/// enum values are accepted at this boundary; Flutter's MediaQuery path
/// remains the primary source when the engine already exposes display
/// features.
final class WindowEnvironmentCodec {
  const WindowEnvironmentCodec._();

  static WindowEnvironment? decode(Json payload) {
    final width = _number(payload['width']);
    final height = _number(payload['height']);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    final insets = _insets(payload['insets']);
    final insetsProvided =
        payload.containsKey('insets') && payload['insets'] is Map;
    final features = _features(payload['displayFeatures']);
    final postureProvided =
        payload.containsKey('posture') &&
        _posture(payload['posture'], allowNull: true) != null;
    final displayFeaturesProvided = payload['displayFeatures'] is List;
    final input = _input(payload['input']);
    // HarmonyOS hosts commonly expose WindowStatusType as either the enum
    // name or its numeric value. Keep the canonical payload small while
    // accepting both forms at the platform boundary.
    final mode = _mode(payload['mode'] ?? payload['windowStatusType']);
    final posture =
        _posture(payload['posture'], allowNull: true) ??
        _postureFromFeatures(features) ??
        WindowPosture.normal;
    final windowId = payload['windowId'];
    return WindowEnvironment(
      width: width,
      height: height,
      insets: insets,
      displayFeatures: features,
      windowId: windowId is String && windowId.isNotEmpty
          ? windowId
          : 'primary',
      mode: mode,
      posture: posture,
      input: input,
      insetsProvided: insetsProvided,
      postureProvided: postureProvided,
      displayFeaturesProvided: displayFeaturesProvided,
    );
  }

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : null;

  static WindowInsets _insets(Object? value) {
    if (value is! Map) return const WindowInsets();
    return WindowInsets(
      left: _number(value['left']) ?? 0,
      top: _number(value['top']) ?? 0,
      right: _number(value['right']) ?? 0,
      bottom: _number(value['bottom']) ?? 0,
    );
  }

  static WindowInputCapabilities _input(Object? value) {
    if (value is! Map) return const WindowInputCapabilities();
    return WindowInputCapabilities(
      touch: value['touch'] is bool ? value['touch'] as bool : true,
      keyboard: value['keyboard'] is bool ? value['keyboard'] as bool : false,
      pointer: value['pointer'] is bool ? value['pointer'] as bool : false,
      stylus: value['stylus'] is bool ? value['stylus'] as bool : false,
    );
  }

  static List<WindowDisplayFeature> _features(Object? value) {
    if (value is! List) return const [];
    final features = <WindowDisplayFeature>[];
    for (final item in value) {
      if (item is! Map) continue;
      final feature = _feature(item.cast<Object?, Object?>());
      if (feature != null) features.add(feature);
    }
    return features;
  }

  static WindowDisplayFeature? _feature(Map<Object?, Object?> value) {
    final left = _number(value['left']);
    final top = _number(value['top']);
    final width = _number(value['width']);
    final height = _number(value['height']);
    final type = _featureType(value['type']);
    if (left == null ||
        top == null ||
        width == null ||
        height == null ||
        width < 0 ||
        height < 0 ||
        type == null) {
      return null;
    }
    return WindowDisplayFeature(
      left: left,
      top: top,
      width: width,
      height: height,
      type: type,
      state: _posture(value['state'], allowNull: true),
    );
  }

  static WindowPosture? _postureFromFeatures(
    List<WindowDisplayFeature> features,
  ) {
    for (final feature in features) {
      if (feature.state != null) return feature.state;
    }
    return null;
  }

  static WindowDisplayFeatureType? _featureType(Object? value) =>
      switch (value) {
        'fold' => WindowDisplayFeatureType.fold,
        'hinge' => WindowDisplayFeatureType.hinge,
        'cutout' => WindowDisplayFeatureType.cutout,
        _ => null,
      };

  static WindowMode _mode(Object? value) => switch (value) {
    'split' || 'SPLIT' || 'SPLIT_SCREEN' => WindowMode.split,
    'floating' || 'FLOATING' => WindowMode.floating,
    'freeform' || 'FREEFORM' => WindowMode.freeform,
    // HarmonyOS WindowStatusType values: FULL_SCREEN=1, MAXIMIZE=2,
    // MINIMIZE=3, FLOATING=4, SPLIT_SCREEN=5.
    4 => WindowMode.floating,
    5 => WindowMode.split,
    _ => WindowMode.fullScreen,
  };

  static WindowPosture? _posture(Object? value, {bool allowNull = false}) {
    final posture = switch (value) {
      'flat' => WindowPosture.flat,
      'book' => WindowPosture.book,
      'tabletop' => WindowPosture.tabletop,
      'normal' => WindowPosture.normal,
      _ => null,
    };
    return posture ?? (allowNull ? null : WindowPosture.normal);
  }
}
