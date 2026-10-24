// 关联被控回调，不等同于编码器 CPU 时间或显示时间。
import 'dart:io';

import '../support.dart';

Json correlate(
  Json receipt,
  List<dynamic> events,
  List<dynamic> clocks,
  List<dynamic> losses,
) {
  if (losses.isNotEmpty) {
    throw StateError('Trace reports data loss; correlation is incomplete');
  }
  final offsets = [
    for (final c in clocks)
      (integer(c['boot_ns']) - integer(c['mono_ns'])) / 1000,
  ];
  if (offsets.isEmpty || maximum(offsets) - minimum(offsets) > 1000) {
    throw StateError('Missing or inconsistent BOOTTIME/MONOTONIC snapshots');
  }
  final offset = median(offsets);
  final frames = <int, dynamic>{};
  for (final frame in receipt['frames'] as List) {
    final pts = integer(frame['pts']);
    if (frames.containsKey(pts)) {
      throw StateError(
        'Duplicate captured PTS requires segment disambiguation',
      );
    }
    frames[pts] = frame;
  }
  if (frames.isEmpty ||
      (receipt['offsetLow'] as num) > (receipt['offsetHigh'] as num)) {
    throw StateError('Missing frames or invalid host clock brackets');
  }
  final matches = <Json>[];
  var outside = 0;
  final seen = <int>{};
  for (final event in events) {
    final name = RegExp(r'^CCodecBufferChannel::onWorkDone\((.+)@ts=(\d+)\)$')
        .firstMatch(event['name'] as String);
    if (name == null || integer(event['dur']) < 0) {
      throw StateError('Malformed or incomplete CCodec event');
    }
    final pts = int.parse(name[2]!);
    if (!seen.add(pts)) {
      throw StateError('Duplicate CCodec PTS requires segment disambiguation');
    }
    if (!frames.containsKey(pts)) {
      if (minimum(frames.keys) <= pts && pts <= maximum(frames.keys)) {
        throw StateError(
          'CCodec event inside capture has no matching received frame',
        );
      }
      outside++;
      continue;
    }
    final frame = frames[pts];
    final doneUs = integer(event['ts']) / 1000;
    final sourceAge = doneUs - (pts + offset);
    if (sourceAge < -1000) {
      throw StateError(
        'PTS lies after callback; source clock assumption failed',
      );
    }
    matches.add({
      'ptsUs': pts,
      'codec': name[1],
      'workDoneBootUs': doneUs,
      'sourceToWorkDoneUs': sourceAge,
      'workDoneToHeaderLowerUs':
          (frame['headerReadUs'] as num) +
          (receipt['offsetLow'] as num) -
          doneUs,
      'workDoneToHeaderUpperUs':
          (frame['headerReadUs'] as num) +
          (receipt['offsetHigh'] as num) -
          doneUs,
    });
  }
  if (matches.isEmpty) {
    throw StateError('No target CCodec events matched received PTS');
  }
  matches.sort(
    (a, b) =>
        (a['workDoneBootUs'] as num).compareTo(b['workDoneBootUs'] as num),
  );
  Json summary(List<Json> rows) => {
    for (final key in [
      'sourceToWorkDoneUs',
      'workDoneToHeaderLowerUs',
      'workDoneToHeaderUpperUs',
    ])
      key: median(rows.map((row) => row[key] as num)),
  };
  final later = matches.sublist(matches.length * 2 ~/ 3);
  return {
    'matched': matches.length,
    'outsideCapture': outside,
    'bootMinusMonoSamplesUs': {
      'min': minimum(offsets),
      'max': maximum(offsets),
      'median': offset,
    },
    'assumptions': [
      'Source PTS shares target MONOTONIC origin and rate; exact PTS matches do not prove this.',
      'Uninterrupted target run; clock snapshots are successive reads, not formal offset bounds.',
      'Receipt host/target offset brackets retain their original continuity assumptions.',
    ],
    'boundary': 'CCodec onWorkDone callback processing, including earlier capture, queues and IPC; not pure encoder CPU or presentation',
    'allMedianUs': summary(matches),
    'lastThirdCount': later.length,
    'lastThirdMedianUs': summary(later),
    'matches': matches,
  };
}

Future<void> run(List<String> arguments, {Query? query}) async {
  final args = parse(
    options(['trace-processor', 'receipt', 'trace', 'output']),
    arguments,
  );
  final receipt = readJson(args['receipt'] as String);
  final run = receipt['run'] as String;
  if (!RegExp(r'^[0-9a-f]{12}$').hasMatch(run)) {
    throw StateError('Expected an isolated raw-drain run ID');
  }
  final ask =
      query ??
      traceQuery(args['trace-processor'] as String, args['trace'] as String);
  final events = await ask(
    '''SELECT s.ts,s.dur,s.name FROM slice s
        JOIN thread_track tt ON tt.id=s.track_id
        JOIN thread t ON t.utid=tt.utid JOIN process p ON p.upid=t.upid
        WHERE p.name='interop.rawdrain.$run'
        AND s.name GLOB 'CCodecBufferChannel::onWorkDone(*@ts=*)' ORDER BY s.ts''',
  );
  final clocks = await ask(
    '''SELECT b.clock_value boot_ns,m.clock_value mono_ns FROM clock_snapshot b
        JOIN clock_snapshot m ON m.snapshot_id=b.snapshot_id AND m.machine_id IS b.machine_id
        WHERE b.clock_name='BOOTTIME' AND m.clock_name='MONOTONIC' ''',
  );
  final losses = await ask(
    "SELECT name,value FROM stats WHERE severity='data_loss' AND value>0",
  );
  final report = correlate(receipt, events, clocks, losses);
  report['inputs'] = {'receipt': args['receipt'], 'trace': args['trace']};
  writeJson(args['output'] as String, report);
  stdout.writeln(pretty.convert(Map.of(report)..remove('matches')));
}

Future<void> main(List<String> arguments) => cli(() => run(arguments));
