import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import 'glass_metrics.dart';

/// Fast real-device performance loop; deliberately does not certify captures or
/// production interaction behavior. Those remain the full Glass driver scope.
Future<void> main() async {
  final directory = Directory(
    Platform.environment['CONNECT_GLASS_CAPTURE_DIR'] ??
        '/tmp/connect-glass-widgets-perf',
  );
  if (!directory.isAbsolute ||
      !directory.path.startsWith('/tmp/') ||
      directory.path.split('/').contains('..')) {
    throw StateError('CONNECT_GLASS_CAPTURE_DIR must be below /tmp/.');
  }
  var ancestor = directory;
  while (!await ancestor.exists()) {
    ancestor = ancestor.parent;
  }
  final ancestorPath = await ancestor.resolveSymbolicLinks();
  if (ancestorPath != '/tmp' && !ancestorPath.startsWith('/tmp/')) {
    throw StateError('Output ancestor must resolve below /tmp/.');
  }
  await directory.create(recursive: true);
  final resolved = await directory.resolveSymbolicLinks();
  if (!resolved.startsWith('/tmp/')) {
    throw StateError('Output must resolve below /tmp/.');
  }
  await integrationDriver(
    driver: await FlutterDriver.connect(),
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async =>
        throw StateError('Performance-only run must not capture screenshots.'),
    responseDataCallback: (data) async {
      final report = <String, dynamic>{...?data}..remove('screenshots');
      try {
        validateGlassProfileReport(report);
        report.addAll(summarizeGlassPerformance(report));
        report['hostValidationComplete'] = true;
        if (report['performanceAcceptanceComplete'] != true) {
          throw StateError(
            'Real profile FrameTimings exceed the display budget.',
          );
        }
      } catch (error) {
        report['profileError'] = error.toString();
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

void validateGlassProfileReport(Map<String, dynamic> report) {
  void require(bool valid, String message) {
    if (!valid) throw StateError(message);
  }

  require(report['schemaVersion'] == 2, 'Wrong schema.');
  require(
    report['composition'] == 'same-variant-single-sdf-layer',
    'Wrong production composition.',
  );
  require(report['scope'] == 'glass-performance', 'Wrong profile scope.');
  require(report['buildMode'] == 'profile', 'Profile build is required.');
  require(report['platform'] == 'android', 'Android GPU runtime is required.');
  require(
    report['backend'] == 'liquid_glass_widgets' &&
        report['backendVersion'] == '1.13.0',
    'Wrong material backend.',
  );
  for (final key in [
    'shaderImageFiltersSupported',
    'shaderProgramsLoaded',
    'harnessComplete',
    'performanceCaptureComplete',
  ]) {
    require(report[key] == true, 'Missing runtime evidence: $key.');
  }
  require(report['fallbackEnabled'] == false, 'Fallback is forbidden.');
  require(
    report['nativeSurfaceDuringTiming'] == true,
    'ImageView timing cannot certify the production surface.',
  );
  require(report['visualAcceptanceComplete'] == false, 'No visual verdict.');
  final windows = report['performance'];
  require(windows is List && windows.length == 4, 'Four scenarios required.');
  const names = ['regular', 'clear', 'blend', 'reduced'];
  for (var i = 0; i < names.length; i++) {
    final window = (windows as List)[i] as Map<String, dynamic>;
    final reduced = names[i] == 'reduced';
    require(window['scenario'] == names[i], 'Scenario order differs.');
    require(window['renderSurface'] == 'native', 'Native surface is required.');
    require(
      window['quality'] == (reduced ? 'opaque' : 'premium'),
      'Premium real refraction is required.',
    );
    if (!reduced) {
      final settings = window['opticalSettings'];
      require(
        settings is Map &&
            settings['bodyMode'] ==
                (names[i] == 'clear' ? 'clear' : 'adaptive') &&
            settings['blurSigmaLogicalPx'] is num &&
            (settings['blurSigmaLogicalPx'] as num) > 0,
        'Missing actual optical settings.',
      );
    }
    require(window['liteCount'] == 0, 'Lite substitution is forbidden.');
    require(
      (window['lensCount'] as num) ==
          (reduced
              ? 0
              : names[i] == 'clear'
              ? 2
              : names[i] == 'blend'
              ? 5
              : 4),
      'Production lens count differs.',
    );
    require(
      reduced ? window['layerCount'] == 0 : window['layerCount'] == 1,
      'Native renderer layer required.',
    );
    require(
      window['screenshotsDuringMeasurement'] == 0,
      'Screenshot work contaminates timings.',
    );
    require(
      (window['backgroundPaints'] as num) > 2,
      'Background must update continuously.',
    );
    require(
      window['frames'] is List && (window['frames'] as List).isNotEmpty,
      'Missing actual FrameTimings.',
    );
    require(
      (window['windowEndWallUs'] as num) -
              (window['windowStartWallUs'] as num) >=
          3000000,
      'Measurement window is too short.',
    );
  }
}
