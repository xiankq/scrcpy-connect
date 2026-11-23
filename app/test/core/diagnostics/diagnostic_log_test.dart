import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';

void main() {
  test('日志读取保留可用记录并标记不完整历史，读取时不删除超限文件', () async {
    final directory = await Directory.systemTemp.createTemp('diagnostics-');
    addTearDown(() => directory.delete(recursive: true));
    final oversized = File('${directory.path}/events.1.jsonl');
    await oversized.writeAsString('a' * 2049);
    final record = jsonEncode({
      'time': '2026-11-22T00:00:00Z',
      'level': 'info',
      'area': 'app',
      'event': 'app.started',
      'fields': <String, Object?>{},
    });
    await File('${directory.path}/events.0.jsonl')
        .writeAsString('$record\n{"unfinished":');
    final log = await DiagnosticLog.open(directory, maxFileBytes: 2048);
    addTearDown(log.close);

    expect(log.recent.single.event, 'app.started');
    expect(log.historyIncomplete, isTrue);
    expect(await oversized.length(), 2049);
    expect(utf8.decode(await log.export()), contains('app.started'));

    await log.clear();
    expect(log.historyIncomplete, isFalse);
  });
}
