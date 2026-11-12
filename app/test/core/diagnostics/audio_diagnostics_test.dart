import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_changed.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';

void main() {
  test('类型化音源事件只记录终止状态和匿名范围，不写设备名称及失败正文', () async {
    final directory = await Directory.systemTemp.createTemp(
      'audio-diagnostics-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final log = await DiagnosticLog.open(directory);
    addTearDown(log.close);
    final reporter = DiagnosticReporter(log);
    const source = DeviceAudioSnapshot(
      sourceId: 'private-source',
      deviceId: 'private-device',
      generation: 2,
      name: 'private-name',
      status: .playing,
      createdAt: 1,
      reason: 'private-error-body',
    );
    reporter.applicationEvent(
      const DeviceAudioChanged(source).toApplicationEvent(),
    );
    expect(log.recent, isEmpty);
    reporter.applicationEvent(
      DeviceAudioChanged(source.copyWith(status: .stopped))
          .toApplicationEvent(),
    );
    reporter.applicationEvent(
      DeviceAudioChanged(source.copyWith(status: .error)).toApplicationEvent(),
    );
    final records = log.recent;
    expect(records.map((e) => e.event), ['audio.updated', 'audio.updated']);
    expect(records.map((e) => e.level), [LogLevel.info, LogLevel.error]);
    expect(records.map((e) => e.fields), [
      {'scope': log.scope(source.deviceId), 'status': 'stopped'},
      {'scope': log.scope(source.deviceId), 'status': 'error'},
    ]);
    expect(
      records.map((e) => e.fields).toString(),
      isNot(contains('private-')),
    );
  });
}
