import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import 'support/glass_scene_marker.dart';

const _scenes = [
  'light-rest',
  'light-scroll',
  'motion-held',
  'motion-drag',
  'motion-cancel',
  'motion-repress',
  'motion-recovered',
  'dialog-light',
  'sheet-light',
  'menu-light',
  'tooltip-light',
  'feedback-light',
  'dark-scroll',
  'dialog-dark',
  'sheet-dark',
  'menu-dark',
  'tooltip-dark',
  'feedback-dark',
  'opaque-light',
  'dialog-opaque',
  'sheet-opaque',
  'menu-opaque',
  'tooltip-opaque',
  'feedback-opaque',
  'opaque-dark',
  'reduced-motion-rest',
  'reduced-motion-held',
  'dialog-reduced-motion',
  'sheet-reduced-motion',
  'menu-reduced-motion',
  'tooltip-reduced-motion',
  'feedback-reduced-motion',
];

Future<void> main() async {
  final output = Directory(
    Platform.environment['CONNECT_GLASS_CHROME_DIR'] ??
        '/tmp/connect-glass-chrome',
  );
  if (!output.isAbsolute ||
      !output.path.startsWith('/tmp/') ||
      output.path.split('/').contains('..')) {
    throw StateError('CONNECT_GLASS_CHROME_DIR must be below /tmp/.');
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
  final photo = File(
    Platform.environment['CONNECT_GLASS_CHROME_SOURCE_PHOTO'] ??
        '../designs/assets/sample-lake.jpg',
  );
  final expectedPhoto = sha256.convert(await photo.readAsBytes()).toString();
  final captures = <String, Map<String, dynamic>>{};
  final pixels = <String, List<int>>{};
  // 只移除本夹具命名的输出，避免中断后重跑将旧画面误当成当前结果。
  //
  for (final name in [..._scenes.map((s) => '$s.png'), 'result.json']) {
    final file = File('$resolved/$name');
    if (await file.exists()) await file.delete();
  }
  await integrationDriver(
    driver: await FlutterDriver.connect(),
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      if (!_scenes.contains(name) || captures.containsKey(name)) {
        throw StateError('Unexpected or duplicate chrome capture: $name');
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
      report['sourcePhotoSha256'] = expectedPhoto;
      try {
        validateGlassChromeReport(report);
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
            throw StateError('Stale scene PNG $name: pixel marker $marker.');
          }
          // 写入后独立核验字节，不依赖设备回执。
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
  );
}

/// 检查有限的运行证据，不作感知视觉判定。
void validateGlassChromeReport(Map<String, dynamic> report) {
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  require(
    report['schemaVersion'] == 1 &&
        report['scope'] == 'production-glass-chrome',
    'Wrong report identity.',
  );
  require(
    report['platform'] == 'android' && report['buildMode'] == 'profile',
    'Use Android profile mode.',
  );
  require(
    report['backend'] == 'liquid_glass_widgets' &&
        report['backendVersion'] == '1.15.0',
    'Wrong production renderer.',
  );
  require(
    report['shaderSupported'] == true &&
        report['shaderLoaded'] == true &&
        report['harnessComplete'] == true,
    'Incomplete shader/runtime evidence.',
  );
  require(
    report['visualReviewRequired'] == true &&
        report['visualAcceptanceComplete'] == false &&
        report['performanceMeasured'] == false,
    'Finite capture cannot certify visual quality or performance.',
  );
  require(
    report['captureSurface'] == 'android-image-reader-after-native-warmup',
    'Missing capture surface boundary.',
  );
  void renderer(dynamic value, bool opaque, String name) {
    require(value is Map, 'Missing renderer counters: $name');
    final r = value as Map;
    require(
      r['liteCount'] == 0 && r['blurCount'] == 0,
      'Lite or blur fallback in $name.',
    );
    require(
      r['lensCount'] is int && r['layerCount'] is int,
      'Invalid renderer counters: $name',
    );
    require(
      opaque
          ? r['lensCount'] == 0 && r['layerCount'] == 0
          : (r['lensCount'] as int) > 0 && (r['layerCount'] as int) > 0,
      'Missing native glass / unexpected opaque optics in $name.',
    );
  }

  renderer(report['nativeWarmup'], false, 'native-warmup');
  final photo = report['photo'];
  require(
    photo is Map &&
        photo['sha256'] == report['sourcePhotoSha256'] &&
        photo['bytes'] is int &&
        (photo['bytes'] as int) > 0 &&
        photo['width'] is int &&
        (photo['width'] as int) > 0 &&
        photo['height'] is int &&
        (photo['height'] as int) > 0,
    'Device photograph does not match the repository photograph.',
  );
  final scenes = report['scenes'];
  final captures = report['hostCaptures'];
  require(
    scenes is List &&
        scenes.length == _scenes.length &&
        captures is Map &&
        captures.length == _scenes.length,
    'Incomplete chrome scene inventory.',
  );
  List<double> vector(dynamic value, int length) {
    require(
      value is List &&
          value.length == length &&
          value.every((n) => n is num && n.isFinite),
      'Invalid geometry/matrix evidence.',
    );
    return (value as List).cast<num>().map((n) => n.toDouble()).toList();
  }

  double delta(List<double> a, List<double> b) => List.generate(
    a.length,
    (i) => (a[i] - b[i]).abs(),
  ).reduce((a, b) => a > b ? a : b);
  final receipts = <String, Map<dynamic, dynamic>>{};
  int? width;
  int? height;
  for (var i = 0; i < _scenes.length; i++) {
    final name = _scenes[i];
    final scene = (scenes as List)[i] as Map;
    final capture = (captures as Map)[name] as Map;
    receipts[name] = scene;
    final opaque = name.startsWith('opaque-') || name.endsWith('-opaque');
    final reducedMotion = name.contains('reduced-motion');
    final dark =
        name == 'opaque-dark' ||
        name == 'dark-scroll' ||
        name.endsWith('-dark');
    require(
      scene['name'] == name && scene['markerCode'] == (0xc300 | (i + 1)),
      'Wrong scene sequence/identity: $name',
    );
    require(
      scene['reduceTransparency'] == opaque &&
          scene['reduceMotion'] == reducedMotion &&
          scene['brightness'] == (dark ? 'dark' : 'light'),
      'Wrong scene preferences: $name',
    );
    renderer(scene['renderer'], opaque, name);
    require(
      scene['sha256'] is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(scene['sha256'] as String) &&
          capture['sha256'] == scene['sha256'] &&
          capture['bytes'] == scene['bytes'],
      'Device/host PNG identity mismatch: $name',
    );
    require(
      capture['width'] == scene['physicalWidth'] &&
          capture['height'] == scene['physicalHeight'],
      'Wrong PNG dimensions: $name',
    );
    width ??= capture['width'] as int;
    height ??= capture['height'] as int;
    require(
      width > 0 &&
          height > 0 &&
          capture['width'] == width &&
          capture['height'] == height,
      'Viewport changed during capture.',
    );
    require(
      scene['dpr'] is num && (scene['dpr'] as num) > 0,
      'Invalid DPR: $name',
    );
    vector(scene['markerBounds'], 4);
    vector(scene['headerBounds'], 4);
    vector(scene['photoBounds'], 4);
    vector((scene['presentation'] as Map)['matrix'], 16);
  }
  final geometry = report['scrollGeometry'] as Map;
  final header = vector(geometry['header'], 4);
  final before = vector(geometry['before'], 4);
  final after = vector(geometry['after'], 4);
  require(
    geometry['offset'] is num &&
        (geometry['offset'] as num) > 40 &&
        after[1] < header[1] + header[3] &&
        after[1] + after[3] > header[1] &&
        before[1] - after[1] > 40,
    'No real photograph underlap beneath the header.',
  );
  final samples = report['motionSamples'];
  require(
    samples is List && samples.length >= 37,
    'Missing continuous motion samples.',
  );
  final phases = (samples as List).map((s) => (s as Map)['phase']).toSet();
  require(
    phases.containsAll({
      'rest',
      'press',
      'drag',
      'cancel',
      'repress',
      'recovery',
      'reduced-rest',
      'reduced-press',
      'reduced-cancel',
    }),
    'Incomplete press/cancel/repress evidence.',
  );
  final rest = vector((samples.first as Map)['matrix'], 16);
  final reducedRest = vector(
    (samples.firstWhere((s) => (s as Map)['phase'] == 'reduced-rest')
        as Map)['matrix'],
    16,
  );
  var changed = false;
  num previousTime = 0;
  for (final raw in samples) {
    final sample = raw as Map;
    final matrix = vector(sample['matrix'], 16);
    vector(sample['bounds'], 4);
    require(
      sample['wallUs'] is num && (sample['wallUs'] as num) >= previousTime,
      'Nonmonotonic presentation samples.',
    );
    previousTime = sample['wallUs'] as num;
    if (sample['phase'] == 'press' && delta(rest, matrix) > .001) {
      changed = true;
    }
    if ((sample['phase'] as String).startsWith('reduced-')) {
      require(
        delta(reducedRest, matrix) < .001,
        'Reduced motion displaced the control.',
      );
    }
    if ([
      'press',
      'drag',
      'cancel',
      'repress',
      'recovery',
    ].contains(sample['phase'])) {
      require(
        sample['activationCount'] == 0,
        'Cancelled press activated an action.',
      );
    }
  }
  require(changed, 'No measured press deformation.');
  final overlays = report['overlaySamples'];
  require(
    overlays is List && overlays.length == 60,
    'Missing continuous dialog/sheet/menu transition samples.',
  );
  for (final kind in ['dialog', 'sheet', 'menu']) {
    for (final mode in ['light', 'dark', 'opaque', 'reduced-motion']) {
      final frames = (overlays as List)
          .where((v) => (v as Map)['phase'] == '$kind-$mode')
          .toList();
      require(frames.length == 5, 'Incomplete $kind-$mode transition.');
      final initial = vector((frames.first as Map)['matrix'], 16);
      for (final value in frames) {
        final matrix = vector((value as Map)['matrix'], 16);
        if (mode == 'reduced-motion') {
          require(
            delta(initial, matrix) < .001,
            'Reduced motion displaced the $kind overlay.',
          );
        }
      }
    }
  }
  final recovered = vector(
    (receipts['motion-recovered']!['presentation'] as Map)['bounds'],
    4,
  );
  final initial = vector((samples.first as Map)['bounds'], 4);
  require(
    delta(initial, recovered) < .5,
    'Control did not recover after cancellation.',
  );
  require(
    report['activationCount'] == 1 && report['menuActivationCount'] == 4,
    'Reactivation/menu action counts do not match actual interactions.',
  );
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
