import 'dart:typed_data';

/// Packed output of modern Android `screencap` without `-p`.
///
/// AOSP writes four native uint32 words (width, height, pixel format, color-space
/// code), then width * bytes-per-pixel per row, omitting GraphicBuffer padding:
/// https://android.googlesource.com/platform/frameworks/base/+/master/cmds/screencap/screencap.cpp
/// This benchmark supports the known little-endian Android RGBA_8888 layout
/// only; it never guesses older 12-byte headers or converts other pixel formats.
class AndroidRgbaScreenshot {
  AndroidRgbaScreenshot._(
    this.width,
    this.height,
    this.format,
    this.colorSpace,
    this.rgba,
  );

  factory AndroidRgbaScreenshot.parse(Uint8List bytes) {
    const headerBytes = 16;
    const maxDimension = 8192;
    // The surface command permits at most 16 Mi characters of base64.
    const maxBytes = 12 * 1024 * 1024;
    if (bytes.length < headerBytes) {
      throw const FormatException('Expected modern 16-byte screencap header.');
    }
    final header = ByteData.sublistView(bytes, 0, headerBytes);
    final width = header.getUint32(0, Endian.little);
    final height = header.getUint32(4, Endian.little);
    final format = header.getUint32(8, Endian.little);
    final colorSpace = header.getUint32(12, Endian.little);
    if (width == 0 ||
        height == 0 ||
        width > maxDimension ||
        height > maxDimension) {
      throw const FormatException('Invalid or excessive screencap dimensions.');
    }
    if (format != 1) {
      throw FormatException(
        'Only screencap RGBA_8888 (1) is supported: $format.',
      );
    }
    // Bound both dimensions before multiplication, including on the Dart VM.
    final expectedBytes = headerBytes + width * height * 4;
    if (expectedBytes > maxBytes || bytes.length > maxBytes) {
      throw const FormatException('Screencap exceeds the byte limit.');
    }
    if (bytes.length != expectedBytes) {
      throw FormatException(
        'Screencap length must be exactly $expectedBytes bytes; '
        'got ${bytes.length}. Older headers and row padding are unsupported.',
      );
    }
    return AndroidRgbaScreenshot._(
      width,
      height,
      format,
      colorSpace,
      Uint8List.sublistView(bytes, headerBytes),
    );
  }

  final int width;
  final int height;
  final int format;
  final int colorSpace;
  final Uint8List rgba;
}
