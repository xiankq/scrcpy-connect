import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

int readGlassSceneMarker(List<int> png, List<num> bounds, num dpr) {
  final (width, height) = _pngDimensions(png);
  final header = ByteData.sublistView(Uint8List.fromList(png));
  final channels = png[25] == 6
      ? 4
      : png[25] == 2
      ? 3
      : 0;
  if (png[24] != 8 ||
      channels == 0 ||
      png[26] != 0 ||
      png[27] != 0 ||
      png[28] != 0) {
    throw StateError(
      'Scene marker requires an 8-bit RGB/RGBA non-interlaced PNG.',
    );
  }
  final compressed = BytesBuilder(copy: false);
  for (var position = 8; position + 12 <= png.length;) {
    final length = header.getUint32(position);
    final end = position + 12 + length;
    if (end > png.length) throw StateError('Truncated screenshot PNG chunk.');
    final type = ascii.decode(png.sublist(position + 4, position + 8));
    if (type == 'IDAT') {
      compressed.add(png.sublist(position + 8, position + 8 + length));
    }
    position = end;
    if (type == 'IEND') break;
  }
  final decoded = ZLibDecoder().convert(compressed.takeBytes());
  final stride = width * channels;
  if (decoded.length != height * (stride + 1)) {
    throw StateError('Invalid screenshot PNG scanline length.');
  }
  final pixels = Uint8List(height * stride);
  int paeth(int left, int up, int corner) {
    final estimate = left + up - corner;
    final a = (estimate - left).abs();
    final b = (estimate - up).abs();
    final c = (estimate - corner).abs();
    return a <= b && a <= c
        ? left
        : b <= c
        ? up
        : corner;
  }

  for (var y = 0; y < height; y++) {
    final source = y * (stride + 1);
    final filter = decoded[source];
    if (filter > 4) throw StateError('Invalid screenshot PNG filter.');
    for (var x = 0; x < stride; x++) {
      final target = y * stride + x;
      final left = x >= channels ? pixels[target - channels] : 0;
      final up = y > 0 ? pixels[target - stride] : 0;
      final corner = y > 0 && x >= channels
          ? pixels[target - stride - channels]
          : 0;
      final predictor = switch (filter) {
        0 => 0,
        1 => left,
        2 => up,
        3 => (left + up) ~/ 2,
        4 => paeth(left, up, corner),
        _ => throw StateError('Invalid screenshot PNG filter.'),
      };
      pixels[target] = (decoded[source + x + 1] + predictor) & 255;
    }
  }
  if (bounds.length != 4 || dpr <= 0 || bounds[2] <= 0 || bounds[3] <= 0) {
    throw StateError('Invalid scene marker geometry.');
  }
  var code = 0;
  for (var bit = 0; bit < 16; bit++) {
    final x = ((bounds[0] + bounds[2] * (bit + .5) / 16) * dpr).floor();
    final y = ((bounds[1] + bounds[3] / 2) * dpr).floor();
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw StateError('Scene marker lies outside screenshot pixels.');
    }
    final offset = y * stride + x * channels;
    final rgb = pixels.sublist(offset, offset + 3);
    final white = rgb.every((channel) => channel > 223);
    final black = rgb.every((channel) => channel < 32);
    if (!white && !black) {
      throw StateError('Scene marker pixel is absent or obscured at bit $bit.');
    }
    code = (code << 1) | (white ? 1 : 0);
  }
  return code;
}

(int, int) _pngDimensions(List<int> bytes) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 33 ||
      !Iterable<int>.generate(8).every((i) => bytes[i] == signature[i]) ||
      ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR') {
    throw StateError('Screenshot was not a PNG with an IHDR header.');
  }
  final header = ByteData.sublistView(Uint8List.fromList(bytes));
  return (header.getUint32(16), header.getUint32(20));
}
