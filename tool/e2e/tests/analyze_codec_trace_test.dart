import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import '../video_fixture/analyze_codec_trace.dart';

void main() {
  late Json receipt;
  late List<Json> events;
  late List<Json> clocks;
  setUp(() {
    receipt = {
      'offsetLow': 1000000,
      'offsetHigh': 1000500,
      'frames': [
        for (final pts in [1000, 2000, 3000])
          {'pts': pts, 'headerReadUs': pts + 9000},
      ],
    };
    events = [
      for (final pts in [1000, 2000, 3000])
        {
          'ts': (1000000 + pts + 4000) * 1000,
          'dur': 100,
          'name':
              'CCodecBufferChannel::onWorkDone(c2.android.avc.encoder#1@ts=$pts)',
        },
    ];
    clocks = [
      {'boot_ns': 1000000000, 'mono_ns': 0},
    ];
  });
  test('three clock origins remain separate', () {
    final report = correlate(receipt, events, clocks, []);
    expect(report['matched'], 3);
    expect(report['allMedianUs']['sourceToWorkDoneUs'], 4000);
    expect(report['allMedianUs']['workDoneToHeaderLowerUs'], 5000);
    expect(report['allMedianUs']['workDoneToHeaderUpperUs'], 5500);
  });
  test(
    'lost duplicate and unreceived frames cannot create complete report',
    () {
      expect(
        () => correlate(receipt, events, clocks, [
          {'name': 'ftrace_cpu_overrun'},
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('data loss'),
          ),
        ),
      );
      expect(
        () => correlate(receipt, [...events, events.first], clocks, []),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Duplicate CCodec'),
          ),
        ),
      );
      (receipt['frames'] as List).removeAt(1);
      expect(
        () => correlate(receipt, events, clocks, []),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no matching'),
          ),
        ),
      );
    },
  );
  test('missing clock or changed offset rejected', () {
    final snapshots = throwsA(
      isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('snapshots'),
      ),
    );
    expect(() => correlate(receipt, events, [], []), snapshots);
    expect(
      () => correlate(receipt, events, [
        ...clocks,
        {'boot_ns': 1002000000, 'mono_ns': 0},
      ], []),
      snapshots,
    );
  });
}
