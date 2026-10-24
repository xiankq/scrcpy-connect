import 'dart:math' as math;

/// 汇总真实 FrameTimings；截图和 widget 测试 pump 时长不作为性能输入，Debug 运行不证明达到性能预算。
///
Map<String, Object?> summarizeGlassPerformance(Map<String, dynamic> report) {
  final windows = (report['performance'] as List).cast<Map<String, dynamic>>();
  final summaries = <Map<String, Object?>>[];
  for (final window in windows) {
    final frames = (window['frames'] as List).cast<Map<String, dynamic>>();
    if (frames.isEmpty) throw StateError('No real FrameTiming samples.');
    final hz = (window['refreshRateHz'] as num).toDouble();
    if (!hz.isFinite || hz <= 0) {
      throw StateError('Invalid display refresh rate.');
    }
    final budgetUs = 1000000 / hz;
    Map<String, Object> distribution(String key) {
      final values =
          frames.map((frame) => (frame[key] as num).toDouble()).toList()
            ..sort();
      if (values.any((v) => !v.isFinite || v < 0)) {
        throw StateError('Invalid FrameTiming duration.');
      }
      double percentile(double fraction) =>
          values[math.max(0, (values.length * fraction).ceil() - 1)] / 1000;
      return {
        'p50Ms': percentile(.5),
        'p95Ms': percentile(.95),
        'p99Ms': percentile(.99),
        'maxMs': values.last / 1000,
        'overBudgetFrames': values.where((v) => v > budgetUs).length,
      };
    }

    final build = distribution('buildUs');
    final raster = distribution('rasterUs');
    final total = distribution('totalUs');
    final vsyncs = frames.map((f) => f['vsyncStartUs'] as int).toList()..sort();
    final intervals = [
      for (var i = 1; i < vsyncs.length; i++) vsyncs[i] - vsyncs[i - 1],
    ]..sort();
    summaries.add({
      'scenario': window['scenario'],
      'frames': frames.length,
      'refreshRateHz': hz,
      'frameBudgetMs': budgetUs / 1000,
      'build': build,
      'raster': raster,
      'totalSpan': total,
      'medianVsyncIntervalMs': intervals.isEmpty
          ? null
          : intervals[intervals.length ~/ 2] / 1000,
      'vsyncIntervalsOverBudget': intervals
          .where((v) => v > budgetUs * 1.5)
          .length,
      'withinBudget':
          (build['p95Ms'] as double) <= budgetUs / 1000 &&
          (raster['p95Ms'] as double) <= budgetUs / 1000,
    });
  }
  final withinBudget = summaries.every(
    (summary) => summary['withinBudget'] == true,
  );
  return {
    'performanceSummary': summaries,
    'performanceWithinBudget': withinBudget,
    'performanceAcceptanceComplete':
        report['buildMode'] == 'profile' &&
        report['nativeSurfaceDuringTiming'] == true &&
        withinBudget,
    'performanceScope':
        'Continuous diagnostic Flutter background, production material controls; '
        '${report['nativeSurfaceDuringTiming'] == true ? 'native Android surface' : 'surface not certified as native'}. '
        'No screen capture inside timed intervals. Does not measure multi-video workloads or Apple native equivalence.',
  };
}
