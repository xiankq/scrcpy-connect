import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/diagnostics/diagnostic_log.dart';
import 'package:interop_bridge/src/diagnostics/diagnostic_reporter.dart';
import 'package:interop_bridge/src/interop_exception.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late DiagnosticLog log;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('connect-log-test-');
    log = await DiagnosticLog.open(directory, maxFileBytes: 2048, fileCount: 3);
  });
  tearDown(() async {
    await log.close();
    await directory.delete(recursive: true);
  });

  test('production decoder events identify backend without inventing hardware proof', () async {
    final reporter = DiagnosticReporter(log);
    reporter.playerEvent(DiagnosticArea.video, 'private-session', {
      'category': 'decoder.video',
      'detail': 'AMediaCodec',
      'error': -38,
    }, generation: 1);
    reporter.playerEvent(DiagnosticArea.video, 'private-session', {
      'category': 'decoder.video',
      'detail': 'FFmpeg',
      'error': 0,
    }, generation: 1);
    reporter.playerEvent(DiagnosticArea.video, 'private-session', {
      'category': 'decoder.video',
      'detail': 'AMediaCodec',
      'error': 0,
    }, generation: 2);
    expect(log.recent.map((r) => r.event), [
      'decoder.failed',
      'decoder.selected',
      'decoder.selected',
    ]);
    expect(log.recent[1].fields['acceleration'], 'software');
    expect(log.recent[2].fields['acceleration'], 'unknown');
    expect(log.recent.map((r) => r.fields['scope']).toSet(), hasLength(1));
    final exported = utf8.decode(await log.export());
    expect(exported, isNot(contains('private-session')));
    expect(exported, contains('FFmpeg'));
  });

  test(
    'payloads, credentials, native messages and error details never reach disk',
    () async {
      final reporter = DiagnosticReporter(log);
      reporter.command(
        'clipboard.set',
        {'deviceId': 'secret-device', 'text': 'clipboard-secret'},
        12,
        error: const InteropException('connection_lost', 'token-secret', {
          'key': 'private-key',
        }),
      );
      log.record(
        DiagnosticArea.app,
        'app.error',
        fields: {
          'token': 'token-secret',
          'message': 'message-secret',
          'path': '/secret/path',
          'decoder': 'http://127.0.0.1:1234/private-token',
          'errorType': 'StateError',
          'count': double.infinity,
        },
      );
      reporter.playerEvent(DiagnosticArea.video, 'secret-session', {
        'category': 'decoder.video',
        'detail': 'native-message-secret',
        'error': 0,
      });
      final exported = utf8.decode(await log.export());
      for (final secret in [
        'secret-device',
        'clipboard-secret',
        'token-secret',
        'private-key',
        'message-secret',
        '/secret/path',
        'private-token',
        'native-message-secret',
        'secret-session',
      ]) {
        expect(exported, isNot(contains(secret)), reason: secret);
      }
      expect(exported, contains('connection_lost'));
      expect(exported, contains('StateError'));
      expect(exported, contains('unknown'));
    },
  );

  test(
    'rotation, restart and export retain bounded complete JSON records',
    () async {
      for (var index = 0; index < 80; index++) {
        log.record(DiagnosticArea.app, 'app.sample', fields: {'count': index});
      }
      await log.flush();
      final files = await directory
          .list()
          .where((f) => f is File)
          .cast<File>()
          .toList();
      expect(files.length, lessThanOrEqualTo(3));
      for (final file in files) {
        expect(await file.length(), lessThanOrEqualTo(2048));
      }
      await log.close();
      log = await DiagnosticLog.open(
        directory,
        maxFileBytes: 2048,
        fileCount: 3,
      );
      final records = const LineSplitter()
          .convert(utf8.decode(await log.export()))
          .map((line) => jsonDecode(line) as Map)
          .toList();
      expect(records.length, lessThan(80));
      expect(records.last['fields']['count'], 79);
      expect(log.recent.last.fields['count'], 79);
      await log.clear();
      expect(log.recent, isEmpty);
      expect(utf8.decode(await log.export()).trim(), isEmpty);
      log.record(DiagnosticArea.app, 'app.afterClear');
      expect(utf8.decode(await log.export()), contains('app.afterClear'));
    },
  );

  test(
    'write queue stays bounded and exports an explicit dropped-record count',
    () async {
      for (var index = 0; index < 1000; index++) {
        log.record(DiagnosticArea.app, 'app.sample', fields: {'count': index});
      }
      expect(log.recent, hasLength(DiagnosticLog.recentLimit));
      final exported = utf8.decode(await log.export());
      expect(exported, contains('log.dropped'));
      expect(exported, contains('744'));
    },
  );

  test('unavailable storage preserves a safe in-memory fallback', () async {
    await log.close();
    final blocker = File(p.join(directory.path, 'blocker'));
    await blocker.writeAsString('not a directory');
    log = await DiagnosticLog.open(Directory(p.join(blocker.path, 'logs')));
    log.record(DiagnosticArea.app, 'app.sample');
    await log.flush();
    expect(log.storageError, isNotNull);
    expect(log.recent.single.event, 'app.sample');
    expect(utf8.decode(await log.export()), contains('app.sample'));
  });

  test('restart repairs a truncated final record before appending', () async {
    log.record(DiagnosticArea.app, 'app.beforeCrash');
    await log.close();
    await File(p.join(directory.path, 'events.0.jsonl'))
        .writeAsString('{"time":"partial', mode: FileMode.append);
    log = await DiagnosticLog.open(directory, maxFileBytes: 2048, fileCount: 3);
    log.record(DiagnosticArea.app, 'app.afterCrash');
    final lines = const LineSplitter().convert(utf8.decode(await log.export()));
    expect(lines.map((line) => (jsonDecode(line) as Map)['event']), [
      'app.beforeCrash',
      'app.afterCrash',
    ]);
  });

  test('export drains records added during an existing flush', () async {
    log.record(DiagnosticArea.app, 'app.beforeFlush');
    final flushing = log.flush();
    // The first batch is captured before directory IO yields.
    await Future<void>.delayed(Duration.zero);
    log.record(DiagnosticArea.app, 'app.duringFlush');
    final exported = utf8.decode(await log.export());
    await flushing;
    expect(exported, contains('app.beforeFlush'));
    expect(exported, contains('app.duringFlush'));
    await log.clear();
    expect(utf8.decode(await log.export()).trim(), isEmpty);
  });
}
