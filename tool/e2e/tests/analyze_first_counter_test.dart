import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support.dart';
import '../video_fixture/analyze_first_counter.dart' as first;

(Json, List<dynamic>, Json, List<dynamic>) observation() {
  final packets = [
    for (var n = 0; n < 10; n++)
      {
        'config': false,
        'sourcePtsUs': 100 + n,
        'receivedHostUs': 10000 + n * 1000,
      },
  ];
  final frames = [
    for (var n = 0; n < 10; n++)
      {'sourcePtsUs': 100 + n, 'counter': n > 1 ? n - 1 : n},
  ];
  final run = <String, dynamic>{
    'run': 'test',
    'inputs': [
      for (var n = 1; n <= 8; n++)
        {
          'sequence': n,
          'counter': n,
          'hostBeforeSendUs': 10000 + n * 1000 - 500,
        },
    ],
    'clockBefore': [
      for (var n = 0; n < 3; n++)
        {'hostBeforeUs': 1000, 'hostAfterUs': 1020, 'targetBootUs': 10000},
    ],
    'clockAfter': [
      for (var n = 0; n < 3; n++)
        {'hostBeforeUs': 30000, 'hostAfterUs': 30020, 'targetBootUs': 40000},
    ],
  };
  final timeline = <dynamic>[
    {
      'run': 'test',
      'kind': 'draw',
      'sequence': 0,
      'counter': 0,
      'nanoUs': 10000,
    },
  ];
  for (var n = 1; n <= 8; n++) {
    timeline.addAll([
      {
        'run': 'test',
        'kind': 'input',
        'sequence': n,
        'counter': n,
        'nanoUs': 20000 + n * 1000,
      },
      {
        'run': 'test',
        'kind': 'draw',
        'sequence': n,
        'counter': n,
        'nanoUs': 20001 + n * 1000,
        'bootBeforeUs': 20001 + n * 1000,
        'bootAfterUs': 20002 + n * 1000,
      },
    ]);
  }
  run.addAll({
    for (final key in [
      'complete',
      'measurementComplete',
      'readerStopped',
      'processAbsent',
      'fixtureAbsent',
      'jarAbsent',
      'forwardRemoved',
      'timelineWritten',
      'packetLedgerWritten',
    ])
      key: true,
  });
  run.addAll({
    'serverShellExit': 0,
    'readerErrors': <dynamic>[],
    'cleanupErrors': <String, dynamic>{},
  });
  return ({'packets': packets}, timeline, run, frames);
}

void main() {
  test('CLI refuses replacing an existing observation', () async {
    final directory = Directory.systemTemp.createTempSync('first-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File(p.join(directory.path, 'first-counter.json'))
      ..writeAsStringSync('original observation');
    await expectLater(
      first.run(['--capture', directory.path, '--ffmpeg', 'unused']),
      throwsA(
        isA<FileSystemException>().having(
          (e) => e.message,
          'message',
          contains('Refusing to replace'),
        ),
      ),
    );
    expect(file.readAsStringSync(), 'original observation');
  });
  test('first pixel uses first packet rather than later same counter', () {
    final (capture, timeline, run, frames) = observation();
    final report = first.correlate(capture, timeline, run, frames);
    expect(report['samples'][0]['sourcePtsUs'], 101);
    expect(report['samples'][0]['inputToFirstRawMs'], .5);
    expect(report['samples'], hasLength(8));
  });
  test('incomplete and ambiguous media rejected', () {
    final changes = <void Function(Json, List<dynamic>, Json, List<dynamic>)>[
      (c, t, r, f) => f.removeLast(),
      (c, t, r, f) => f[2]['sourcePtsUs'] = 101,
      (c, t, r, f) => c['packets'][2]['sourcePtsUs'] = 101,
      (c, t, r, f) => f.last['counter'] = 7,
      (c, t, r, f) => f[3]['counter'] = 0,
      (c, t, r, f) => c['packets'][1]['receivedHostUs'] = 50000,
    ];
    for (final change in changes) {
      final (c, t, r, f) = observation();
      change(c, t, r, f);
      expect(() => first.correlate(c, t, r, f), throwsStateError);
    }
  });
  test('fixture and calibration failure cannot be latency sample', () {
    final changes = <void Function(Json, List<dynamic>, Json, List<dynamic>)>[
      (c, t, r, f) => t.add(jsonDecode(jsonEncode(t.first))),
      (c, t, r, f) => t.removeLast(),
      (c, t, r, f) => t[1]['run'] = 'other',
      (c, t, r, f) => t[2]['counter'] = 9,
      (c, t, r, f) => r['clockAfter'][0]['targetBootUs'] = 90000,
      (c, t, r, f) => r['inputs'][1]['sequence'] = 1,
    ];
    for (final change in changes) {
      final (c, t, r, f) = observation();
      change(c, t, r, f);
      expect(() => first.correlate(c, t, r, f), throwsStateError);
    }
  });
  test('failed cleanup cannot be accepted through early complete flag', () {
    for (final key in [
      'measurementComplete',
      'readerStopped',
      'processAbsent',
      'fixtureAbsent',
      'jarAbsent',
      'forwardRemoved',
      'timelineWritten',
      'packetLedgerWritten',
    ]) {
      final (c, t, r, f) = observation();
      r[key] = false;
      expect(
        () => first.correlate(c, t, r, f),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('cleanup'),
          ),
        ),
      );
    }
    for (final (key, value) in <(String, dynamic)>[
      ('readerErrors', ['incomplete packet']),
      ('serverShellExit', 1),
      ('cleanupErrors', {'uninstall': 'timeout'}),
    ]) {
      final (c, t, r, f) = observation();
      r[key] = value;
      expect(
        () => first.correlate(c, t, r, f),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('cleanup'),
          ),
        ),
      );
    }
  });
}
