import 'package:scrcpy_connect/core/control/video_display.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart'
    show RequestFailure;

/// 在当前编码器上限内求解产品宽高比，并保留偶数像素及极窄视口的比例。
class VirtualDisplayPolicy {
  static VideoDisplaySize fit(VideoDisplaySize size, int maxSize) {
    final (:width, :height) = size;
    if (width < 2 ||
        height < 2 ||
        width > 4096 ||
        height > 4096 ||
        maxSize < 320 ||
        maxSize > 4096) {
      throw const RequestFailure('invalid_argument', '独立显示尺寸或编码器上限无效。');
    }
    final longest = width > height ? width : height;
    final limit = maxSize ~/ 2 * 2;
    int scaled(int side, int ceiling) {
      final even = (side * ceiling + longest) ~/ (2 * longest) * 2;
      return even < 2 ? 2 : even;
    }

    var fittedWidth = width;
    var fittedHeight = height;
    if (longest > limit) {
      fittedWidth = scaled(width, limit);
      fittedHeight = scaled(height, limit);
      final ratio = width / height;
      // 极窄自动视口的短边取整可能损失比例精度；优先选择比例误差在 0.5% 且绝对误差在 0.008 内的最大偶数尺寸。
      // 像素不足时保留最大尺寸。
      for (var ceiling = limit; ceiling >= 2; ceiling -= 2) {
        final candidateWidth = scaled(width, ceiling);
        final candidateHeight = scaled(height, ceiling);
        final error = (candidateWidth / candidateHeight - ratio).abs();
        if (error <= .008 && error / ratio <= .005) {
          fittedWidth = candidateWidth;
          fittedHeight = candidateHeight;
          break;
        }
      }
    }
    return (width: fittedWidth, height: fittedHeight);
  }
}
