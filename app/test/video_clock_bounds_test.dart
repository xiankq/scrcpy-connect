import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/driver/video_clock_bounds.dart';

void main() {
  final round = <String, dynamic>{
    'round': 0,
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
    'samples': [
      {
        'fixtureSequence': 1,
        'counter': 1,
        'transportFrame': {
          'sourcePtsUs': 5100000,
          'firstAdbRead': {'payloadStartedUs': 2100000},
          'readCompletedUs': 2100020,
        },
      },
    ],
  };
  final timeline = <ClockJson>[
    {
      'sequence': 1,
      'counter': 1,
      'kind': 'input',
      'nanoUs': 5099000,
      'bootBeforeUs': 5099100,
      'bootAfterUs': 5099102,
    },
    {
      'sequence': 1,
      'counter': 1,
      'kind': 'draw',
      'nanoUs': 5099100,
      'bootBeforeUs': 5099200,
      'bootAfterUs': 5099202,
      'drawStartUs': 5099050,
      'drawStartBootBeforeUs': 5099150,
      'drawStartBootAfterUs': 5099152,
    },
  ];
  test('bounds source age without assuming symmetric transport or using a midpoint', () {
    final result = videoClockBounds([round], timeline);
    expect(result['complete'], true);
    final r = (result['rounds'] as List).single as ClockJson;
    expect(r['offsetLowerUs'], 3999799);
    expect(r['offsetUpperUs'], 4010001);
    final sample = (r['samples'] as List).single as ClockJson;
    expect(sample['sourceToPayloadLowerUs'], 999695);
    expect(sample['sourceToPayloadUpperUs'], 1009903);
    expect(sample['sourceToRawCompleteLowerUs'], 999715);
    expect(sample['sourceToRawCompleteUpperUs'], 1009923);
    expect(sample['drawEndToPayloadLowerUs'], 1000595);
    expect(sample['drawEndToPayloadUpperUs'], 1010803);
  });
  test('rejects incompatible probes, target clock steps and missing clock observations', () {
    for (final fault in [
      'probe',
      'bridge',
      'missing',
      'reversed',
      'eventOrder',
    ]) {
      final r = jsonDecode(jsonEncode(round)) as ClockJson;
      final t = (jsonDecode(jsonEncode(timeline)) as List).cast<ClockJson>();
      switch (fault) {
        case 'probe':
          ((r['clockAfter'] as List).single as ClockJson)
            ..['targetBootLowerUs'] = 7200000
            ..['targetBootUpperUs'] = 7210000;
        case 'bridge':
          t.last['bootBeforeUs'] = 6099200;
          t.last['bootAfterUs'] = 6099202;
        case 'missing':
          r.remove('clockAfter');
        case 'reversed':
          ((r['clockBefore'] as List).single
                  as ClockJson)['controllerAfterUs'] =
              999999;
        case 'eventOrder':
          t.last['drawStartUs'] = 5098999;
      }
      expect(videoClockBounds([r], t)['complete'], false, reason: fault);
    }
    expect(videoClockBounds([], [])['complete'], false);
  });
  test('keeps draw bounds when the additional PTS clock assumption fails', () {
    final r = jsonDecode(jsonEncode(round)) as ClockJson;
    (((r['samples'] as List).single as ClockJson)['transportFrame']
            as ClockJson)['sourcePtsUs'] =
        999999999;
    final result = videoClockBounds([r], timeline);
    expect(result['complete'], true);
    final rows = (result['rounds'] as List).single as ClockJson;
    final sample = (rows['samples'] as List).single as ClockJson;
    expect(sample['ptsCompatible'], false);
    expect(sample['drawEndToPayloadLowerUs'], 1000595);
  });
}
