import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/activities/activity_catalog.dart';
import 'package:scrcpy_connect/core/activities/activity_management.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';

void main() {
  test('只读组合丢弃变化中的快照，不把连接缓存或已完成任务列为实际活动', () async {
    final fixture = _Fixture();
    var reads = 0;
    fixture.readSessions = (_) async {
      reads++;
      if (reads == 1) fixture.revision++;
      return [
        SessionActivity(
          sessionId: reads == 1 ? 'retired' : 'current',
          deviceId: 'device',
          name: 'Screen',
          status: 'streaming',
          needsLaunchReview: true,
        ),
      ];
    };
    fixture.devices.values = [
      const DeviceSnapshot(
        id: 'device',
        name: 'Phone',
        connectionId: 'verified',
      ),
      const DeviceSnapshot(id: 'cached', name: 'Cached', status: .connected),
    ];
    fixture.transfers.values = [
      const FileTransferSnapshot(
        id: 'done',
        deviceId: 'device',
        status: .completed,
      ),
      const FileTransferSnapshot(
        id: 'cleanup',
        deviceId: 'device',
        status: .failed,
        cleanupPending: true,
      ),
      const FileTransferSnapshot(
        id: 'other',
        deviceId: 'other',
        status: .running,
      ),
    ];
    final result = await fixture.catalog.readActivities(deviceId: 'device');
    expect(reads, 2);
    expect(result.activities.map((item) => item.target.key), [
      'connection:device',
      'session:current',
      'transfer:cleanup',
    ]);
    expect(
      result.activities.every((item) => item.deviceName == 'Phone'),
      isTrue,
    );
    expect(result.pendingApplications.single.sessionId, 'current');
    expect(fixture.stopped, isEmpty);
  });

  test('持续变化的查询有界重试；关闭期间的迟到投影不能交付', () async {
    final busy = _Fixture();
    busy.readSessions = (_) async {
      busy.revision++;
      return [];
    };
    await expectLater(
      busy.catalog.readActivities(),
      throwsA(_failure('state_busy')),
    );
    expect(busy.revision, 4);
    final retiring = _Fixture();
    final pending = Completer<List<SessionActivity>>();
    retiring.readSessions = (_) => pending.future;
    final reading = retiring.catalog.readActivities();
    retiring.disposed = true;
    pending.complete([]);
    await expectLater(reading, throwsA(_failure('disposed')));
  });

  test('停止音源先核对精确设备和音源，迟到目标不能停止后继', () async {
    final fixture = _Fixture();
    fixture.sources = [
      const DeviceAudioSnapshot(
        sourceId: 'current',
        deviceId: 'device',
        generation: 2,
        name: 'Audio',
        status: .playing,
        createdAt: 1,
      ),
    ];
    for (final target in [
      const DeviceAudioTarget(deviceId: 'device', sourceId: 'retired'),
      const DeviceAudioTarget(deviceId: 'other', sourceId: 'current'),
    ]) {
      await expectLater(
        fixture.catalog.stopActivity(ActivityTarget.audio(target)),
        throwsA(_failure('not_found')),
      );
    }
    expect(fixture.stopped, isEmpty);
    await fixture.catalog.stopActivity(
      const ActivityTarget.audio(
        DeviceAudioTarget(deviceId: 'device', sourceId: 'current'),
      ),
    );
    expect(fixture.stopped, ['audio:device:current']);
  });
}

Matcher _failure(String code) =>
    isA<RequestFailure>().having((e) => e.code, 'code', code);

final class _Fixture {
  int revision = 0;
  bool disposed = false;
  final devices = _Devices();
  final transfers = _Transfers();
  final stopped = <String>[];
  List<DeviceAudioSnapshot> sources = [];
  Future<List<SessionActivity>> Function(String?) readSessions = (_) async =>
      [];
  late final catalog = ActivityCatalog(
    diagnostics: DiagnosticReporter(null),
    readRevision: () => revision,
    devices: devices,
    readSessions: ({deviceId}) => readSessions(deviceId),
    readAudio: () => sources,
    readObservations: () => [],
    transfers: transfers,
    disconnectDevice: (id) async => stopped.add('connection:$id'),
    stopVideo: (id) async => stopped.add('session:$id'),
    stopAudio: (source) async =>
        stopped.add('audio:${source.deviceId}:${source.sourceId}'),
    stopObservation: (id) async => stopped.add('observation:$id'),
    isDisposed: () => disposed,
  );
}

final class _Devices implements DeviceReader {
  List<DeviceSnapshot> values = [];
  @override
  List<DeviceSnapshot> readDevices() => values;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('活动组合不应执行：${invocation.memberName}');
}

final class _Transfers implements FileTransfers {
  List<FileTransferSnapshot> values = [];
  @override
  Future<FileTransferCollection> readTransfers() async =>
      FileTransferCollection(transfers: values);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('只读活动不应执行传输：${invocation.memberName}');
}
