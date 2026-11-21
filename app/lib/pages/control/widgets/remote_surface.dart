import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:media_codec/media_codec.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/pages/control/remote_input_owner.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/ambient_loading_field.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

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
  });

  final RemotePresentation presentation;
  final RemoteInputOwner inputs;
  final ValueChanged<Size> onViewport;
  final String deviceLabel;
  final bool independent, ime, sensitive, needsWake, screenOff;
  final FocusNode inputFocus;
  final VoidCallback? onWake, onClose;
  final Widget recovery, controls;

  @override
  Widget build(BuildContext context) {
    final waiting = presentation.awaitingFirstFrame;
    final loading = waiting || presentation.connecting;
    final abnormal =
        presentation.error != null ||
        (presentation.paused && !presentation.connecting) ||
        presentation.stateUnverified ||
        presentation.appLaunchUnknown;
    final stage = abnormal
        ? '无法打开'
        : independent
        ? '正在打开独立窗口'
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
        if (loading && !screenOff)
          Positioned.fill(
            key: const ValueKey('remote-first-frame-wait'),
            child: AmbientLoadingField(
              semanticsLabel: '$deviceLabel，$stage',
              animating:
                  !abnormal && presentation.connecting && !presentation.exiting,
              showParticles: false,
              overlay: abnormal
                  ? recovery
                  : Center(
                      child: ContentLoadingIndicator(
                        size: DesignTokens.componentIconLargeSize,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
            ),
          ),
        if (presentation.qualityRebuilding)
          const Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(DesignTokens.spacingMd),
                child: ContentSurface(
                  padding: EdgeInsets.all(DesignTokens.spacingMd),
                  child: Text('正在调整画面…'),
                ),
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
                padding: EdgeInsets.only(top: DesignTokens.spacingXs),
                child: ContentSurface(
                  radius: DesignTokens.roundedFull,
                  padding: EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacingSm,
                    vertical: DesignTokens.spacingXxs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.pause,
                        size: DesignTokens.componentIconSmallSize,
                      ),
                      SizedBox(width: DesignTokens.spacingXxs),
                      Text('已暂停'),
                    ],
                  ),
                ),
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
          Center(
            child: Tooltip(
              message: '点亮屏幕',
              excludeFromSemantics: true,
              child: GlassToolbarIconButton(
                variant: GlassVariant.clear,
                semanticLabel: '点亮屏幕',
                onPressed: onWake,
                icon: const Icon(LucideIcons.sun, color: Colors.white),
              ),
            ),
          ),
        if (waiting)
          Positioned(
            left: MediaQuery.paddingOf(context).left + 20,
            top: MediaQuery.paddingOf(context).top + 12,
            child: Tooltip(
              message: '关闭等待',
              excludeFromSemantics: true,
              child: GlassToolbarIconButton(
                key: const ValueKey('remote-first-frame-close'),
                semanticLabel: '关闭等待',
                onPressed: onClose,
                icon: const Icon(LucideIcons.x),
              ),
            ),
          )
        else
          controls,
      ],
    );
  }
}
