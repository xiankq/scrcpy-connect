import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmark/live_video/frame_trace_stages.dart';

void main() {
  final native = <String, dynamic>{
    'clockOriginUs': 900000,
    'decoded': [
      {'ptsSeconds': 1.0, 'elapsedUs': 200000},
    ],
    'snapshot': {
      'ptsSeconds': 1.0,
      'submittedElapsedUs': 150000,
      'elapsedUs': 300000,
    },
  };
  final relay = <Map<String, dynamic>>[
    // writeCompletedUs deliberately follows onVideo: the consumer may run
    // before the producer's write Future resumes.
    {'ptsUs': 999999, 'writeStartedUs': 997000, 'writeCompletedUs': 1200000},
  ];

  test('joins exact frame identity using one clock for every duration', () {
    final stages = frameTraceStages(native, relay);
    expect(stages['complete'], true);
    expect(stages['relayToOnVideoUs'], 103000);
    expect(stages['onVideoToSnapshotUs'], 100000);
    expect(stages['snapshotRequestToCallbackUs'], 150000);
  });

  test(
    'missing and ambiguous PTS remain evidence instead of nearest pairing',
    () {
      for (final frames in [
        <Map<String, dynamic>>[],
        [relay.single, relay.single],
        [
          {...relay.single, 'ptsUs': 999990},
        ],
      ]) {
        final stages = frameTraceStages(native, frames);
        expect(stages['complete'], false);
        expect(stages.containsKey('relayToOnVideoUs'), false);
        expect(stages['snapshotRequestToCallbackUs'], 150000);
      }
      final stages = frameTraceStages({
        ...native,
        'decoded': [...native['decoded'] as List, ...native['decoded'] as List],
      }, relay);
      expect(stages['complete'], false);
      expect(stages['decodedMatchCount'], 2);
    },
  );

  test('rejects missing trace, nonfinite identity and reversed timing', () {
    expect(frameTraceStages(null, relay)['complete'], false);
    for (final patch in [
      {'ptsSeconds': double.nan},
      {'elapsedUs': 100000},
      {'submittedElapsedUs': 400000},
    ]) {
      final stages = frameTraceStages({
        ...native,
        'snapshot': {...native['snapshot'] as Map<String, dynamic>, ...patch},
      }, relay);
      expect(stages['complete'], false);
    }
    expect(
      frameTraceStages({...native, 'clockOriginUs': 0}, relay)['complete'],
      false,
    );
  });
}
