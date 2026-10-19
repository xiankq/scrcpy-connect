// Standalone protocol regression; no Flutter runner or native build is needed.
// Run: dart tool/driver/support/android_screencap_test.dart
import 'dart:io';
import 'dart:typed_data';

import '../../benchmark/live_video/android_screencap.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Uint8List capture({
  int width = 2,
  int height = 2,
  int format = 1,
  int colorSpace = 1,
  List<int> pixels = const [
    255,
    0,
    0,
    255,
    0,
    255,
    0,
    127,
    0,
    0,
    255,
    63,
    17,
    29,
    41,
    255,
  ],
}) {
  final bytes = Uint8List(16 + pixels.length);
  final header = ByteData.sublistView(bytes);
  header.setUint32(0, width, Endian.little);
  header.setUint32(4, height, Endian.little);
  header.setUint32(8, format, Endian.little);
  header.setUint32(12, colorSpace, Endian.little);
  bytes.setRange(16, bytes.length, pixels);
  return bytes;
}

void rejects(Uint8List bytes, String detail) {
  try {
    AndroidRgbaScreenshot.parse(bytes);
  } on FormatException catch (error) {
    check(error.message.contains(detail), 'Unexpected rejection: $error');
    return;
  }
  throw StateError('Accepted invalid screencap: $detail');
}

void main() {
  final bytes = capture();
  final screenshot = AndroidRgbaScreenshot.parse(bytes);
  check(screenshot.width == 2 && screenshot.height == 2, 'Wrong dimensions.');
  check(screenshot.format == 1 && screenshot.colorSpace == 1, 'Wrong header.');
  check(
    screenshot.rgba.join(',') ==
        '255,0,0,255,0,255,0,127,0,0,255,63,17,29,41,255',
    'RGBA order or packed row layout changed.',
  );

  // ADB output may itself be a view into a socket buffer with a nonzero offset.
  final backing = Uint8List(bytes.length + 11);
  backing.setRange(5, 5 + bytes.length, bytes);
  final nested = AndroidRgbaScreenshot.parse(
    Uint8List.sublistView(backing, 5, 5 + bytes.length),
  );
  check(
    nested.rgba.length == 16,
    'Pixel view contains header or trailing data.',
  );
  check(nested.rgba.offsetInBytes == 21, 'Lost source view offset.');
  backing[21] = 73;
  check(nested.rgba[0] == 73, 'Pixel payload is not a live buffer view.');

  final nonsquare = AndroidRgbaScreenshot.parse(
    capture(
      width: 1,
      height: 2,
      colorSpace: 2,
      pixels: [1, 2, 3, 4, 5, 6, 7, 8],
    ),
  );
  check(
    nonsquare.width == 1 && nonsquare.height == 2,
    'Header fields swapped.',
  );
  check(nonsquare.colorSpace == 2, 'Color space was not preserved.');
  check(
    AndroidRgbaScreenshot.parse(capture(colorSpace: 0)).colorSpace == 0,
    'Android unknown color-space code should be preserved.',
  );

  for (var length = 0; length < 16; length++) {
    rejects(Uint8List.sublistView(bytes, 0, length), '16-byte');
  }
  rejects(Uint8List.sublistView(bytes, 0, bytes.length - 1), 'length');
  rejects(Uint8List.fromList([...bytes, 0]), 'length');
  // Old Android headers omit the color-space word; never infer that layout.
  rejects(Uint8List.fromList([...bytes.take(12), ...bytes.skip(16)]), 'length');
  rejects(capture(width: 0), 'dimensions');
  rejects(capture(height: 0), 'dimensions');
  rejects(capture(width: 8193), 'dimensions');
  rejects(capture(height: 8193), 'dimensions');
  rejects(capture(width: 0xffffffff, height: 0xffffffff), 'dimensions');
  rejects(capture(width: 2048, height: 2048), 'byte limit');
  for (final format in [0, 2, 3, 4, 5, 0xffffffff]) {
    rejects(capture(format: format), 'RGBA_8888');
  }
  stdout.writeln(
    'PASS: Android packed RGBA screencap header, view and rejection bounds.',
  );
}
