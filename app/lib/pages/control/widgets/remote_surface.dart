import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:media_codec/media_codec.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/pages/control/remote_input_owner.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_opening_view.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/banner.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';

class RemoteSurface extends StatelessWidget {
  const RemoteSurface({
    super.key,
    required this.textureId,
    required this.sourceSize,
    required this.inputs,
    this.onViewport,
  });

  final int? textureId;
  final Size sourceSize;
  final RemoteInputOwner inputs;
  final ValueChanged<Size>? onViewport;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = constraints.biggest;
      onViewport?.call(viewport);
      final texture = textureId;
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerHover: (event) => inputs.hover(event, viewport, sourceSize),
        onPointerSignal: (event) => inputs.scroll(event, viewport, sourceSize),
        onPointerDown: (event) =>
            inputs.pointer(event, .down, viewport, sourceSize),
        onPointerMove: (event) =>
            inputs.pointer(event, .move, viewport, sourceSize),
        onPointerUp: (event) =>
            inputs.pointer(event, .up, viewport, sourceSize),
        onPointerCancel: (event) =>
            inputs.pointer(event, .cancel, viewport, sourceSize),
        child: texture != null && sourceSize.width > 0 && sourceSize.height > 0
            ? MediaCodecView(
                textureId: texture,
                width: sourceSize.width.round(),
                height: sourceSize.height.round(),
              )
            : const SizedBox.expand(),
      );
    },
  );
}

/// 画面、等待与恢复覆盖层共用同一视口，输入和会话资源由页面所有者管理。
class RemoteStage extends StatelessWidget {
  const RemoteStage({
    super.key,
    required this.presentation,
    required this.inputs,
    required this.onViewport,
    required this.deviceLabel,
    required this.independent,
    required this.recovery,
    required this.ime,
    required this.sensitive,
    required this.inputFocus,
    required this.needsWake,
    required this.screenOff,
    required this.onWake,
    required this.onClose,
    required this.controls,
    this.onSwitchWindow,
  });

  final RemotePresentation presentation;
  final RemoteInputOwner inputs;
  final ValueChanged<Size> onViewport;
  final String deviceLabel;
  final bool independent, ime, sensitive, needsWake, screenOff;
  final FocusNode inputFocus;
  final VoidCallback? onWake, onClose;
  final VoidCallback? onSwitchWindow;
  final Widget recovery, controls;

  @override
  Widget build(BuildContext context) {
    final waiting = presentation.awaitingFirstFrame;
    final sideToolbar = liquid.GlassVerticalBar.maybeOf(context);
    final closeWait = Tooltip(
      message: '关闭等待',
      excludeFromSemantics: true,
      child: GlassToolbarIconButton(
        key: const ValueKey('remote-first-frame-close'),
        semanticLabel: '关闭等待',
        onPressed: onClose,
        icon: const Icon(AppIcons.close),
      ),
    );
    final switchWait = onSwitchWindow == null
        ? null
        : GlassToolbarIconButton(
            semanticLabel: '切换窗口',
            onPressed: onSwitchWindow,
            icon: const Icon(LucideIcons.layers),
          );
    final loading = waiting || presentation.connecting;
    final abnormal =
        presentation.error != null ||
        (presentation.paused && !presentation.connecting) ||
        presentation.stateUnverified ||
        presentation.appLaunchUnknown;
    final showMotion = !abnormal && !presentation.exiting;
    final stage = abnormal
        ? '无法打开'
        : independent
        ? '正在打开独立应用画面'
        : '正在打开手机屏幕';
    return Stack(
      children: [
        Positioned.fill(
          child: RemoteSurface(
            textureId: screenOff ? null : presentation.session?.textureId,
            sourceSize: Size(presentation.imageWidth, presentation.imageHeight),
            inputs: inputs,
            onViewport: onViewport,
          ),
        ),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: reduceMotionOf(context) || screenOff
                ? Duration.zero
                : contentArrivalDuration,
            switchOutCurve: panelCurve,
            layoutBuilder: (current, outgoing) => Stack(
              fit: StackFit.expand,
              children: [
                for (final child in outgoing)
                  IgnorePointer(
                    child: ExcludeSemantics(
                      child: TickerMode(enabled: false, child: child),
                    ),
                  ),
                ?current,
              ],
            ),
            child: loading && !screenOff
                ? RemoteOpeningView(
                    key: const ValueKey('remote-first-frame-wait'),
                    semanticsLabel: '$deviceLabel，$stage',
                    title: stage,
                    detail: deviceLabel,
                    steps: remoteOpeningSteps(
                      presentation,
                      deviceLabel: deviceLabel,
                      failed: false,
                    ),
                    animating: showMotion,
                    failure: abnormal ? recovery : null,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        if (presentation.qualityRebuilding)
          const Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(DesignTokens.spacingLg),
                child: AppBanner(message: '正在调整画面…', icon: AppIcons.refresh),
              ),
            ),
          ),
        if (!loading &&
            !presentation.connecting &&
            (presentation.error != null ||
                presentation.stateUnverified ||
                presentation.appLaunchUnknown ||
                presentation.sessionEnded) &&
            !needsWake &&
            presentation.errorCode != 'device_asleep')
          recovery
        else if (!loading && presentation.paused && !screenOff)
          const Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  DesignTokens.spacingLg,
                  DesignTokens.spacingSm,
                  DesignTokens.spacingLg,
                  0,
                ),
                child: AppBanner(message: '已暂停', icon: LucideIcons.pause),
              ),
            ),
          ),
        if (ime)
          Positioned(
            left: 0,
            bottom: 0,
            width: 1,
            height: 1,
            child: TextField(
              focusNode: inputFocus,
              controller: inputs.text,
              autofocus: true,
              obscureText: sensitive,
              enableSuggestions: !sensitive,
              autocorrect: !sensitive,
              enableInteractiveSelection: !sensitive,
              onSubmitted: (_) {
                if (!inputs.canSendInput) return;
                for (final action in [
                  ControlKeyAction.down,
                  ControlKeyAction.up,
                ]) {
                  unawaited(inputs.send(ControlAction.key(66, action: action)));
                }
              },
            ),
          ),
        if (needsWake)
          // 熄屏视口中央的「点亮屏幕」（Ardot「远控 / 点亮屏幕」37:1156）。
          Center(
            child: AppButton(
              role: AppButtonRole.glass,
              label: '点亮屏幕',
              icon: LucideIcons.sun,
              onPressed: onWake,
            ),
          ),
        if (!waiting)
          controls
        else if (sideToolbar != null)
          GlassSideToolbar(bar: sideToolbar, children: [closeWait, ?switchWait])
        else
          Positioned(
            left:
                MediaQuery.paddingOf(context).left +
                (DesktopWindowInsets.of(context)?.left ?? 0) +
                DesignTokens.spacingSm,
            right:
                MediaQuery.paddingOf(context).right +
                (DesktopWindowInsets.of(context)?.right ?? 0) +
                DesignTokens.spacingSm,
            top: MediaQuery.paddingOf(context).top,
            height: DesignTokens.componentPageBarHeight,
            child: Row(
              spacing: DesignTokens.spacingSm,
              children: [
                closeWait,
                Expanded(
                  child: Text(
                    independent ? deviceLabel : '$deviceLabel · 手机屏幕',
                    style: AppTypography.of(context).title3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ?switchWait,
              ],
            ),
          ),
      ],
    );
  }
}
