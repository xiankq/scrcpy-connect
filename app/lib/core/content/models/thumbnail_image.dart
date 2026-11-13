import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:scrcpy_connect/core/content/models/thumbnail_source.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 已核验大小、摘要及尺寸的 JPEG；字节不会与协议回执共享可变存储。
final class ThumbnailImage {
  ThumbnailImage._({
    required this.source,
    required this.jpeg,
    required this.digest,
    required this.width,
    required this.height,
  });

  static const maxBytes = 256 * 1024;

  factory ThumbnailImage({
    required ThumbnailSource source,
    required List<int> jpeg,
    required int maxSize,
  }) {
    if (jpeg.length > maxBytes) {
      throw const RequestFailure('invalid_thumbnail', '缩略图数据超过大小限制。');
    }
    final bytes = Uint8List.fromList(jpeg).asUnmodifiableView();
    final (:width, :height) = readDimensions(bytes);
    if (width > maxSize || height > maxSize) {
      throw const RequestFailure('invalid_thumbnail', '缩略图尺寸超过请求范围。');
    }
    return ThumbnailImage._(
      source: source,
      jpeg: bytes,
      digest: crypto.sha256.convert(bytes).toString(),
      width: width,
      height: height,
    );
  }

  factory ThumbnailImage.fromJson(
    Map<String, Object?> response, {
    required int maxSize,
  }) {
    final source = ThumbnailSource.fromJson(response['sourceStamp']);
    if (response['thumbnail'] != true || response['mime'] != 'image/jpeg') {
      throw const RequestFailure('source_changed', '生成期间媒体源或缩略图类型发生变化。');
    }
    final encoded = response['data'];
    if (encoded is! String || encoded.length > ((maxBytes + 2) ~/ 3) * 4) {
      throw const RequestFailure('invalid_thumbnail', '缩略图数据缺失或超过大小限制。');
    }
    final Uint8List jpeg;
    try {
      jpeg = base64Decode(encoded);
    } on FormatException {
      throw const RequestFailure('invalid_thumbnail', '缩略图编码无效。');
    }
    final image = ThumbnailImage(source: source, jpeg: jpeg, maxSize: maxSize);
    if (response['sha256'] != image.digest ||
        response['jpegBytes'] != image.jpeg.length ||
        response['width'] != image.width ||
        response['height'] != image.height) {
      throw const RequestFailure('invalid_thumbnail', '缩略图摘要、大小或尺寸不一致。');
    }
    return image;
  }

  final ThumbnailSource source;
  final Uint8List jpeg;
  final String digest;
  final int width, height;

  static ({int width, int height}) readDimensions(List<int> bytes) {
    const invalid = RequestFailure('invalid_thumbnail', '缩略图 JPEG 结构或尺寸无效。');
    if (bytes.length < 4 ||
        bytes[0] != 255 ||
        bytes[1] != 216 ||
        bytes[bytes.length - 2] != 255 ||
        bytes.last != 217) {
      throw invalid;
    }
    var offset = 2;
    while (offset + 4 <= bytes.length) {
      if (bytes[offset] != 255) throw invalid;
      while (offset < bytes.length && bytes[offset] == 255) {
        offset++;
      }
      if (offset >= bytes.length) throw invalid;
      final marker = bytes[offset++];
      if (marker == 218 || marker == 217) throw invalid;
      if (marker == 1 || marker >= 208 && marker <= 216) continue;
      if (offset + 2 > bytes.length) throw invalid;
      final length = bytes[offset] * 256 + bytes[offset + 1];
      if (length < 2 || offset + length > bytes.length) throw invalid;
      if (marker >= 192 && marker <= 194) {
        if (length < 8 || bytes[offset + 2] != 8) throw invalid;
        final height = bytes[offset + 3] * 256 + bytes[offset + 4],
            width = bytes[offset + 5] * 256 + bytes[offset + 6];
        if (width == 0 || height == 0) throw invalid;
        return (width: width, height: height);
      }
      offset += length;
    }
    throw invalid;
  }
}
