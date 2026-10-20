import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support.dart';
import '../video_fixture/analyze_capture_slots.dart';

Json event(int ts, int slot, String operation, [int? identity]) => {
  'sliceId': identity ?? ts,
  'ts': ts,
  'dur': 1,
  'name': 'GraphicBufferSource: $slot',
  'operation': operation,
  'operationSliceId': ts + 1000,
  'operationTs': ts - 1,
  'operationDur': 3,
};
Matcher rejects(String message) => throwsA(
  isA<StateError>().having((e) => e.message, 'message', contains(message)),
);

void main() {
  test(
    'first release infers initial acquisition without invented duration',
    () {
      final report = analyzeSlots([
        event(10, 7, 'releaseBuffer'),
        event(20, 7, 'dequeueBuffer'),
        event(30, 7, 'queueBuffer'),
        event(40, 7, 'acquireBuffer'),
        event(90, 7, 'releaseBuffer'),
      ]);
      expect(report['initialAcquiredSlotsInferred'], [7]);
      expect(report['initialPartialReleases'], [
        {'slot': 7, 'releaseSliceId': 10, 'releasedAtNs': 10},
      ]);
      expect(report['counts']['completePairs'], 1);
      expect(report['pairs'][0]['holdNs'], 50);
      expect(report['finalAcquiredSlots'], isEmpty);
    },
  );
  test('terminal acquisition saved without inventing window-end release', () {
    final report = analyzeSlots([
      event(10, 4, 'acquireBuffer'),
      event(20, 4, 'releaseBuffer'),
      event(30, 4, 'acquireBuffer'),
      event(100, 9, 'queueBuffer'),
    ]);
    expect(report['allHolds']['count'], 1);
    expect(report['allHolds']['medianMs'], 10 / 1e6);
    expect(report['terminalAcquisitions'], [
      {'slot': 4, 'acquireSliceId': 30, 'acquiredAtNs': 30},
    ]);
    expect(report['finalAcquiredSlots'], [4]);
  });
  test('occupancy weighted by wall clock and slot event starts', () {
    final rows = [
      event(10, 2, 'acquireBuffer'),
      event(11, 3, 'dequeueBuffer'),
      event(12, 3, 'queueBuffer'),
      event(13, 3, 'dequeueBuffer'),
      event(14, 3, 'queueBuffer'),
      event(85, 2, 'releaseBuffer'),
      event(100, 3, 'dequeueBuffer'),
    ];
    rows.last.addAll({'dur': 50, 'operationDur': 52});
    final report = analyzeSlots(rows);
    expect(report['window']['lastThirdStartNs'], 70);
    expect(report['window']['endExclusiveNs'], 100);
    expect(report['lastThirdOccupancy'], [
      {'acquiredSlots': 0, 'durationNs': 15, 'percent': 50.0},
      {'acquiredSlots': 1, 'durationNs': 15, 'percent': 50.0},
    ]);
    expect(report['lastThirdReleasedHolds']['medianMs'], 75 / 1e6);
    expect((report['events'] as List).length, rows.length);
  });
  test('invalid state sequences rejected', () {
    final cases = [
      (
        [event(10, 2, 'acquireBuffer'), event(20, 2, 'acquireBuffer')],
        'Duplicate acquire',
      ),
      (
        [event(10, 2, 'queueBuffer'), event(20, 2, 'releaseBuffer')],
        'without acquisition',
      ),
      (
        [event(10, 2, 'releaseBuffer'), event(20, 2, 'releaseBuffer')],
        'without acquisition',
      ),
      (
        [event(10, 2, 'acquireBuffer'), event(20, 2, 'dequeueBuffer')],
        'while slot',
      ),
    ];
    for (final (rows, message) in cases) {
      expect(() => analyzeSlots(rows), rejects(message));
    }
  });
  test('missing or ambiguous trace evidence rejected', () {
    final good = [event(10, 1, 'acquireBuffer'), event(20, 1, 'releaseBuffer')];
    expect(
      () => analyzeSlots(good, [
        {'name': 'ftrace_cpu_overrun', 'value': 1},
      ]),
      rejects('data loss'),
    );
    expect(() => analyzeSlots([]), rejects('positive wall-clock'));
    expect(
      () => analyzeSlots(good.reversed.toList()),
      rejects('timestamp order'),
    );
    expect(
      () => analyzeSlots([
        event(10, 1, 'acquireBuffer', 1),
        event(10, 1, 'releaseBuffer', 2),
      ]),
      rejects('Same-slot timestamps'),
    );
    expect(
      () => analyzeSlots([
        good.first,
        event(20, 1, 'releaseBuffer', good.first['sliceId'] as int),
      ]),
      rejects('Duplicate slot slice'),
    );
  });
  test('malformed and unclosed slot or parent slices rejected', () {
    final cases = <(String, dynamic, String)>[
      ('name', 'GraphicBufferSource: nope', 'Malformed slot'),
      ('operation', null, 'Malformed slot'),
      ('ts', '1.5', 'Malformed integer'),
      ('dur', -1, 'unclosed'),
      ('operationDur', -1, 'unclosed'),
      ('operationTs', 11, 'outside'),
      ('dur', 10, 'outside'),
    ];
    for (final (key, value, message) in cases) {
      final rows = [
        event(10, 1, 'acquireBuffer'),
        event(20, 1, 'releaseBuffer'),
      ];
      rows.first[key] = value;
      expect(
        () => analyzeSlots(rows),
        throwsA(predicate((e) => '$e'.contains(message))),
      );
    }
  });
  test(
    'CLI rejects missing or ambiguous exact process before writing',
    () async {
      final directory = Directory.systemTemp.createTempSync('slots-test-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final output = p.join(directory.path, 'must-not-exist.json');
      for (final rows in [
        <Json>[],
        <Json>[
          {'upid': '1', 'pid': '12', 'name': 'same-name'},
          {'upid': '2', 'pid': '34', 'name': 'same-name'},
        ],
      ]) {
        var calls = 0;
        await expectLater(
          run(
            [
              '--trace-processor',
              'unused',
              '--trace',
              'unused',
              '--process-name',
              'same-name',
              '--output',
              output,
            ],
            query: (_) async {
              calls++;
              return rows;
            },
          ),
          rejects('unique exact process'),
        );
        expect(calls, 1);
        expect(File(output).existsSync(), false);
      }
    },
  );
  test('CLI preserves existing evidence', () async {
    final directory = Directory.systemTemp.createTempSync('slots-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final output = File(p.join(directory.path, 'existing.json'))
      ..writeAsStringSync('original evidence\n');
    var call = 0;
    final responses = <List<Json>>[
      [
        {'upid': '5', 'pid': '12', 'name': 'chosen'},
      ],
      [],
      [event(10, 2, 'acquireBuffer', 1), event(20, 2, 'releaseBuffer', 2)],
    ];
    await expectLater(
      run([
        '--trace-processor',
        'unused',
        '--trace',
        'unused',
        '--process-name',
        'chosen',
        '--output',
        output.path,
      ], query: (_) async => responses[call++]),
      throwsA(isA<FileSystemException>()),
    );
    expect(output.readAsStringSync(), 'original evidence\n');
  });
}
