import 'package:flutter/painting.dart';
import 'package:scrcpy_connect/services/media_cache_lease.dart';

/// Keep a cache file protected while Flutter's asynchronous image read/decode
/// settles, including when the cell/page is removed before the first frame.
class CachedFileImage extends FileImage {
  const CachedFileImage(super.file, {this.lease});
  final MediaCacheLease? lease;

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
