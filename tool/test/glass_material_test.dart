import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../benchmark/glass_metrics.dart';
import '../driver/glass_material.dart';

Map<String, dynamic> fixture() {
  const names = [
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
  ];
  final report = <String, dynamic>{
    'schemaVersion': 2,
    'scope': 'glass-material',
    'backend': 'liquid_glass_widgets',
    'backendVersion': '1.13.0',
    'platform': 'android',
    'buildMode': 'profile',
    'fallbackEnabled': false,
    'debugPointerOverlay': false,
    'tooltipsVisible': false,
    'visualAcceptanceComplete': false,
    for (final key in [
      'shaderImageFiltersSupported',
      'shaderProgramsLoaded',
      'surfaceConverted',
      'functionalAcceptanceComplete',
      'opticalCaptureComplete',
      'harnessComplete',
      'visualReviewRequired',
      'dynamicCaptureComplete',
      'performanceCaptureComplete',
    ])
      key: true,
    'scenes': <Map<String, dynamic>>[],
    'hostCaptures': <String, dynamic>{},
    'interactions': {
      for (final key in [
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
      ])
        key: true,
      'backgroundScrollDistance': 180,
    },
    'motionSamples': [
      for (var i = 0; i < 60; i++)
        {
          'phase': [
            'press',
            'drag',
            'cancel',
            'repress',
            'recovery',
            'reduced-motion-press',
          ][i % 6],
          'elapsedUs': i * 16667,
          'bounds': [30, 30, 22, 22],
        },
    ],
    'performance': [
      for (final scenario in ['regular', 'clear', 'blend', 'reduced'])
        {
          'scenario': scenario,
          'refreshRateHz': 60,
          'backgroundPaints': 120,
          'screenshotsDuringMeasurement': 0,
          'frames': [
            for (var i = 0; i < 120; i++)
              {
                'number': i,
                'vsyncStartUs': i * 16667,
                'buildUs': 1000,
                'rasterUs': 5000,
                'totalUs': 6500,
              },
          ],
        },
    ],
  };
  for (var i = 0; i < names.length; i++) {
    final name = names[i];
    final clear = name.startsWith('clear-');
    final reduced = [
      'reduced-light',
      'reduced-light-scrolled',
      'reduced-dark',
    ].contains(name);
    final blend = name.startsWith('blend-');
    (report['scenes'] as List).add({
      'name': name,
      'markerCode': 0xa500 | (i + 1),
      'markerBounds': [0, 0, 96, 6],
      'reduceTransparency': reduced,
      'reduceMotion': name == 'reduced-motion-pressed',
      'variant': clear ? 'clear' : 'regular',
      'brightness': name.endsWith('dark') ? 'dark' : 'light',
      'background': clear ? 'geometric-media' : 'lines-text-checks',
      'optics': reduced ? 'skipped-reduced-transparency' : 'shader',
      'lightweightSurfaceCount': 0,
      'blurWidgetCount': 0,
      'surfaceCount': reduced
          ? 0
          : clear
          ? 2
          : blend
          ? 5
          : 4,
      'layerCount': reduced ? 0 : 4,
      'blendGroupCount': reduced
          ? 0
          : blend
          ? 2
          : 1,
      'backgroundOffset': name.endsWith('scrolled') ? 180 : 0,
      'physicalWidth': 400,
      'physicalHeight': 800,
      'devicePixelRatio': 1,
      'controls': {
        'close': [20, 20, 44, 44],
        'toolbar': [250, 20, 88, 44],
        if (!clear) 'panel': [60, 200, 280, 120],
        if (!clear) 'tabs': [20, 700, 360, 66],
      },
    });
    (report['hostCaptures'] as Map)[name] = {'width': 400, 'height': 800};
  }
  return jsonDecode(jsonEncode(report)) as Map<String, dynamic>;
}

void main() {
  test(
    'capture contract rejects the old backend, missing dynamics and fallback',
    () {
      validateGlassMaterialReport(fixture());
      for (final key in [
        'backend',
        'dynamicCaptureComplete',
        'performanceCaptureComplete',
        'debugPointerOverlay',
      ]) {
        final report = fixture();
        report[key] = key == 'backend'
            ? 'liquid_glass_easy'
            : key == 'debugPointerOverlay';
        expect(
          () => validateGlassMaterialReport(report),
          throwsStateError,
          reason: key,
        );
      }
      final fallback = fixture();
      ((fallback['scenes'] as List).first as Map)['lightweightSurfaceCount'] =
          1;
      expect(() => validateGlassMaterialReport(fallback), throwsStateError);
      final contaminated = fixture();
      ((contaminated['performance'] as List).first
              as Map)['screenshotsDuringMeasurement'] =
          1;
      expect(() => validateGlassMaterialReport(contaminated), throwsStateError);
    },
  );

  test('performance reports budget misses and never certifies a debug run', () {
    final report = fixture();
    expect(
      summarizeGlassPerformance(report)['performanceAcceptanceComplete'],
      isTrue,
    );
    report['buildMode'] = 'debug';
    expect(
      summarizeGlassPerformance(report)['performanceAcceptanceComplete'],
      isFalse,
    );
    report['buildMode'] = 'profile';
    final frames =
        ((report['performance'] as List).first as Map)['frames'] as List;
    for (final raw in frames) {
      (raw as Map)['rasterUs'] = 25000;
    }
    final summary = summarizeGlassPerformance(report);
    expect(summary['performanceWithinBudget'], isFalse);
    final first = (summary['performanceSummary'] as List).first as Map;
    expect((first['raster'] as Map)['p95Ms'], 25);
    expect((first['raster'] as Map)['overBudgetFrames'], 120);
  });
}
