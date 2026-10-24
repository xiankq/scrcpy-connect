import 'package:flutter/widgets.dart';

import 'controller.dart';

/// 在 Flutter 场景中呈现原生解码纹理。
/// 调用方持有所有权，路由变化不能停止捕获。
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
