import 'package:flutter_test/flutter_test.dart';

import '../benchmark/glass_metrics.dart';

Map<String, dynamic> fixture() => {
  'buildMode': 'profile',
  'nativeSurfaceDuringTiming': true,
  'performance': [
    {
      'scenario': 'regular',
      'refreshRateHz': 60,
      'frames': [
        for (var i = 0; i < 120; i++)
          {
            'vsyncStartUs': i * 16667,
            'buildUs': 1000,
            'rasterUs': 5000,
            'totalUs': 6500,
          },
      ],
    },
  ],
};

void main() {
  test('ImageView timings never certify the native surface budget', () {
    final report = fixture()..['nativeSurfaceDuringTiming'] = false;
    final summary = summarizeGlassPerformance(report);
    expect(summary['performanceWithinBudget'], isTrue);
    expect(summary['performanceAcceptanceComplete'], isFalse);
  });

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
