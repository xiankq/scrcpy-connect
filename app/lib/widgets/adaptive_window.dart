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

/// designs/design.md「自适应窗口与形态」中的窗口阈值与窗格宽度。
abstract final class AdaptiveWindowMetrics {
  /// W ≥ 1080：文字侧栏 + 列表／详情双栏。
  static const splitWidth = 1080.0;

  /// 双栏时每个窗格至少 360 点。
  static const paneWidth = 360.0;

  /// iPhone Duo 内屏横向时每个安全窗格至少 280 点。
  static const duoPaneWidth = 280.0;

  /// H < 480：优先保证正文可滚动，侧栏收为导航轨道。
  static const shortHeight = 480.0;
}
