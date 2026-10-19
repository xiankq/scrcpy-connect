import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../benchmark/glass_metrics.dart';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

const _sceneNames = <String>[
  'regular-light',
  'regular-light-pressed',
  'regular-light-scrolled',
  'regular-dark',
  'clear-bright',
  'clear-dark',
  'reduced-light',
  'reduced-light-scrolled',
  'reduced-dark',
  'motion-rest',
  'motion-held',
  'motion-drag',
  'motion-repress',
  'motion-recovered',
  'reduced-motion-pressed',
  'blend-near',
  'blend-separated',
  'navigation-travel',
  'menu-open',
  'menu-cancelled',
  'exit-held',
  'exit-recovered',
  'regular-photo',
  'clear-photo',
];

Future<void> main() async {
  final directory = Directory(
    Platform.environment['CONNECT_GLASS_CAPTURE_DIR'] ??
        '/tmp/connect-glass-material',
  );
  // Keep diagnostic artifacts out of the repository, including via symlinks.
  if (!directory.isAbsolute ||
      !directory.path.startsWith('/tmp/') ||
      directory.path.split('/').contains('..')) {
    throw StateError('CONNECT_GLASS_CAPTURE_DIR must be a path below /tmp/.');
  }
  var existingParent = directory;
  while (!await existingParent.exists()) {
    existingParent = existingParent.parent;
  }
  final parentPath = await existingParent.resolveSymbolicLinks();
  if (parentPath != '/tmp' && !parentPath.startsWith('/tmp/')) {
    throw StateError('Capture parent must resolve below /tmp/.');
  }
  await directory.create(recursive: true);
  final resolved = await directory.resolveSymbolicLinks();
  if (!resolved.startsWith('/tmp/')) {
    throw StateError('CONNECT_GLASS_CAPTURE_DIR must resolve below /tmp/.');
  }
  final captures = <String, Map<String, dynamic>>{};
  final captureBytes = <String, List<int>>{};
  await integrationDriver(
    driver: await FlutterDriver.connect(),
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      if (!_sceneNames.contains(name) || captures.containsKey(name)) {
        throw StateError('Unexpected or duplicate Glass screenshot: $name');
      }
      final dimensions = _pngDimensions(bytes);
      final file = File('$resolved/$name.png');
      await file.writeAsBytes(bytes, flush: true);
      captureBytes[name] = bytes;
      captures[name] = <String, dynamic>{
        'path': file.path,
        'width': dimensions.$1,
        'height': dimensions.$2,
        'bytes': bytes.length,
      };
      return true;
    },
    responseDataCallback: (data) async {
      final report = <String, dynamic>{...?data}..remove('screenshots');
      report['hostCaptures'] = captures;
      // Preserve partial evidence on failure; validation always fails closed.
      try {
        validateGlassMaterialReport(report);
        report.addAll(summarizeGlassPerformance(report));
        // Read the actual captured pixels, independently of the scene receipt.
        // A correct JSON theme/variant cannot make a stale screenshot pass.
        for (final value in report['scenes'] as List<dynamic>) {
          final scene = value as Map<String, dynamic>;
          final name = scene['name'] as String;
          final actual = readGlassSceneMarker(
            captureBytes[name]!,
            (scene['markerBounds'] as List<dynamic>).cast<num>(),
            scene['devicePixelRatio'] as num,
          );
          captures[name]!['pixelMarkerCode'] = actual;
          if (actual != scene['markerCode']) {
            throw StateError(
              'Stale/mislabeled PNG $name: expected pixel marker '
              '${scene['markerCode']}, found $actual. Inspect its visible scene stamp.',
            );
          }
        }
        report['sceneMarkerPixelValidationComplete'] = true;
        report['hostValidationComplete'] = true;
      } catch (error) {
        report['hostValidationComplete'] = false;
        report['hostValidationError'] = error.toString();
        rethrow;
      } finally {
        await File('$resolved/result.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      }
    },
  );
}

/// Validates the independent Glass capture contract, not product/backend flows.
/// It intentionally does not certify perceptual quality or Apple equivalence.
void validateGlassMaterialReport(Map<String, dynamic> report) {
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  require(report['schemaVersion'] == 2, 'Missing Glass report schema.');
  require(report['scope'] == 'glass-material', 'Wrong acceptance scope.');
  require(report['platform'] == 'android', 'Android runtime was not used.');
  for (final key in <String>[
    'shaderImageFiltersSupported',
    'shaderProgramsLoaded',
    'surfaceConverted',
    'functionalAcceptanceComplete',
    'opticalCaptureComplete',
    'harnessComplete',
    'visualReviewRequired',
  ]) {
    require(report[key] == true, 'Glass acceptance missing: $key.');
  }
  require(
    report['backend'] == 'liquid_glass_widgets' &&
        report['backendVersion'] == '1.13.0',
    'Wrong production material backend.',
  );
  require(report['fallbackEnabled'] == false, 'Fallback was enabled.');
  require(
    report['nativeSurfaceDuringTiming'] == true,
    'Timing must precede Android ImageView screenshot conversion.',
  );
  require(
    report['debugPointerOverlay'] == false &&
        report['tooltipsVisible'] == false,
    'Debug decorations contaminate captures.',
  );
  require(
    report['dynamicCaptureComplete'] == true &&
        report['performanceCaptureComplete'] == true,
    'Missing dynamic or timing evidence.',
  );
  require(
    report['visualAcceptanceComplete'] == false,
    'The capture harness cannot declare a human visual review passed.',
  );
  final sceneData = report['scenes'];
  final captureData = report['hostCaptures'];
  require(sceneData is List<dynamic>, 'Missing scene receipts.');
  require(captureData is Map<String, dynamic>, 'Missing host screenshots.');
  final scenes = sceneData as List<dynamic>;
  final captures = captureData as Map<String, dynamic>;
  require(scenes.length == _sceneNames.length, 'Incomplete scene receipts.');
  require(captures.length == _sceneNames.length, 'Incomplete PNG captures.');
  int? physicalWidth;
  int? physicalHeight;
  for (var index = 0; index < _sceneNames.length; index++) {
    final name = _sceneNames[index];
    final value = scenes[index];
    require(value is Map<String, dynamic>, 'Invalid receipt: $name.');
    final scene = value as Map<String, dynamic>;
    require(scene['name'] == name, 'Scene order/name mismatch: $name.');
    require(
      scene['markerCode'] == (0xa500 | (index + 1)),
      'Missing or incorrect scene pixel marker: $name.',
    );
    final marker = scene['markerBounds'];
    require(
      marker is List<dynamic> &&
          marker.length == 4 &&
          marker.every((v) => v is num && v.isFinite),
      'Missing scene marker bounds: $name.',
    );
    final reduced = [
      'reduced-light',
      'reduced-light-scrolled',
      'reduced-dark',
    ].contains(name);
    final production = [
      'navigation-travel',
      'menu-open',
      'menu-cancelled',
      'exit-held',
      'exit-recovered',
    ].contains(name);
    final blend = name.startsWith('blend-');
    final clear = name.startsWith('clear-');
    final photo = name.endsWith('-photo');
    require(
      scene['reduceTransparency'] == reduced,
      'Incorrect accessibility mode: $name.',
    );
    require(
      scene['variant'] == (clear ? 'clear' : 'regular'),
      'Incorrect material variant: $name.',
    );
    require(
      scene['brightness'] == (name.endsWith('dark') ? 'dark' : 'light'),
      'Incorrect theme: $name.',
    );
    require(
      scene['background'] ==
          (photo
              ? 'repository-photo'
              : clear
              ? 'geometric-media'
              : 'lines-text-checks'),
      'Incorrect background: $name.',
    );
    require(
      scene['optics'] == (reduced ? 'skipped-reduced-transparency' : 'shader'),
      'Fallback or missing optical receipt: $name.',
    );
    require(
      scene['productionDemo'] == production,
      'Missing production interaction scene: $name.',
    );
    if (!reduced) {
      final settings = scene['opticalSettings'];
      require(
        settings is Map &&
            settings['bodyMode'] == (clear ? 'clear' : 'adaptive') &&
            settings['blurSigmaLogicalPx'] is num &&
            (settings['blurSigmaLogicalPx'] as num) > 0,
        'Missing or incorrect production optical settings: $name.',
      );
    }
    require(scene['lightweightSurfaceCount'] == 0, 'Lite fallback in $name.');
    require(scene['blurWidgetCount'] == 0, 'Blur-only fallback in $name.');
    if (photo) {
      final sources = report['photoSources'];
      require(sources is Map, 'Missing real photo receipts.');
      final source = (sources as Map)[name];
      require(source is Map, 'Missing decoded photo: $name.');
      final receipt = source as Map;
      require(
        receipt['imageStreamComplete'] == true &&
            receipt['path'] == scene['photoPath'] &&
            receipt['bytes'] is num &&
            (receipt['bytes'] as num) > 0 &&
            receipt['decodedWidth'] is num &&
            (receipt['decodedWidth'] as num) > 0 &&
            receipt['decodedHeight'] is num &&
            (receipt['decodedHeight'] as num) > 0,
        'Photo was not really loaded: $name.',
      );
    }
    final lensCount = scene['surfaceCount'];
    require(
      production
          ? lensCount is int && lensCount >= 5
          : lensCount ==
                (reduced
                    ? 0
                    : clear
                    ? 2
                    : blend
                    ? 5
                    : 4),
      'Optics were not enabled/removed as requested: $name.',
    );
    require(
      scene['reduceMotion'] == (name == 'reduced-motion-pressed'),
      'Incorrect reduced motion policy: $name.',
    );
    require(
      scene['layerCount'] is int &&
          (reduced
              ? scene['layerCount'] == 0
              : (scene['layerCount'] as int) > 0),
      'Missing actual backend layers: $name.',
    );
    if (blend) {
      require(
        scene['blendGroupCount'] is int && scene['blendGroupCount'] == 1,
        'Fusion demo bypassed shared group geometry.',
      );
    }
    final offset = scene['backgroundOffset'];
    require(
      offset is num &&
          offset.isFinite &&
          (name.endsWith('scrolled') ? offset > 100 : offset == 0),
      'Background did not reach its required position: $name.',
    );
    final captureValue = captures[name];
    require(captureValue is Map<String, dynamic>, 'Missing PNG: $name.');
    final capture = captureValue as Map<String, dynamic>;
    final width = capture['width'];
    final height = capture['height'];
    require(
      width is int && width >= 320 && height is int && height >= 480,
      'Invalid screenshot size: $name.',
    );
    physicalWidth ??= width as int;
    physicalHeight ??= height as int;
    require(
      width == physicalWidth && height == physicalHeight,
      'Screenshot viewport changed: $name.',
    );
    require(
      scene['physicalWidth'] == width && scene['physicalHeight'] == height,
      'PNG does not match the actual device viewport: $name.',
    );
    final dpr = scene['devicePixelRatio'];
    require(dpr is num && dpr.isFinite && dpr > 0, 'Missing DPR: $name.');
    final boundsValue = scene['controls'];
    require(boundsValue is Map<String, dynamic>, 'Missing control bounds.');
    final bounds = boundsValue as Map<String, dynamic>;
    final expectedControls = clear
        ? <String>{'close', 'toolbar'}
        : <String>{'close', 'toolbar', 'panel', 'tabs'};
    require(
      bounds.keys.toSet().containsAll(expectedControls) &&
          bounds.length == expectedControls.length,
      'Missing controls: $name.',
    );
    for (final entry in bounds.entries) {
      final rect = entry.value;
      require(
        rect is List<dynamic> &&
            rect.length == 4 &&
            rect.every((v) => v is num && v.isFinite),
        'Invalid control bounds: $name/${entry.key}.',
      );
      final values = (rect as List<dynamic>).cast<num>();
      require(
        values[0] >= 0 &&
            values[1] >= 0 &&
            values[2] > 0 &&
            values[3] > 0 &&
            (values[0] + values[2]) * (dpr as num) <= (width as int) + 1 &&
            (values[1] + values[3]) * dpr <= (height as int) + 1,
        'Clipped control: $name/${entry.key}.',
      );
      if (entry.key != 'panel') {
        require(
          values[2] >= 44 && values[3] >= 44,
          'Undersized target: $name/${entry.key}.',
        );
      }
    }
  }
  final interactionValue = report['interactions'];
  require(interactionValue is Map<String, dynamic>, 'Missing interactions.');
  final interactions = interactionValue as Map<String, dynamic>;
  for (final name in <String>[
    'cancelDoesNotActivate',
    'tapAfterCancel',
    'toolbarTap',
    'tabSelection',
    'tapAfterBackgroundScroll',
    'clearToolbarTap',
    'reducedControlsOperate',
    'interruptedRecovery',
    'reducedMotionNoGeometry',
    'realBlendGroup',
    'navigationRedirectAndReducedMotion',
    'productionMenuOpenCancelAction',
    'productionMenuReducedMotion',
    'actualExitHandleFeedbackCancelTap',
  ]) {
    require(interactions[name] == true, 'Unverified interaction: $name.');
  }
  final motion = report['motionSamples'];
  require(
    motion is List && motion.length >= 50,
    'Missing real multi-frame presentation samples.',
  );
  final phases = (motion as List).map((v) => (v as Map)['phase']).toSet();
  require(
    phases.containsAll({
      'press',
      'drag',
      'cancel',
      'repress',
      'recovery',
      'reduced-motion-press',
    }),
    'Incomplete interruption sequence.',
  );
  for (final raw in motion) {
    final item = raw as Map;
    final bounds = item['bounds'];
    require(
      bounds is List &&
          bounds.length == 4 &&
          bounds.every((n) => n is num && n.isFinite),
      'Invalid presentation sample.',
    );
  }
  final performance = report['performance'];
  require(
    performance is List && performance.length == 4,
    'Missing measured real-vsync workload windows.',
  );
  for (final raw in performance as List) {
    final sample = raw as Map;
    require(
      sample['frames'] is List && (sample['frames'] as List).isNotEmpty,
      'No actual FrameTiming samples.',
    );
    require(
      sample['screenshotsDuringMeasurement'] == 0 &&
          sample['backgroundPaints'] is int &&
          (sample['backgroundPaints'] as int) > 2,
      'Timing window is static or contaminated by captures.',
    );
  }
  final distance = interactions['backgroundScrollDistance'];
  require(
    distance is num && distance.isFinite && distance > 100,
    'No actual drag beneath the fixed controls.',
  );
}

/// Decodes the small black/white stamp from PNG pixels, without a Flutter
/// renderer or trusting the report's requested theme. Android PixelCopy emits
/// non-interlaced 8-bit RGB/RGBA PNGs; unsupported encodings fail closed.
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
