import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

double pct(List<double> values, double q) {
  final sorted = List<double>.of(values)..sort();
  return sorted[((sorted.length - 1) * q).round()];
}

double median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    throw ArgumentError('Expected result directory and optional warmup count.');
  }
  final root = args[0];
  final skip = args.length > 1 ? int.parse(args[1]) : 2;
  final report = jsonDecode(
    File('$root/result.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final all = _objects(report['runs']);
  final runs = all.skip(skip).map((r) => _object(r['response'])).toList();
  if (skip < 0 ||
      runs.isEmpty ||
      report['complete'] != true ||
      runs.any((r) => r['complete'] != true)) {
    throw StateError('Incomplete run');
  }
  Set<int> pts(Map<String, dynamic> r) =>
      _objects(_object(r['native'])['sends'])
          .where(
            (s) =>
                s['index'] != 0 &&
                (s['ptsUs'] as int) >= 3000000 &&
                (s['ptsUs'] as int) < 14000000,
          )
          .map((s) => s['ptsUs'] as int)
          .where(
            (p) =>
                _objects(r['decoded'])
                    .where(
                      (f) => ((f['ptsSeconds'] as num) * 1e6 - p).abs() < 2,
                    )
                    .length ==
                1,
          )
          .toSet();
  final common = runs.map(pts).reduce((a, b) => a.intersection(b));
  if (common.isEmpty) throw StateError('No common decoded PTS');
  final variedConfiguration =
      runs.map((r) => r['configuration']).toSet().length > 1;
  final results = <Map<String, dynamic>>[];
  for (final r in runs) {
    final n = _object(r['native']);
    final sends = _objects(n['sends']);
    final input = <double>[];
    final scheduled = <double>[];
    final calls = <double>[];
    final afterNext = <double>[];
    for (var i = 1; i < sends.length; i++) {
      final s = sends[i];
      if (!common.contains(s['ptsUs'])) continue;
      final ptsUs = s['ptsUs'] as int;
      final entered = s['enteredUs'] as int;
      final f = _objects(
        r['decoded'],
      ).singleWhere((f) => ((f['ptsSeconds'] as num) * 1e6 - ptsUs).abs() < 2);
      final callback = (r['clockOriginUs'] as int) + (f['elapsedUs'] as int);
      input.add((callback - entered) / 1000.0);
      scheduled.add((callback - (n['startedUs'] as int) - ptsUs) / 1000.0);
      calls.add(((s['completedUs'] as int) - entered) / 1000.0);
      if (i + 1 < sends.length) {
        afterNext.add((callback - (sends[i + 1]['enteredUs'] as int)) / 1000.0);
      }
    }
    results.add({
      'mode': r['mode'],
      'round': r['round'],
      'configuration': r['configuration'],
      'group': variedConfiguration
          ? '${r['mode']}/${r['configuration']}'
          : r['mode'],
      'commonFrames': common.length,
      'decodedFrames': _objects(r['decoded']).length,
      'prepareMs': r['prepareMs'],
      'textureMs': r['textureMs'],
      'inputP50Ms': pct(input, .5),
      'inputP95Ms': pct(input, .95),
      'scheduledP50Ms': pct(scheduled, .5),
      'scheduledP95Ms': pct(scheduled, .95),
      'writeOrAppendP50Ms': pct(calls, .5),
      'writeOrAppendP95Ms': pct(calls, .95),
      'afterFollowingInputP50Ms': pct(afterNext, .5),
      'afterFollowingInputP95Ms': pct(afterNext, .95),
      'cpuOneCorePercent':
          (r['cpuTicks'] as int) / 100 / ((r['wallUs'] as int) / 1e6) * 100,
      'rssBeforeMiB': (r['rssBeforeBytes'] as int) / 1048576,
      'rssPeakMiB': (r['rssPeakBytes'] as int) / 1048576,
      'maxBufferedMs': r['maxBufferedMs'],
      'rejected': n['rejected'],
      'traceDrops': r['traceDrops'],
      'decoder': _objects(r['events'])
          .where((e) => e['category'] == 'decoder.video')
          .toList(),
      'pixelsCounter': _object(r['pixels'])['counter'],
      'previousCleanup': r['previousCleanup'],
    });
  }
  final groups = <String, dynamic>{};
  for (final name in results.map((r) => r['group'] as String).toSet()) {
    final group = results.where((r) => r['group'] == name).toList();
    groups[name] = {
      for (final key in [
        'inputP50Ms',
        'inputP95Ms',
        'scheduledP50Ms',
        'scheduledP95Ms',
        'cpuOneCorePercent',
        'writeOrAppendP95Ms',
      ])
        key: {
          'median': median(
            group.map((r) => (r[key] as num).toDouble()).toList(),
          ),
          'min': group.map((r) => (r[key] as num).toDouble()).reduce(math.min),
          'max': group.map((r) => (r[key] as num).toDouble()).reduce(math.max),
        },
    };
  }
  final output = {
    'complete': true,
    'sourceReport': '$root/result.json',
    'skippedWarmupRounds': skip,
    'measurementPtsUs': [3000000, 14000000],
    'commonFramesPerRun': common.length,
    'runs': results,
    'groups': groups,
    'cleanup': report['cleanup'],
  };
  File('$root/comparison.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
}

Map<String, dynamic> _object(Object? value) => value as Map<String, dynamic>;
List<Map<String, dynamic>> _objects(Object? value) =>
    (value as List<dynamic>).cast<Map<String, dynamic>>();
