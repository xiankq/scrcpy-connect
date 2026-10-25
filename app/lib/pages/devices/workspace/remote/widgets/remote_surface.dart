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
