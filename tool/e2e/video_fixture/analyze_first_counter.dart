// Exact-PTS join of every decoded frame to its original raw receipt.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../support.dart';

Json correlate(
  Json capture,
  List<dynamic> timeline,
  Json run,
  List<dynamic> frames,
) {
  const required = [
    'complete',
    'measurementComplete',
    'readerStopped',
    'processAbsent',
    'fixtureAbsent',
    'jarAbsent',
    'forwardRemoved',
    'timelineWritten',
    'packetLedgerWritten',
  ];
  if (required.any((key) => run[key] != true) ||
      run['serverShellExit'] != 0 ||
      run['readerErrors'] is! List ||
      (run['readerErrors'] as List).isNotEmpty ||
      run['cleanupErrors'] is! Map ||
      (run['cleanupErrors'] as Map).isNotEmpty) {
    throw StateError('capture or cleanup did not complete');
  }
  final media = (capture['packets'] as List)
      .where((v) => v['config'] != true)
      .toList();
  final pts = media.map((v) => v['sourcePtsUs']).toList();
  if (pts.isEmpty ||
      pts.toSet().length != pts.length ||
      frames.length != pts.length) {
    throw StateError('incomplete/ambiguous decoded packet ledger');
  }
  if (!sameList(frames.map((f) => f['sourcePtsUs']).toList(), pts)) {
    throw StateError('decoded PTS differ from the complete media ledger');
  }
  for (var i = 0; i + 1 < media.length; i++) {
    if ((media[i]['receivedHostUs'] as num) >
        (media[i + 1]['receivedHostUs'] as num)) {
      throw StateError('raw receipts are out of order');
    }
  }
  final expected = run['inputs'] as List;
  final sequences = List.generate(8, (i) => i + 1);
  if (!sameList(expected.map((v) => v['sequence']).toList(), sequences)) {
    throw StateError('expected eight unique input sequences');
  }
  if (!sameList(expected.map((v) => v['counter']).toList(), sequences)) {
    throw StateError('counter wrap is not supported by this narrow lab run');
  }
  for (final kind in ['input', 'draw']) {
    final actual =
        timeline
            .where((v) => v['kind'] == kind && v['sequence'] != 0)
            .map((v) => v['sequence'] as int)
            .toList()
          ..sort();
    if (!sameList(actual, sequences)) {
      throw StateError('missing/duplicate fixture input or first draw');
    }
  }
  if (timeline.where((v) => v['kind'] == 'draw' && v['sequence'] == 0).length !=
      1) {
    throw StateError('fixture reset or missing initial draw');
  }
  if (timeline.any(
    (v) => v['run'] != run['run'] || !['input', 'draw'].contains(v['kind']),
  )) {
    throw StateError('unrelated or unknown timeline event');
  }
  final probes = [...run['clockBefore'] as List, ...run['clockAfter'] as List];
  if (probes.length != 6 ||
      probes.any(
        (v) => (v['hostAfterUs'] as num) < (v['hostBeforeUs'] as num),
      )) {
    throw StateError('incomplete clock brackets');
  }
  final low = maximum(
    probes.map((v) => (v['targetBootUs'] as num) - (v['hostAfterUs'] as num)),
  );
  final high = minimum(
    probes.map(
      (v) => (v['targetBootUs'] as num) + 10000 - (v['hostBeforeUs'] as num),
    ),
  );
  if (low > high) throw StateError('inconsistent clock brackets');
  final counters = frames.map((v) => v['counter'] as int).toList();
  if (counters.first != 0 || counters.last != 8) {
    throw StateError('skipped, reverted or missing terminal counter');
  }
  for (var i = 0; i + 1 < counters.length; i++) {
    if (counters[i] > counters[i + 1] || counters[i + 1] > counters[i] + 1) {
      throw StateError('skipped, reverted or missing terminal counter');
    }
  }
  final draws = {
    for (final e in timeline.where((v) => v['kind'] == 'draw'))
      e['sequence']: e,
  };
  final inputs = {
    for (final e in timeline.where((v) => v['kind'] == 'input'))
      e['sequence']: e,
  };
  final rows = <Json>[];
  for (final key in expected) {
    final seq = key['sequence'] as int;
    final draw = draws[seq];
    final targetInput = inputs[seq];
    if (draw['counter'] != seq ||
        targetInput['counter'] != seq ||
        (draw['nanoUs'] as num) < (targetInput['nanoUs'] as num)) {
      throw StateError('fixture counter/time mismatch');
    }
    if ((draw['bootBeforeUs'] as num) > (draw['bootAfterUs'] as num)) {
      throw StateError('inverted target clock observation');
    }
    final frame = counters.indexOf(seq);
    final packet = media[frame];
    final received = packet['receivedHostUs'] as num;
    if ((probes.first['hostBeforeUs'] as num) >
            (key['hostBeforeSendUs'] as num) ||
        (key['hostBeforeSendUs'] as num) > received ||
        received > (probes.last['hostAfterUs'] as num)) {
      throw StateError('first packet lies outside observed input/calibration');
    }
    rows.add({
      'sequence': seq,
      'firstFrameIndex': frame,
      'sourcePtsUs': packet['sourcePtsUs'],
      'inputToFirstRawMs': (received - (key['hostBeforeSendUs'] as num)) / 1000,
      'drawEndToFirstRawLowerMs':
          (received - (draw['bootAfterUs'] as num) + low) / 1000,
      'drawEndToFirstRawUpperMs':
          (received - (draw['bootBeforeUs'] as num) + high) / 1000,
    });
  }
  return {
    'complete': true,
    'clockIntervalWidthMs': (high - low) / 1000,
    'assumptions': [
      'constant host/target boot clock offset during the bracketed run',
      'no suspend or clock step',
    ],
    'boundary': 'earliest decoded new-counter packet at host raw drain; not Flutter latency, encoder CPU or glass-to-glass',
    'packets': media.length,
    'frames': frames.length,
    'samples': rows,
  };
}

Future<(List<Json>, String)> decodeFrames(
  String path,
  String ffmpeg,
  int origin,
) async {
  final decoded = await checked(
    ffmpeg,
    [
      '-nostdin',
      '-hide_banner',
      '-xerror',
      '-threads',
      '1',
      '-i',
      path,
      '-vf',
      'scale=64:64,format=rgba,showinfo',
      '-fps_mode',
      'passthrough',
      '-f',
      'rawvideo',
      'pipe:1',
    ],
    binary: true,
    timeout: const Duration(seconds: 90),
  );
  final log = utf8.decode(decoded.stderr as List<int>);
  if (!log.contains('config in time_base: 1/1000000')) {
    throw StateError('unexpected decoded timestamp timebase');
  }
  final observed = RegExp(r'\bn:\s*(\d+)\s+pts:\s*(-?\d+)\s+pts_time:')
      .allMatches(log)
      .toList();
  final pixels = decoded.stdout as List<int>;
  if (pixels.length != observed.length * 64 * 64 * 4) {
    throw StateError('decoded pixel/PTS count mismatch');
  }
  final frames = <Json>[];
  for (var index = 0; index < observed.length; index++) {
    if (int.parse(observed[index][1]!) != index) {
      throw StateError('non-contiguous decoded frame numbers');
    }
    var counter = 0;
    const xs = [8, 24, 40, 56];
    for (var bit = 0; bit < xs.length; bit++) {
      final offset = index * 16384 + (32 * 64 + xs[bit]) * 4;
      final red = pixels[offset];
      final blue = pixels[offset + 2];
      if (!((red > 150 && blue < 150) || (red < 150 && blue > 150))) {
        throw StateError('unrecognizable decoded counter');
      }
      if (red > 150) counter |= 1 << bit;
    }
    frames.add({
      'sourcePtsUs': origin + int.parse(observed[index][2]!),
      'counter': counter,
    });
  }
  return (frames, log);
}

Future<void> run(List<String> arguments) async {
  final args = parse(options(['capture', 'ffmpeg']), arguments);
  final directory = args['capture'] as String;
  refuseEvidence(directory, [
    'decode.log',
    'decoded-frames.json',
    'first-counter.json',
  ]);
  final capture = readJson(p.join(directory, 'packets.json'));
  final result = readJson(p.join(directory, 'result.json'));
  if (result['complete'] != true) throw StateError('capture failed');
  final media = (capture['packets'] as List)
      .where((v) => v['config'] != true)
      .toList();
  final (frames, log) = await decodeFrames(
    p.join(directory, 'capture.mkv'),
    args['ffmpeg'] as String,
    media.first['sourcePtsUs'] as int,
  );
  File(p.join(directory, 'decode.log')).writeAsStringSync(log);
  final report = correlate(
    capture,
    readJsonList(p.join(directory, 'target-timeline.json')),
    result,
    frames,
  );
  writeJson(p.join(directory, 'decoded-frames.json'), frames);
  writeJson(p.join(directory, 'first-counter.json'), report);
  stdout.writeln(pretty.convert(report));
}

Future<void> main(List<String> arguments) => cli(() => run(arguments));
