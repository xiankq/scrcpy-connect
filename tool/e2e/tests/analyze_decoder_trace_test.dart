import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../analyze_decoder_trace.dart' as decoder;
import '../support.dart';

Json event(String name, int timestamp, [int pid = 42]) => {
  'id': '1',
  'ts': '$timestamp',
  'dur': '100',
  'name': name,
  'pid': '$pid',
};

void main() {
  late List<Json> slices;
  late Json benchmark;
  Json sample() =>
      (decoder.correlate(slices, benchmark, 42)['inputs'] as List).first
          as Json;
  setUp(() {
    slices = [
      event('CCodecBufferChannel::queue(decoder#1@ts=999999)', 90000000000),
      event(
        'CCodecBufferChannel::onWorkDone(decoder#1@ts=999999)',
        90002000000,
      ),
      event('connect.onVideo(t=7@ts=1000000)', 90102000000),
    ];
    benchmark = {
      'rounds': <dynamic>[
        {
          'round': 0,
          'inputs': [
            {
              'relayFrame': {'ptsUs': 1000000, 'writeStartedUs': 997000},
              'nativeFrameTrace': {
                'traceToken': 7,
                'clockOriginUs': 900000,
                'decoded': [
                  {'ptsSeconds': 1.0, 'elapsedUs': 200000},
                ],
              },
            },
          ],
        },
      ],
    };
  });
  test('separate clocks and one microsecond PTS truncation', () {
    final result = sample();
    expect(result['queueToDoneMs'], 2);
    expect(result['doneToOnVideoMs'], 100);
    expect(result['relayToOnVideoMs'], 103);
    expect(result['tracePtsUs'], 999999);
  });
  test('another player token cannot supply marker', () {
    slices[2]['name'] = 'connect.onVideo(t=8@ts=1000000)';
    expect(sample(), isNot(contains('doneToOnVideoMs')));
    expect(sample(), isNot(contains('queueToDoneMs')));
  });
  test('another process cannot supply marker', () {
    slices[2]['pid'] = '43';
    expect(sample(), isNot(contains('doneToOnVideoMs')));
    expect(sample(), isNot(contains('queueToDoneMs')));
  });
  test('repeated native decode cannot be chosen', () {
    (benchmark['rounds'][0]['inputs'][0]['nativeFrameTrace']['decoded'] as List)
        .add({'ptsSeconds': 1.0, 'elapsedUs': 100000});
    expect(sample(), isNot(contains('relayToOnVideoMs')));
  });
  test('missing repeated codec events cannot reuse another session pair', () {
    final second = jsonDecode(jsonEncode(benchmark['rounds'][0]));
    second['round'] = 1;
    second['inputs'][0]['nativeFrameTrace']['traceToken'] = 8;
    (benchmark['rounds'] as List).add(second);
    slices.add(event('connect.onVideo(t=8@ts=1000000)', 95102000000));
    for (final row
        in decoder.correlate(slices, benchmark, 42)['inputs'] as List) {
      expect(row, isNot(contains('queueToDoneMs')));
      expect(row, isNot(contains('doneToOnVideoMs')));
    }
  });
  test('reused PTS across codec instances is ambiguous', () {
    slices.addAll([
      event('CCodecBufferChannel::queue(decoder#2@ts=999999)', 80000000000),
      event(
        'CCodecBufferChannel::onWorkDone(decoder#2@ts=999999)',
        80002000000,
      ),
    ]);
    expect(sample()['unmatched'], 'codec_pair_count=2');
    expect(sample(), isNot(contains('queueToDoneMs')));
  });
  test('repeated queue or callback cannot be chosen', () {
    slices.add(Map.of(slices.first));
    expect(sample(), contains('unmatched'));
    slices.removeLast();
    slices.add(Map.of(slices[2]));
    expect(sample(), isNot(contains('doneToOnVideoMs')));
  });
  test('marker preceding work done cannot produce negative latency', () {
    slices[2]['ts'] = '90001000000';
    expect(sample()['markerUnmatched'], 'marker_precedes_work_done');
  });
  test('CLI rejects empty failed benchmark', () async {
    final directory = Directory.systemTemp.createTempSync('decoder-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final input = p.join(directory.path, 'benchmark.json');
    writeJson(input, {'rounds': <dynamic>[]});
    await expectLater(
      decoder.run([
        '--trace-processor',
        'unused',
        '--trace',
        'unused',
        '--benchmark',
        input,
        '--pid',
        '42',
        '--output',
        p.join(directory.path, 'output.json'),
        '--require-markers',
      ], query: (_) async => []),
      throwsStateError,
    );
  });
}
