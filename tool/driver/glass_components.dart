import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import 'glass_material.dart' show readGlassSceneMarker;

const _scenes = [
  'background-light',
  'tab-light-rest',
  'tab-light-held',
  'tab-light-dragged',
  'background-dark',
  'tab-dark-rest',
  'tab-dark-held',
  'tab-dark-dragged',
  'dialog-light',
  'tooltip-light',
  'icon-held',
  'opaque-light',
  'opaque-dark',
];

Future<void> main() async {
  final output = Directory(
    Platform.environment['CONNECT_GLASS_COMPONENTS_DIR'] ??
        '/tmp/connect-glass-components/gpu',
  );
  if (!output.isAbsolute ||
      !output.path.startsWith('/tmp/') ||
      output.path.split('/').contains('..')) {
    throw StateError('CONNECT_GLASS_COMPONENTS_DIR must be below /tmp/.');
  }
  var ancestor = output;
  while (!await ancestor.exists()) {
    ancestor = ancestor.parent;
  }
  final parent = await ancestor.resolveSymbolicLinks();
  if (parent != '/tmp' && !parent.startsWith('/tmp/')) {
    throw StateError('Capture directory escapes /tmp/ through a symlink.');
  }
  await output.create(recursive: true);
  final resolved = await output.resolveSymbolicLinks();
  if (!resolved.startsWith('/tmp/')) throw StateError('Unsafe capture path.');
  for (final name in [..._scenes.map((name) => '$name.png'), 'result.json']) {
    final file = File('$resolved/$name');
    if (await file.exists()) await file.delete();
  }
  final captures = <String, Map<String, dynamic>>{};
  final pixels = <String, List<int>>{};
  await integrationDriver(
    driver: await FlutterDriver.connect(),
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      if (!_scenes.contains(name) || captures.containsKey(name)) {
        throw StateError('Unexpected or duplicate component capture: $name');
      }
      final size = _dimensions(bytes);
      final file = File('$resolved/$name.png');
      await file.writeAsBytes(bytes, flush: true);
      pixels[name] = bytes;
      captures[name] = {
        'path': file.path,
        'width': size.$1,
        'height': size.$2,
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      };
      return true;
    },
    responseDataCallback: (data) async {
      final report = <String, dynamic>{...?data}..remove('screenshots');
      report['hostCaptures'] = captures;
      try {
        validateGlassComponentsReport(report);
        for (final raw in report['scenes'] as List) {
          final scene = raw as Map;
          final name = scene['name'] as String;
          final marker = readGlassSceneMarker(
            pixels[name]!,
            (scene['markerBounds'] as List).cast<num>(),
            scene['dpr'] as num,
          );
          captures[name]!['pixelMarkerCode'] = marker;
          if (marker != scene['markerCode']) {
            throw StateError('Stale PNG $name: pixel marker $marker.');
          }
          final stored = await File(captures[name]!['path'] as String)
              .readAsBytes();
          if (sha256.convert(stored).toString() != scene['sha256']) {
            throw StateError('Stored PNG SHA mismatch: $name');
          }
        }
        report['hostValidationComplete'] = true;
      } catch (error) {
        report['hostValidationComplete'] = false;
        report['hostValidationError'] = '$error';
        rethrow;
      } finally {
        await File('$resolved/result.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
      }
    },
  ).catchError((Object error, StackTrace stack) async {
    // A VM or emulator can disappear before responseDataCallback runs. Keep
    // that incomplete attempt visible without inventing device-side evidence.
    final result = File('$resolved/result.json');
    if (!await result.exists()) {
      await result.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 1,
          'scope': 'production-glass-components',
          'harnessComplete': false,
          'hostValidationComplete': false,
          'hostValidationError': '$error',
          'visualAcceptanceComplete': false,
          'performanceMeasured': false,
          'hostCaptures': captures,
        }),
        flush: true,
      );
    }
    Error.throwWithStackTrace(error, stack);
  });
}

/// Verifies finite runtime receipts, never perceptual quality or performance.
void validateGlassComponentsReport(Map<String, dynamic> report) {
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  require(
    report['schemaVersion'] == 1 &&
        report['scope'] == 'production-glass-components',
    'Wrong report identity.',
  );
  require(
    report['platform'] == 'android' && report['buildMode'] == 'profile',
    'Use Android profile mode.',
  );
  require(
    report['backend'] == 'liquid_glass_widgets' &&
        report['backendVersion'] == '1.13.0',
    'Wrong production renderer.',
  );
  require(
    report['shaderSupported'] == true &&
        report['shaderLoaded'] == true &&
        report['harnessComplete'] == true,
    'Incomplete runtime evidence.',
  );
  require(
    report['visualReviewRequired'] == true &&
        report['visualAcceptanceComplete'] == false &&
        report['performanceMeasured'] == false,
    'A finite capture cannot certify visual quality or performance.',
  );
  require(
    report['background'] == 'painted-lines-and-color-blocks',
    'Missing sampleable background.',
  );
  void renderer(dynamic raw, bool opaque, String name) {
    require(raw is Map, 'Missing renderer: $name');
    final value = raw as Map;
    require(
      value['liteCount'] == 0 && value['blurCount'] == 0,
      'Fallback blur or lightweight glass in $name.',
    );
    require(
      value['nativeCount'] is int && value['layerCount'] is int,
      'Invalid renderer counters: $name',
    );
    require(
      opaque
          ? value['nativeCount'] == 0 && value['layerCount'] == 0
          : (value['nativeCount'] as int) > 0 &&
                (value['layerCount'] as int) > 0,
      'Missing native glass or unexpected opaque optics: $name',
    );
  }

  renderer(report['nativeWarmup'], false, 'warmup');
  final scenes = report['scenes'];
  final captures = report['hostCaptures'];
  require(
    scenes is List &&
        scenes.length == _scenes.length &&
        captures is Map &&
        captures.length == _scenes.length,
    'Incomplete scene inventory.',
  );
  for (var i = 0; i < _scenes.length; i++) {
    final name = _scenes[i];
    final scene = (scenes as List)[i] as Map;
    final capture = (captures as Map)[name] as Map;
    final opaque = name.startsWith('opaque-');
    final dark = name.contains('-dark');
    require(
      scene['name'] == name && scene['markerCode'] == (0xc500 | (i + 1)),
      'Wrong scene identity: $name',
    );
    require(
      scene['brightness'] == (dark ? 'dark' : 'light') &&
          scene['reduceTransparency'] == opaque,
      'Wrong preferences: $name',
    );
    renderer(scene['renderer'], opaque, name);
    require(
      scene['sha256'] is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(scene['sha256'] as String) &&
          capture['sha256'] == scene['sha256'] &&
          capture['bytes'] == scene['bytes'],
      'Device/host image identity mismatch: $name',
    );
    require(
      capture['width'] == scene['physicalWidth'] &&
          capture['height'] == scene['physicalHeight'] &&
          (capture['width'] as int) > 0 &&
          (capture['height'] as int) > 0,
      'Wrong image dimensions: $name',
    );
    require(
      scene['dpr'] is num && (scene['dpr'] as num) > 0,
      'Invalid DPR: $name',
    );
    require(
      scene['markerBounds'] is List &&
          (scene['markerBounds'] as List).length == 4 &&
          (scene['markerBounds'] as List).every((v) => v is num && v.isFinite),
      'Invalid stamp geometry: $name',
    );
    if (name.startsWith('dialog-') || name.startsWith('tooltip-')) {
      require(
        (scene['renderer'] as Map)['cardCount'] == 1,
        'Official GlassCard not mounted: $name',
      );
    }
    if (name.startsWith('tab-') && !name.endsWith('-rest')) {
      require(
        (scene['indicators'] as List).any((raw) {
          final indicator = raw as Map;
          return indicator['paintGlass'] == true &&
              indicator['backgroundPass'] == false &&
              indicator['thickness'] is num &&
              (indicator['thickness'] as num) > 0;
        }),
        'No active official indicator lens: $name',
      );
    }
  }
  final drags = report['dragResults'];
  require(
    drags is List && drags.length == 2,
    'Missing light/dark drag results.',
  );
  for (final mode in ['light', 'dark']) {
    final matching = (drags as List).where(
      (raw) => (raw as Map)['brightness'] == mode,
    );
    require(matching.length == 1, 'Missing $mode drag.');
    final drag = matching.single as Map;
    require(
      drag['from'] == 0 &&
          drag['to'] == 2 &&
          drag['selectionCallbacks'] is List &&
          (drag['selectionCallbacks'] as List).isNotEmpty &&
          (drag['selectionCallbacks'] as List).last == 2,
      'First-to-last drag did not commit through onSelected: $mode',
    );
  }
  require(report['iconActivations'] == 0, 'Cancelled icon press activated.');
}

(int, int) _dimensions(List<int> bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 33 ||
      !List.generate(8, (i) => bytes[i] == signature[i]).every((v) => v) ||
      ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR') {
    throw StateError('Capture is not a complete PNG.');
  }
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return (data.getUint32(16), data.getUint32(20));
}
