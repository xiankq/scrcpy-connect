// Earliest counter packets from one actual player archive, without cross-clock subtraction.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../support.dart';
import 'analyze_first_counter.dart' show decodeFrames;

Json correlatePlayer(Json run, Json archive, List<dynamic> decoded) {
  if ([
    'measurementLoopComplete',
    'appCleanupConfirmed',
    'driverCloseConfirmed',
    'fixtureCleanupConfirmed',
    'targetTimelineComplete',
  ].any((k) => run[k] != true)) {
    throw StateError('measurement or cleanup is incomplete');
  }
  if (run['packetArchiveRequested'] != true || run['diagnosticOnly'] != true) {
    throw StateError('expected explicit archive diagnostic');
  }
  final rounds = run['rounds'] as List;
  if (rounds.length != 1 ||
      run['clockBounds']['complete'] != true ||
      run['clockBounds']['rounds'][0]['valid'] != true) {
    throw StateError('expected one valid clock-calibrated round');
  }
  final frames = archive['frames'] as List;
  if (archive['complete'] != true ||
      frames.isEmpty ||
      frames.length != decoded.length) {
    throw StateError('incomplete decoded archive');
  }
  final pts = frames.map((f) => f['sourcePtsUs']).toList();
  if (!sameList(pts, decoded.map((f) => f['sourcePtsUs']).toList()) ||
      pts.toSet().length != pts.length) {
    throw StateError('ambiguous or incomplete exact-PTS join');
  }
  final origins = frames
      .map((f) => (f['sourcePtsUs'] as num) - (f['ptsUs'] as num))
      .toSet();
  if (origins.length != 1 ||
      frames.any((f) => f['generation'] != archive['generation'])) {
    throw StateError('archive origin or generation changed');
  }
  final inputs = rounds.single['inputs'] as List;
  final counters = decoded.map((f) => f['counter'] as int).toList();
  final sequences = List.generate(inputs.length, (i) => i + 1);
  if (!sameList(inputs.map((s) => s['fixtureSequence']).toList(), sequences)) {
    throw StateError('input sequences reset or duplicated');
  }
  if (!sameList(inputs.map((s) => s['expectedCounter']).toList(), sequences) ||
      inputs.length > 15) {
    throw StateError('this narrow diagnostic does not accept counter wrap');
  }
  if (counters.first != 0 || counters.last != inputs.length) {
    throw StateError('counter skipped, reverted or missing terminal update');
  }
  for (var i = 0; i + 1 < counters.length; i++) {
    if (counters[i] > counters[i + 1] || counters[i + 1] > counters[i] + 1) {
      throw StateError('counter skipped, reverted or missing terminal update');
    }
  }
  final bounds = run['clockBounds']['rounds'][0];
  final timeline = run['targetTimeline'] as List;
  if (timeline.where((e) => e['kind'] == 'draw' && e['sequence'] == 0).length !=
      1) {
    throw StateError('fixture reset or missing initial draw');
  }
  final rows = <Json>[];
  for (final sample in inputs) {
    final seq = sample['fixtureSequence'] as int;
    final first = counters.indexOf(seq);
    final selected = pts.indexOf(sample['relayFrame']['sourcePtsUs']);
    if (selected < first || counters[selected] != seq) {
      throw StateError('snapshot frame does not belong to the new counter');
    }
    final matching = (sample['transportWindow'] as List)
        .where((f) => f['sourcePtsUs'] == pts[first])
        .toList();
    if (matching.length != 1) {
      throw StateError('earliest frame lacks one exact raw receipt');
    }
    final raw = matching.single;
    if (raw['captureSegment'] != sample['transportFrame']['captureSegment']) {
      throw StateError('raw generation changed during input');
    }
    final trace = sample['nativeFrameTrace'];
    final snap = trace['snapshot'];
    final snapshotUs =
        (trace['clockOriginUs'] as num) + (snap['elapsedUs'] as num);
    final selectedRaw = sample['transportFrame'];
    final observed = sample['inputObservedBeforeInvokeUs'] as num;
    final rawUs = raw['readCompletedUs'] as num;
    final selectedUs = selectedRaw['readCompletedUs'] as num;
    if (observed > rawUs || rawUs > selectedUs || selectedUs > snapshotUs) {
      throw StateError('controller event order is inconsistent');
    }
    final matches = (trace['decoded'] as List)
        .where(
          (d) =>
              ((d['ptsSeconds'] as num) * 1000000 -
                      (frames[first]['ptsUs'] as num))
                  .abs() <=
              1.1,
        )
        .toList();
    if (matches.length > 1) {
      throw StateError('ambiguous earliest onVideo callback');
    }
    final events = timeline.where((e) => e['sequence'] == seq).toList();
    final kinds = events.map((e) => e['kind'] as String).toList()..sort();
    if (events.length != 2 ||
        !sameList(kinds, ['draw', 'input']) ||
        events.any((e) => e['counter'] != seq)) {
      throw StateError('missing or ambiguous target events');
    }
    final draw = events.singleWhere((e) => e['kind'] == 'draw');
    final row = <String, dynamic>{
      'sequence': seq,
      'firstFrameIndex': first,
      'selectedFrameIndex': selected,
      'firstSourcePtsUs': pts[first],
      'selectedSourcePtsUs': pts[selected],
      'newCounterFramesBeforeSelected': selected - first,
      'inputToFirstRawMs': (rawUs - observed) / 1000,
      'firstRawToSelectedRawMs': (selectedUs - rawUs) / 1000,
      'firstRawToSnapshotMs': (snapshotUs - rawUs) / 1000,
      'drawEndToFirstRawLowerMs':
          (rawUs -
              (draw['nanoUs'] as num) +
              (bounds['offsetLowerUs'] as num) -
              (bounds['bootMinusMonoUpperUs'] as num) -
              1) /
          1000,
      'drawEndToFirstRawUpperMs':
          (rawUs -
              (draw['nanoUs'] as num) +
              (bounds['offsetUpperUs'] as num) -
              (bounds['bootMinusMonoLowerUs'] as num) +
              1) /
          1000,
      'earliestOnVideoObserved': matches.length == 1,
    };
    if (matches.isNotEmpty) {
      final onVideo =
          (trace['clockOriginUs'] as num) +
          (matches.single['elapsedUs'] as num);
      if (rawUs > onVideo || onVideo > snapshotUs) {
        throw StateError(
          'earliest onVideo precedes raw receipt or follows snapshot',
        );
      }
      row['firstRawToFirstOnVideoMs'] = (onVideo - rawUs) / 1000;
      row['firstOnVideoToSnapshotMs'] = (snapshotUs - onVideo) / 1000;
    }
    rows.add(row);
  }
  return {
    'complete': true,
    'diagnosticOnly': true,
    'frames': frames.length,
    'clockIntervalWidthMs': (bounds['intervalWidthUs'] as num) / 1000,
    'boundary': 'same player HTTP body and raw receipts; snapshot callback, not physical scan-out',
    'assumptions': run['clockBounds']['assumptions'],
    'samples': rows,
  };
}

Future<void> run(List<String> arguments) async {
  final args = parse(options(['run', 'ffmpeg']), arguments);
  final root = args['run'] as String;
  refuseEvidence(root, [
    'player-decode.log',
    'player-frames.json',
    'player-first-counter.json',
  ]);
  final result = readJson(p.join(root, 'result.json'));
  final archives = result['packetArchives'] as List? ?? [];
  if (archives.length != 1) {
    throw StateError('expected one exported player archive');
  }
  final child = archives.single['directory'] as String;
  if (p.basename(child) != child) {
    throw StateError('archive must be an immediate evidence child');
  }
  final directory = p.join(root, child);
  final archive = readJson(p.join(directory, 'archive.json'));
  final origin =
      (archive['frames'][0]['sourcePtsUs'] as int) -
      (archive['frames'][0]['ptsUs'] as int);
  final (frames, log) = await decodeFrames(
    p.join(directory, 'capture.mkv'),
    args['ffmpeg'] as String,
    origin,
  );
  final report = correlatePlayer(result, archive, frames);
  File(p.join(root, 'player-decode.log')).writeAsStringSync(log);
  writeJson(p.join(root, 'player-frames.json'), frames);
  writeJson(p.join(root, 'player-first-counter.json'), report);
  stdout.writeln(pretty.convert(report));
}

Future<void> main(List<String> arguments) => cli(() => run(arguments));
