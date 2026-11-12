import 'package:flutter/painting.dart';
import 'package:scrcpy_connect/core/content/content_cache_lease.dart';

/// Flutter 异步读取和解码图片期间持续保护缓存，包含首帧前页面或网格项已移除的情况。
class CachedFileImage extends FileImage {
  const CachedFileImage(super.file, {this.lease});
  final ContentCacheLease? lease;

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) {
    final release = lease?.hold();
    final completer = super.loadImage(key, decode);
    if (release != null) {
      late ImageStreamListener listener;
      void finish() {
        completer.removeListener(listener);
        release();
      }

      listener = ImageStreamListener((image, _) {
        image.dispose();
        finish();
      }, onError: (Object _, StackTrace? _) => finish());
      completer.addListener(listener);
    }
    return completer;
  }
}
