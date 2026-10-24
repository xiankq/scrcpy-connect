import 'dart:typed_data';

/// 现代 Android 不带 -p 的 screencap 紧凑输出。
///
/// AOSP 先写四个本机 uint32（宽、高、像素格式、色彩空间），
/// 随后每行写 width × bytes-per-pixel，省略 GraphicBuffer 填充：
/// https://android.googlesource.com/platform/frameworks/base/+/master/cmds/screencap/screencap.cpp
/// 本基准只支持已知的小端 Android RGBA_8888 布局，
/// 不猜测旧的 12 字节头，也不转换其他像素格式。
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
    // surface 命令最多允许 16 Mi 个 base64 字符。
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
    // 相乘前先限制两个维度，Dart VM 路径也遵循此规则。
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
