// Offline acquired BufferQueue slot lifetimes; not the Codec2 work queue.
import 'dart:io';

import '../support.dart';

const operations = {
  'acquireBuffer',
  'releaseBuffer',
  'queueBuffer',
  'dequeueBuffer',
};
String sqlString(dynamic value) {
  if (value is! String || value.isEmpty || value.contains('\x00')) {
    throw ArgumentError('Expected a nonempty process name without NUL');
  }
  return "'${value.replaceAll("'", "''")}'";
}

int rowInteger(Json row, String key) {
  final value = row[key];
  if (value is bool || !RegExp(r'^-?\d+$').hasMatch('$value')) {
    throw FormatException('Malformed integer $key: $value');
  }
  return integer(value);
}

Json analyzeSlots(List<dynamic> events, [List<dynamic> losses = const []]) {
  if (losses.isNotEmpty) {
    throw StateError('Trace reports data loss; slot analysis is incomplete');
  }
  final normalized = <Json>[];
  final first = <int, Json>{};
  final ids = <int>{};
  final lastBySlot = <int, int>{};
  int? previousTs;
  for (final raw in events) {
    final row = raw as Json;
    final name = RegExp(r'^GraphicBufferSource: (0|[1-9]\d*)$')
        .firstMatch('${row['name']}');
    if (name == null || !operations.contains(row['operation'])) {
      throw StateError('Malformed slot name or operation');
    }
    final event = <String, dynamic>{
      for (final key in [
        'sliceId',
        'ts',
        'dur',
        'operationSliceId',
        'operationTs',
        'operationDur',
      ])
        key: rowInteger(row, key),
    };
    if (event.values.any((v) => (v as int) < 0)) {
      throw StateError('Negative integer or unclosed slot/operation slice');
    }
    final ts = event['ts'] as int;
    if ((event['operationTs'] as int) > ts ||
        ts + (event['dur'] as int) >
            (event['operationTs'] as int) + (event['operationDur'] as int)) {
      throw StateError('Slot slice lies outside its operation slice');
    }
    if (!ids.add(event['sliceId'] as int)) {
      throw StateError('Duplicate slot slice ID');
    }
    final slot = int.parse(name[1]!);
    if (previousTs != null && ts < previousTs) {
      throw StateError('Slot events are out of timestamp order');
    }
    if (lastBySlot.containsKey(slot) && ts <= lastBySlot[slot]!) {
      throw StateError('Same-slot timestamps are ambiguous or out of order');
    }
    previousTs = ts;
    lastBySlot[slot] = ts;
    event.addAll({
      'name': row['name'],
      'operation': row['operation'],
      'slot': slot,
    });
    normalized.add(event);
    first.putIfAbsent(slot, () => event);
  }
  if (normalized.length < 2 ||
      normalized.last['ts'] == normalized.first['ts']) {
    throw StateError('Expected a positive wall-clock slot event span');
  }
  final initial =
      first.keys
          .where((slot) => first[slot]!['operation'] == 'releaseBuffer')
          .toList()
        ..sort();
  final acquired = initial.toSet();
  final starts = <int, Json>{};
  final pairs = <Json>[];
  final occupancy = <(int, int)>[];
  final initialReleases = <Json>[];
  for (final event in normalized) {
    final slot = event['slot'] as int;
    final operation = event['operation'];
    if (operation == 'acquireBuffer') {
      if (!acquired.add(slot)) {
        throw StateError('Duplicate acquire for slot $slot');
      }
      starts[slot] = event;
    } else if (operation == 'releaseBuffer') {
      if (!acquired.remove(slot)) {
        throw StateError('Release without acquisition for slot $slot');
      }
      final start = starts.remove(slot);
      if (start != null) {
        final duration = (event['ts'] as int) - (start['ts'] as int);
        pairs.add({
          'slot': slot,
          'acquireSliceId': start['sliceId'],
          'releaseSliceId': event['sliceId'],
          'acquiredAtNs': start['ts'],
          'releasedAtNs': event['ts'],
          'holdNs': duration,
          'holdMs': duration / 1e6,
        });
      } else {
        initialReleases.add({
          'slot': slot,
          'releaseSliceId': event['sliceId'],
          'releasedAtNs': event['ts'],
        });
      }
    } else if (acquired.contains(slot)) {
      throw StateError('Producer operation while slot $slot is acquired');
    }
    occupancy.add((event['ts'] as int, acquired.length));
  }
  final start = normalized.first['ts'] as int;
  final end = normalized.last['ts'] as int;
  final cut = start + (end - start) * 2 ~/ 3;
  final weights = <int, int>{};
  for (var i = 0; i + 1 < occupancy.length; i++) {
    final (ts, count) = occupancy[i];
    final duration = occupancy[i + 1].$1 - (ts > cut ? ts : cut);
    if (duration > 0) weights[count] = (weights[count] ?? 0) + duration;
  }
  if (weights.values.fold(0, (a, b) => a + b) != end - cut) {
    throw StateError('Incomplete occupancy coverage');
  }
  final late = pairs
      .where((pair) => (pair['releasedAtNs'] as int) >= cut)
      .toList();
  Json holds(List<Json> rows) {
    final values = rows.map((pair) => pair['holdMs'] as num).toList();
    return {
      'count': values.length,
      'medianMs': values.isEmpty ? null : median(values),
      'minMs': values.isEmpty ? null : minimum(values),
      'maxMs': values.isEmpty ? null : maximum(values),
    };
  }

  final observed = first.keys.toList()..sort();
  final terminal = starts.keys.toList()..sort();
  final finalSlots = acquired.toList()..sort();
  final weighted = weights.keys.toList()..sort();
  return {
    'boundary': 'Observed BufferQueue slots from acquireBuffer to releaseBuffer; not exact Codec2 work queue size, encoding CPU or pixel presentation latency',
    'clockPolicy':
        'Only timestamps within this trace; no PTS or cross-clock subtraction',
    'assumptions': [
      'The trace has no reported data loss and captures relevant slot operations in this process.',
      'A slot whose first operation is release was acquired before the event window.',
      'Only observed slots are counted; unseen slots or unreported events cannot be reconstructed.',
    ],
    'window': {
      'startNs': start,
      'endExclusiveNs': end,
      'lastThirdStartNs': cut,
      'definition': 'First through last selected slot event start, not slice ends or sample count',
      'lastThirdDefinition': 'start + floor(2 * (end - start) / 3); occupancy weighted by interval duration',
      'holdSelection': 'Complete lifetimes released at or after the cut; durations are not clipped',
    },
    'observedSlots': observed,
    'initialAcquiredSlotsInferred': initial,
    'initialPartialReleases': initialReleases,
    'terminalAcquisitions': [
      for (final slot in terminal)
        {
          'slot': slot,
          'acquireSliceId': starts[slot]!['sliceId'],
          'acquiredAtNs': starts[slot]!['ts'],
        },
    ],
    'finalAcquiredSlots': finalSlots,
    'counts': {
      'events': normalized.length,
      'acquires': normalized
          .where((e) => e['operation'] == 'acquireBuffer')
          .length,
      'releases': normalized
          .where((e) => e['operation'] == 'releaseBuffer')
          .length,
      'completePairs': pairs.length,
    },
    'acquiredCountRange': [
      minimum(occupancy.map((v) => v.$2)),
      maximum(occupancy.map((v) => v.$2)),
    ],
    'allHolds': holds(pairs),
    'lastThirdReleasedHolds': holds(late),
    'lastThirdOccupancy': [
      for (final count in weighted)
        {
          'acquiredSlots': count,
          'durationNs': weights[count],
          'percent': 100 * weights[count]! / (end - cut),
        },
    ],
    'events': normalized,
    'pairs': pairs,
  };
}

Future<void> run(List<String> arguments, {Query? query}) async {
  final args = parse(
    options(['trace-processor', 'trace', 'process-name', 'output']),
    arguments,
  );
  final ask =
      query ??
      traceQuery(args['trace-processor'] as String, args['trace'] as String);
  final processes = await ask(
    'SELECT upid,pid,name FROM process WHERE name=${sqlString(args['process-name'])}',
  );
  if (processes.length != 1) {
    throw StateError('Expected one unique exact process name in trace');
  }
  final upid = rowInteger(processes.single, 'upid');
  if (upid < 0) throw StateError('Malformed process upid');
  final losses = await ask(
    "SELECT name,value FROM stats WHERE severity='data_loss' AND value>0",
  );
  final events = await ask('''SELECT s.id sliceId,s.ts,s.dur,s.name,
        par.id operationSliceId,par.ts operationTs,par.dur operationDur,par.name operation
        FROM slice s LEFT JOIN slice par ON par.id=s.parent_id
        JOIN thread_track tt ON tt.id=s.track_id
        JOIN thread t ON t.utid=tt.utid
        WHERE t.upid=$upid AND s.name GLOB 'GraphicBufferSource:*'
        ORDER BY s.ts,s.id''');
  final report = analyzeSlots(events, losses);
  report['inputs'] = {
    'trace': args['trace'],
    'processName': args['process-name'],
    'process': processes.single,
  };
  writeJson(args['output'] as String, report, exclusive: true);
  stdout.writeln(
    pretty.convert(
      Map.of(report)
        ..remove('events')
        ..remove('pairs'),
    ),
  );
}

Future<void> main(List<String> arguments) => cli(() => run(arguments));
