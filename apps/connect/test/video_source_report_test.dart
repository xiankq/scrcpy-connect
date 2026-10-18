import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../test_driver/video_source_report.dart';

void main() {
  Map<String, dynamic> input(int sequence, int counter) => {
    'fixtureSequence': sequence,
    'counter': counter,
    'inputObservedBeforeInvokeUs': 1080000 + sequence * 1000,
    'transportFrame': {
      'sourcePtsUs': 5100000 + sequence * 1000,
      'firstAdbRead': {'payloadStartedUs': 2100000 + sequence * 1000},
      'readCompletedUs': 2100020 + sequence * 1000,
    },
  };
  Map<String, dynamic> round(List<Map<String, dynamic>> inputs, int pause) => {
    'round': pause,
    'inputs': inputs,
    'pause': {
      'stage': 'complete',
      'fixtureSequence': pause,
      'expectedCounter': pause == 3 ? 1 : 3,
    },
    'clockBefore': [
      {
        'controllerBeforeUs': 1000000,
        'controllerAfterUs': 1000200,
        'targetBootLowerUs': 5000000,
        'targetBootUpperUs': 5010000,
      },
    ],
    'clockAfter': [
      {
        'controllerBeforeUs': 2200000,
        'controllerAfterUs': 2200200,
        'targetBootLowerUs': 6200000,
        'targetBootUpperUs': 6210000,
      },
    ],
  };
  final rounds = [
    round([input(1, 15), input(2, 0)], 3),
    round([input(4, 2)], 5),
  ];
  final timeline = <Map<String, dynamic>>[
    {'sequence': 0, 'counter': 0, 'kind': 'draw'},
    for (final (sequence, counter) in [(1, 15), (2, 0), (3, 1), (4, 2), (5, 3)])
      for (final kind in ['input', 'draw'])
        {
          'sequence': sequence,
          'counter': counter,
          'kind': kind,
          'nanoUs': 5099000 + sequence * 1000 + (kind == 'draw' ? 100 : 0),
          'bootBeforeUs':
              5099100 + sequence * 1000 + (kind == 'draw' ? 100 : 0),
          'bootAfterUs': 5099102 + sequence * 1000 + (kind == 'draw' ? 100 : 0),
          if (kind == 'draw') ...{
            'drawStartUs': 5099050 + sequence * 1000,
            'drawStartBootBeforeUs': 5099150 + sequence * 1000,
            'drawStartBootAfterUs': 5099152 + sequence * 1000,
          },
        },
  ];

  test('joins wrapped counters and pause keys across multiple rounds', () {
    final result = videoSourceReport(rounds, timeline);
    expect(result['targetTimelineComplete'], true);
    expect(result['targetTimelineIssues'], isEmpty);
    expect(result['targetDrawSegments'], hasLength(5));
    expect((result['clockBounds'] as Map)['complete'], true);
    final bounds = ((result['clockBounds'] as Map)['rounds'] as List).first;
    final sample = (bounds['samples'] as List).first as Map;
    expect(sample['observedInputToTargetInputLowerUs'], 9097);
    expect(sample['observedInputToTargetInputUpperUs'], 19305);
    expect(sample['observedInputToDrawStartLowerUs'], 9147);
    expect(sample['observedInputToDrawEndUpperUs'], 19405);
    expect(sample['drawEndToRawCompleteLowerUs'], 1000615);
  });

  test('rejects Activity resets, missing pause draws and unexpected keys', () {
    for (final fault in [
      'reset',
      'missing',
      'duplicate',
      'counter',
      'order',
      'extra',
    ]) {
      final altered = (jsonDecode(jsonEncode(timeline)) as List)
          .cast<Map<String, dynamic>>();
      switch (fault) {
        case 'reset':
          altered.add({...altered.first});
        case 'missing':
          altered.removeWhere((r) => r['sequence'] == 3 && r['kind'] == 'draw');
        case 'duplicate':
          altered.add({...altered[1]});
        case 'counter':
          altered[3]['counter'] = 15;
        case 'order':
          altered[2]['drawStartUs'] = 0;
        case 'extra':
          altered.add({...altered[1], 'sequence': 99});
      }
      expect(
        videoSourceReport(rounds, altered)['targetTimelineComplete'],
        false,
        reason: fault,
      );
    }
  });

  test(
    'rejects requested sequence reuse and keeps failed clock brackets explicit',
    () {
      final reused = (jsonDecode(jsonEncode(rounds)) as List)
          .cast<Map<String, dynamic>>();
      (reused.last['inputs'] as List).first['fixtureSequence'] = 1;
      expect(
        videoSourceReport(reused, timeline)['targetTimelineComplete'],
        false,
      );
      final outside = (jsonDecode(jsonEncode(rounds)) as List)
          .cast<Map<String, dynamic>>();
      (outside.first['inputs'] as List).first['inputObservedBeforeInvokeUs'] =
          0;
      final result = videoSourceReport(outside, timeline);
      expect(result['targetTimelineComplete'], true);
      expect((result['clockBounds'] as Map)['complete'], false);
      expect(videoSourceReport([], [])['targetTimelineComplete'], false);
    },
  );
}
