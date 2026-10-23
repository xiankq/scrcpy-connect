import 'package:flutter/widgets.dart';

import 'controller.dart';

/// Presents a native decoded texture inside the Flutter scene.
/// Ownership remains with the caller, so route changes cannot stop capture.
class MediaCodecView extends StatelessWidget {
  const MediaCodecView({
    super.key,
    required this.textureId,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.low,
  });

  factory MediaCodecView.controller(
    MediaCodecController controller, {
    Key? key,
    BoxFit fit = BoxFit.contain,
  }) => MediaCodecView(
    key: key,
    textureId: controller.textureId,
    width: controller.width,
    height: controller.height,
    fit: fit,
  );

  final int? textureId;
  final int width, height;
  final BoxFit fit;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    if (textureId == null || width < 1 || height < 1) {
      return const SizedBox.expand();
    }
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: fit,
          child: SizedBox(
            width: width.toDouble(),
            height: height.toDouble(),
            child: Texture(textureId: textureId!, filterQuality: filterQuality),
          ),
        ),
      ),
    );
  }
}
