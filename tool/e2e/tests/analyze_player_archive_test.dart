import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import '../video_fixture/analyze_player_archive.dart';

(Json, Json, List<dynamic>) observation() {
  final frames = [
    for (var n = 0; n < 4; n++)
      {'generation': 7, 'ptsUs': n * 1000, 'sourcePtsUs': 1000000 + n * 1000},
  ];
  final archive = <String, dynamic>{
    'generation': 7,
    'complete': true,
    'frames': frames,
  };
  final decoded = <dynamic>[
    for (var n = 0; n < 4; n++)
      {
        'sourcePtsUs': frames[n]['sourcePtsUs'],
        'counter': [0, 1, 1, 2][n],
      },
  ];
  final samples = <Json>[];
  final timeline = <Json>[
    {'sequence': 0, 'kind': 'draw', 'counter': 0},
  ];
  for (final (seq, first, selected) in [(1, 1, 2), (2, 3, 3)]) {
    final raw = {
      'sourcePtsUs': frames[first]['sourcePtsUs'],
      'readCompletedUs': seq * 10000 + 2000,
      'captureSegment': 1,
    };
    final chosen = first == selected
        ? raw
        : {
            'sourcePtsUs': frames[selected]['sourcePtsUs'],
            'readCompletedUs': seq * 10000 + 3000,
            'captureSegment': 1,
          };
    samples.add({
      'fixtureSequence': seq,
      'expectedCounter': seq,
      'inputObservedBeforeInvokeUs': seq * 10000,
      'transportFrame': chosen,
      'transportWindow': first == selected ? [raw] : [raw, chosen],
      'relayFrame': {'sourcePtsUs': frames[selected]['sourcePtsUs']},
      'nativeFrameTrace': {
        'clockOriginUs': 0,
        'snapshot': {'elapsedUs': seq * 10000 + 4000},
        'decoded': [
          {
            'ptsSeconds': frames[first]['ptsUs']! / 1000000,
            'elapsedUs': seq * 10000 + 2500,
          },
        ],
      },
    });
    timeline.addAll([
      {'sequence': seq, 'kind': 'input', 'counter': seq},
      {
        'sequence': seq,
        'kind': 'draw',
        'counter': seq,
        'nanoUs': seq * 10000 + 3000,
      },
    ]);
  }
  final run = <String, dynamic>{
    for (final key in [
      'measurementLoopComplete',
      'appCleanupConfirmed',
      'driverCloseConfirmed',
      'fixtureCleanupConfirmed',
      'targetTimelineComplete',
      'packetArchiveRequested',
      'diagnosticOnly',
    ])
      key: true,
  };
  run.addAll({
    'rounds': [
      {'inputs': samples},
    ],
    'targetTimeline': timeline,
    'clockBounds': {
      'complete': true,
      'assumptions': 'conditional',
      'rounds': [
        {
          'valid': true,
          'intervalWidthUs': 204,
          'offsetLowerUs': 1900,
          'offsetUpperUs': 2100,
          'bootMinusMonoLowerUs': 4,
          'bootMinusMonoUpperUs': 6,
        },
      ],
    },
  });
  return (run, archive, decoded);
}

void main() {
  test('earliest frame can precede snapshot selected frame', () {
    final (r, a, d) = observation();
    final report = correlatePlayer(r, a, d);
    expect(report['samples'][0]['newCounterFramesBeforeSelected'], 1);
    expect(report['samples'][0]['firstRawToSelectedRawMs'], 1);
    expect(report['samples'][0]['firstRawToFirstOnVideoMs'], .5);
    expect(
      report['samples'][0]['drawEndToFirstRawLowerMs'],
      closeTo(.893, .0000001),
    );
    expect(
      report['samples'][0]['drawEndToFirstRawUpperMs'],
      closeTo(1.097, .0000001),
    );
  });
  test('absent earliest callback remains absent', () {
    final (r, a, d) = observation();
    r['rounds'][0]['inputs'][0]['nativeFrameTrace']['decoded'] = <dynamic>[];
    final row = correlatePlayer(r, a, d)['samples'][0];
    expect(row['earliestOnVideoObserved'], false);
    expect(row, isNot(contains('firstRawToFirstOnVideoMs')));
  });
  test('missing ambiguous reversed or failed evidence rejected', () {
    final changes = <void Function(Json, Json, List<dynamic>)>[
      (r, a, d) => r['appCleanupConfirmed'] = false,
      (r, a, d) => d.removeLast(),
      (r, a, d) => a['frames'][2]['sourcePtsUs'] = 1001000,
      (r, a, d) => d[2]['counter'] = 0,
      (r, a, d) =>
          (r['rounds'][0]['inputs'][0]['transportWindow'] as List).removeAt(0),
      (r, a, d) => (r['rounds'][0]['inputs'][0]['transportWindow'] as List).add(
        r['rounds'][0]['inputs'][0]['transportWindow'][0],
      ),
      (r, a, d) => (r['targetTimeline'] as List).add(r['targetTimeline'][1]),
      (r, a, d) =>
          r['rounds'][0]['inputs'][0]['nativeFrameTrace']['snapshot']['elapsedUs'] =
              11000,
      (r, a, d) => a['frames'][2]['generation'] = 8,
    ];
    for (final change in changes) {
      final (r, a, d) = observation();
      change(r, a, d);
      expect(() => correlatePlayer(r, a, d), throwsStateError);
    }
  });
}
