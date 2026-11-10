import 'dart:async';
import 'dart:math' as math;

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/remote_presentation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/ambient_loading_field.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:flutter/material.dart';
import 'package:media_codec/media_codec.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/remote_input_owner.dart';

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
            inputs.pointer(event, 'down', viewport, sourceSize),
        onPointerMove: (event) =>
            inputs.pointer(event, 'move', viewport, sourceSize),
        onPointerUp: (event) =>
            inputs.pointer(event, 'up', viewport, sourceSize),
        onPointerCancel: (event) =>
            inputs.pointer(event, 'cancel', viewport, sourceSize),
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
    required this.onWake,
    required this.onClose,
    required this.controls,
  });

  final RemotePresentation presentation;
  final RemoteInputOwner inputs;
  final ValueChanged<Size> onViewport;
  final String deviceLabel;
  final bool independent, ime, sensitive, needsWake;
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
        ? presentation.connecting
              ? '正在核对屏幕启动结果'
              : presentation.stateUnverified || presentation.appLaunchUnknown
              ? '屏幕启动结果待核对'
              : '屏幕启动未完成'
        : independent
        ? '正在打开独立窗口'
        : '正在打开手机屏幕';
    return Stack(
      children: [
        Positioned.fill(
          child: RemoteSurface(
            textureId: int.tryParse('${presentation.session?['textureId']}'),
            sourceSize: Size(presentation.imageWidth, presentation.imageHeight),
            inputs: inputs,
            onViewport: onViewport,
          ),
        ),
        if (loading)
          Positioned.fill(
            key: const ValueKey('remote-first-frame-wait'),
            child: AmbientLoadingField(
              semanticsLabel: '$deviceLabel，$stage',
              animating:
                  !abnormal && presentation.connecting && !presentation.exiting,
              showParticles: !abnormal && !presentation.exiting,
              overlay: abnormal ? recovery : null,
            ),
          ),
        if (presentation.qualityRebuilding)
          const Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(DesignTokens.spacingMd),
                child: Glass(
                  padding: EdgeInsets.all(DesignTokens.spacingMd),
                  child: Text('正在调整画面…'),
                ),
              ),
            ),
          ),
        if (!loading &&
            !presentation.connecting &&
            (presentation.error != null || presentation.paused) &&
            presentation.errorCode != 'device_asleep')
          recovery,
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
                for (final action in ['down', 'up']) {
                  unawaited(
                    inputs.send(ApplicationCommand.sessionKey, {
                      'keyCode': 66,
                      'action': action,
                    }),
                  );
                }
              },
            ),
          ),
        if (needsWake)
          Positioned(
            left: 0,
            right: 0,
            bottom: math.max(MediaQuery.paddingOf(context).bottom, 24) + 48,
            child: Center(
              child: GlassActionIcon(
                tooltip: '点亮屏幕',
                onPressed: onWake,
                icon: Icon(
                  LucideIcons.sun,
                  color: loading
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.white,
                ),
              ),
            ),
          ),
        if (waiting)
          Positioned(
            left: MediaQuery.paddingOf(context).left + 20,
            top: MediaQuery.paddingOf(context).top + 12,
            child: GlassActionIcon(
              key: const ValueKey('remote-first-frame-close'),
              tooltip: '关闭等待',
              onPressed: onClose,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: const Icon(LucideIcons.x),
            ),
          )
        else
          controls,
      ],
    );
  }
}
