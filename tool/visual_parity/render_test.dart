import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final environment = Platform.environment;
  final configPath = environment['CONNECT_PARITY_CONFIG'];
  if (configPath == null) return;
  testWidgets('compare explicitly paired design and production captures', (
    tester,
  ) async {
    final report = await tester.runAsync(() async {
      final config = jsonDecode(await File(configPath).readAsString()) as Map;
      if (config['version'] != 1 ||
          config['cases'] is! List ||
          (config['cases'] as List).isEmpty) {
        throw const FormatException('Expected version 1 and nonempty cases');
      }
      final output = Directory(environment['CONNECT_PARITY_OUTPUT']!);
      await output.create(recursive: true);
      final flutterDirectory = environment['CONNECT_PARITY_FLUTTER']!;
      final layoutFile = File(
        '$flutterDirectory/${config['layoutContract'] ?? 'layout-contract.json'}',
      );
      Map<String, dynamic>? layoutContract;
      String? layoutError;
      if (await layoutFile.exists()) {
        try {
          layoutContract = Map<String, dynamic>.from(
            jsonDecode(await layoutFile.readAsString()) as Map,
          );
          if (layoutContract['version'] != 1 ||
              layoutContract['captures'] is! Map) {
            throw const FormatException('Invalid layout contract');
          }
        } on Object catch (error) {
          layoutContract = null;
          layoutError = '$error';
        }
      }
      final cases = <Map<String, Object?>>[];
      final identifiers = <String>{};
      for (final entry in config['cases'] as List) {
        final item = Map<String, dynamic>.from(entry as Map);
        final id = item['id'] as String;
        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) || !identifiers.add(id)) {
          throw FormatException('Invalid or duplicate case id: $id');
        }
        final result = <String, Object?>{
          'id': id,
          'pencilFrame': item['pencilFrame'],
          'route': item['route'],
          'pencilCrop': item['pencilCrop'],
          'flutterCrop': item['flutterCrop'],
          'sourceCornerRadius': item['sourceCornerRadius'] ?? 0,
          'captureScope': item['captureScope'],
          'comparisonScope': item['comparisonScope'],
          'fixtureContentDifferences': item['fixtureContentDifferences'] ?? [],
          'contentAcceptanceComplete': false,
        };
        for (final suffix in ['side-by-side', 'difference']) {
          final previous = File('${output.path}/$id-$suffix.png');
          if (await previous.exists()) await previous.delete();
        }
        final designFile = File(
          '${environment['CONNECT_PARITY_PENCIL']}/${item['pencil']}',
        );
        final flutterFile = File(
          '${environment['CONNECT_PARITY_FLUTTER']}/${item['flutter']}',
        );
        result['inputs'] = {
          'pencil': designFile.absolute.path,
          'flutter': flutterFile.absolute.path,
        };
        final missing = <String>[
          if (!await designFile.exists()) designFile.path,
          if (!await flutterFile.exists()) flutterFile.path,
        ];
        if (missing.isNotEmpty) {
          result.addAll({'status': 'missing-input', 'missing': missing});
          cases.add(result);
          continue;
        }
        ui.Image? design;
        ui.Image? flutter;
        try {
          final designBytes = await designFile.readAsBytes();
          final flutterBytes = await flutterFile.readAsBytes();
          result['inputSha256'] = {
            'pencil': sha256.convert(designBytes).toString(),
            'flutter': sha256.convert(flutterBytes).toString(),
          };
          final layout = layoutContract?['captures'][item['flutter']];
          result['flutterLayout'] =
              layout is Map &&
                  layout['screenshotSha256'] ==
                      sha256.convert(flutterBytes).toString()
              ? {'status': 'associated', ...Map<String, dynamic>.from(layout)}
              : {
                  'status': layout == null ? 'unavailable' : 'stale',
                  'reason':
                      layoutError ??
                      (layout == null
                          ? 'No layout entry for this screenshot; rerun capture.'
                          : 'Screenshot SHA-256 differs; geometry was not attached.'),
                };
          design = await _decode(designBytes);
          flutter = await _decode(flutterBytes);
          result['sourceDimensions'] = {
            'pencil': [design.width, design.height],
            'flutter': [flutter.width, flutter.height],
          };
          final sourceWidth = item['sourceWidth'] as int?;
          final sourceHeight = item['sourceHeight'] as int?;
          if ((sourceWidth != null &&
                  (design.width != sourceWidth ||
                      flutter.width != sourceWidth)) ||
              (sourceHeight != null &&
                  (design.height != sourceHeight ||
                      flutter.height != sourceHeight))) {
            result.addAll({
              'status': 'dimension-mismatch',
              'expectedSourceDimensions': [sourceWidth, sourceHeight],
            });
            cases.add(result);
            continue;
          }
          final radius = (item['sourceCornerRadius'] as num?)?.toDouble() ?? 0;
          design = await _crop(design, item['pencilCrop'], radius);
          flutter = await _crop(flutter, item['flutterCrop'], radius);
          final width = item['width'] as int;
          final height = item['height'] as int;
          result['expectedDimensions'] = [width, height];
          result['comparisonDimensions'] = {
            'pencil': [design.width, design.height],
            'flutter': [flutter.width, flutter.height],
          };
          if (design.width != width ||
              design.height != height ||
              flutter.width != width ||
              flutter.height != height) {
            result['status'] = 'dimension-mismatch';
          } else {
            final a = (await design.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba,
            ))!;
            final b = (await flutter.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba,
            ))!;
            final difference = Uint8List(width * height * 4);
            var changedPixels = 0;
            var absoluteError = 0;
            for (var offset = 0; offset < difference.length; offset += 4) {
              var changed = false;
              for (var channel = 0; channel < 3; channel++) {
                // 比较各输入在白色画布上的显示，包括透明 PNG 像素；alpha 通道不计作 RGB 误差。
                //
                final first = _onWhite(a, offset, channel);
                final second = _onWhite(b, offset, channel);
                final delta = (first - second).abs();
                difference[offset + channel] = delta;
                absoluteError += delta;
                changed = changed || delta != 0;
              }
              difference[offset + 3] = 255;
              if (changed) changedPixels++;
            }
            final recorder = ui.PictureRecorder();
            final canvas = ui.Canvas(recorder);
            canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
            canvas.drawImage(design, ui.Offset.zero, ui.Paint());
            canvas.drawImage(
              flutter,
              ui.Offset(width.toDouble(), 0),
              ui.Paint(),
            );
            final picture = recorder.endRecording();
            final sideBySide = await picture.toImage(width * 2, height);
            picture.dispose();
            await _save(sideBySide, '${output.path}/$id-side-by-side.png');
            sideBySide.dispose();
            final differenceImage = await _fromRgba(difference, width, height);
            await _save(differenceImage, '${output.path}/$id-difference.png');
            differenceImage.dispose();
            result.addAll({
              'status': 'compared',
              'changedPixelFraction': changedPixels / (width * height),
              'meanAbsoluteRgbError': absoluteError / (width * height * 3),
              'sideBySide': '$id-side-by-side.png',
              'difference': '$id-difference.png',
            });
          }
        } on Object catch (error) {
          result.addAll({'status': 'input-error', 'error': '$error'});
        } finally {
          design?.dispose();
          flutter?.dispose();
        }
        cases.add(result);
      }
      final report = <String, Object?>{
        'version': 1,
        'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
        'config': File(configPath).absolute.path,
        'layoutContract': layoutFile.absolute.path,
        'unmatchedCaptures': config['unmatchedCaptures'] ?? {},
        'completed': cases.every((entry) => entry['status'] == 'compared'),
        'visualAcceptanceComplete': false,
        'interpretation':
            'Pixel errors are review aids, not geometric acceptance. Review '
            'layout, typography, content, safe areas and optical materials '
            'separately; no resizing or automatic acceptance is performed.',
        'cases': cases,
      };
      await File('${output.path}/report.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      return report;
    });
    expect(
      report!['completed'],
      isTrue,
      reason: 'Missing images, decode errors or dimension mismatch: see report.json',
    );
  });
}

int _onWhite(ByteData data, int offset, int channel) {
  final alpha = data.getUint8(offset + 3);
  return (data.getUint8(offset + channel) * alpha +
          255 * (255 - alpha) +
          127) ~/
      255;
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// 显式 [x, y, width, height] 裁剪，不缩放或填补任一输入。
Future<ui.Image> _crop(ui.Image source, Object? crop, double radius) async {
  if (crop == null && radius == 0) return source;
  final values = crop == null
      ? [0, 0, source.width, source.height]
      : (crop as List).cast<int>();
  if (values.length != 4 ||
      values[0] < 0 ||
      values[1] < 0 ||
      values[2] <= 0 ||
      values[3] <= 0 ||
      values[0] + values[2] > source.width ||
      values[1] + values[3] > source.height) {
    throw FormatException('Crop outside source image: $crop');
  }
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // 相同白色遮罩仅移除实体手机轮廓，保留内容差异；遮罩先在源坐标声明，再执行裁剪。
  //
  canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
  if (radius > 0) {
    canvas.clipRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(
          -values[0].toDouble(),
          -values[1].toDouble(),
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        ui.Radius.circular(radius),
      ),
    );
  }
  canvas.drawImage(
    source,
    ui.Offset(-values[0].toDouble(), -values[1].toDouble()),
    ui.Paint(),
  );
  final picture = recorder.endRecording();
  final result = await picture.toImage(values[2], values[3]);
  picture.dispose();
  source.dispose();
  return result;
}

Future<ui.Image> _fromRgba(Uint8List bytes, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

Future<void> _save(ui.Image image, String path) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  await File(path).writeAsBytes(data.buffer.asUint8List());
}
