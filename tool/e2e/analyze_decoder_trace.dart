// PTS are identity keys. Durations always use one clock domain.
import 'dart:io';

import 'support.dart';

final codecPattern = RegExp(
  r'^CCodecBufferChannel::(queue|onWorkDone)\((.+)@ts=(-?\d+)\)$',
);
final markerPattern = RegExp(r'^connect\.onVideo\(t=(\d+)@ts=(-?\d+)\)$');
const decoderSql = '''
        SELECT s.id, s.ts, s.dur, s.name, p.pid
        FROM slice s
        JOIN thread_track tt ON s.track_id = tt.id
        JOIN thread t ON tt.utid = t.utid
        JOIN process p ON t.upid = p.upid
        WHERE s.name GLOB 'CCodecBufferChannel::queue(*'
           OR s.name GLOB 'CCodecBufferChannel::onWorkDone(*'
           OR s.name GLOB 'connect.onVideo(*'
        ORDER BY s.ts
''';

Json correlate(List<dynamic> slices, Json benchmark, int processId) {
  final groups = <(int, String, int), Map<String, List<Json>>>{};
  final markers = <Json>[];
  for (final row in slices) {
    final event = <String, dynamic>{
      for (final key in ['id', 'ts', 'dur', 'pid']) key: integer(row[key]),
    };
    if (event['pid'] != processId) continue;
    final match = codecPattern.firstMatch(row['name'] as String);
    if (match != null) {
      final key = (event['pid'] as int, match[2]!, int.parse(match[3]!));
      groups
          .putIfAbsent(key, () => {'queue': [], 'onWorkDone': []})[match[1]]!
          .add(event);
    } else {
      final marker = markerPattern.firstMatch(row['name'] as String);
      if (marker != null) {
        event.addAll({
          'token': int.parse(marker[1]!),
          'ptsUs': int.parse(marker[2]!),
        });
        markers.add(event);
      }
    }
  }
  final pairs = <Json>[];
  final rejected = <Json>[];
  for (final entry in groups.entries) {
    final (pid, codec, pts) = entry.key;
    final queued = entry.value['queue']!;
    final done = entry.value['onWorkDone']!;
    if (queued.length != 1 ||
        done.length != 1 ||
        (done.first['ts'] as int) < (queued.first['ts'] as int)) {
      rejected.add({
        'pid': pid,
        'codec': codec,
        'ptsUs': pts,
        'queueCount': queued.length,
        'doneCount': done.length,
      });
    } else {
      pairs.add({
        'pid': pid,
        'codec': codec,
        'ptsUs': pts,
        'queueNs': queued.first['ts'],
        'doneNs': done.first['ts'],
      });
    }
  }
  final rounds = benchmark['rounds'] as List? ?? [];
  final requested = [
    for (final round in rounds)
      for (final sample in round['inputs'] as List)
        sample['relayFrame']['ptsUs'] as num,
  ];
  final inputs = <Json>[];
  for (final round in rounds) {
    final samples = round['inputs'] as List;
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      final frame = sample['relayFrame'];
      final pts = frame['ptsUs'] as num;
      final native = sample['nativeFrameTrace'];
      final record = <String, dynamic>{
        'round': round['round'],
        'input': index,
        'ptsUs': pts,
      };
      inputs.add(record);
      final candidates = pairs
          .where((p) => ((p['ptsUs'] as num) - pts).abs() <= 1)
          .toList();
      if (candidates.length != 1) {
        record['unmatched'] = 'codec_pair_count=${candidates.length}';
        continue;
      }
      final pair = candidates.single;
      if (requested
              .where((p) => ((pair['ptsUs'] as num) - p).abs() <= 1)
              .length !=
          1) {
        record['unmatched'] = 'codec_pair_requested_by_multiple_inputs';
        continue;
      }
      final decoded = (native['decoded'] as List)
          .where(
            (d) =>
                (d['ptsSeconds'] as num).isFinite &&
                ((d['ptsSeconds'] as num) * 1000000 - pts).abs() <= 1.1,
          )
          .toList();
      if (decoded.length != 1) {
        record['unmatched'] = 'native_decoded_count=${decoded.length}';
        continue;
      }
      final token = native['traceToken'];
      final matching = markers
          .where(
            (m) =>
                token != null &&
                m['token'] == token &&
                m['pid'] == pair['pid'] &&
                ((m['ptsUs'] as num) - pts).abs() <= 1,
          )
          .toList();
      if (matching.length != 1) {
        record['markerUnmatched'] = 'marker_count=${matching.length}';
        if (token != null) continue;
      } else if ((matching.single['ts'] as num) < (pair['doneNs'] as num)) {
        record['markerUnmatched'] = 'marker_precedes_work_done';
        continue;
      } else {
        record.addAll({
          'traceToken': token,
          'markerPtsUs': matching.single['ptsUs'],
          'doneToOnVideoMs':
              ((matching.single['ts'] as num) - (pair['doneNs'] as num)) /
              1000000,
        });
      }
      record.addAll({
        'codec': pair['codec'],
        'tracePtsUs': pair['ptsUs'],
        'queueToDoneMs':
            ((pair['doneNs'] as num) - (pair['queueNs'] as num)) / 1000000,
        'relayToOnVideoMs':
            ((native['clockOriginUs'] as num) +
                (decoded.single['elapsedUs'] as num) -
                (frame['writeStartedUs'] as num)) /
            1000,
      });
    }
  }
  Json? summary(String field) {
    final values = inputs
        .where((r) => r.containsKey(field))
        .map((r) => r[field] as num)
        .toList();
    return values.isEmpty
        ? null
        : {
            'count': values.length,
            'min': minimum(values),
            'median': median(values),
            'max': maximum(values),
          };
  }

  return {
    'scope': 'instrumented ordinary Driver benchmark; no glass-to-glass claim',
    'clockPolicy': 'PTS keys only; each duration uses one clock domain; no cross-clock timestamp subtraction',
    'processId': processId,
    'codecPairs': pairs.length,
    'rejectedCodecGroups': rejected,
    'inputCount': inputs.length,
    'queueToDoneMs': summary('queueToDoneMs'),
    'relayToOnVideoMs': summary('relayToOnVideoMs'),
    'doneToOnVideoMs': summary('doneToOnVideoMs'),
    'inputs': inputs,
  };
}

Future<void> run(List<String> arguments, {Query? query}) async {
  final args = parse(
    options(
      ['trace-processor', 'trace', 'benchmark', 'pid', 'output'],
      flags: ['require-markers'],
    ),
    arguments,
  );
  final rows =
      await (query ??
          traceQuery(
            args['trace-processor'] as String,
            args['trace'] as String,
            seconds: 120,
          ))(decoderSql);
  final report = correlate(
    rows,
    readJson(args['benchmark'] as String),
    int.parse(args['pid'] as String),
  );
  writeJson(args['output'] as String, report, exclusive: true);
  stdout.writeln(
    pretty.convert(
      Map.of(report)
        ..remove('inputs')
        ..remove('rejectedCodecGroups'),
    ),
  );
  final inputs = report['inputs'] as List;
  if (inputs.isEmpty) {
    throw StateError('No benchmark input observations; see output.');
  }
  if (args['require-markers'] == true &&
      inputs.any((r) => !(r as Map).containsKey('doneToOnVideoMs'))) {
    throw StateError(
      'Incomplete or ambiguous system marker coverage; see output.',
    );
  }
}

Future<void> main(List<String> arguments) => cli(() => run(arguments));
