import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/control/app_launch_journal.dart';
import 'package:scrcpy_connect/core/control/capture_resources.dart';
import 'package:scrcpy_connect/core/control/media_capture.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/device_metadata_transfer.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/settings/app_settings.dart';
import 'package:scrcpy_connect/core/settings/models/settings_changed.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

void main() {
  test('持久化待核对记录进入活动及恢复投影，不创建捕获子资源', () async {
    final directory = await Directory.systemTemp.createTemp('pending-launch-');
    addTearDown(() => directory.delete(recursive: true));
    const operation = '00000000-0000-0000-0000-000000000001';
    const original = '00000000-0000-0000-0000-000000000002';
    final previous = await AppLaunchJournal.open(directory: directory);
    await previous.begin(
      operationId: operation,
      sessionId: original,
      deviceId: 'phone',
      packageName: 'com.example.app',
    );
    final launches = await AppLaunchJournal.open(directory: directory);
    final resources = await _resources(launches: launches);
    final activities = await resources.readActivitySessions(deviceId: 'phone');
    expect(activities.single.sessionId, operation);
    expect(activities.single.linkedSessionId, original);
    expect(activities.single.recordOnly, isTrue);
    expect(activities.single.needsLaunchReview, isTrue);
    expect(await resources.readActivitySessions(deviceId: 'other'), isEmpty);
    final recovered = (await resources.readRecoverySessions()).single;
    expect(recovered.session.sessionId, operation);
    expect(recovered.session.failureCode, 'interrupted');
    expect(recovered.keepAwake!.keepActiveLeaseActive, isFalse);
    expect(resources.currentSessions(), isEmpty);
    await resources.close();
    expect(() => resources.capture, throwsA(isA<RequestFailure>()));
    expect(() => resources.sessions, throwsA(isA<RequestFailure>()));
    expect(() => resources.audio, throwsA(isA<RequestFailure>()));
    expect(() => resources.keepAwake, throwsA(isA<RequestFailure>()));
    expect((await launches.unresolved()).single.operationId, operation);
  });

  test('空投影和退出不调用原生能力，只创建实际取得的子能力', () async {
    final notCreated = throwsA(isA<RequestFailure>());
    final owners = <String, Object Function(CaptureResources)>{
      'none': (_) => Object(),
      'capture': (resources) => resources.capture,
      'audio': (resources) => resources.audio,
      'sessions': (resources) => resources.sessions,
    };
    for (final MapEntry(key: name, value: take) in owners.entries) {
      final resources = await _resources();
      final taken = take(resources);
      expect(resources.currentSessions(), isEmpty, reason: name);
      expect(await resources.readSessions(), isEmpty, reason: name);
      expect(await resources.readRecoverySessions(), isEmpty, reason: name);
      expect(await resources.readActivitySessions(), isEmpty, reason: name);
      expect(resources.audioSnapshots(), isEmpty, reason: name);
      resources.handleApplicationEvent(
        SettingsChanged(Preferences()).toApplicationEvent(sequence: 1),
      );
      if (taken is MediaCapture) {
        final wake = taken.readWake('device');
        expect(wake.keepActive, isFalse);
        expect(wake.keepActiveLeaseActive, isFalse);
      }
      await resources.close();
      await resources.close();
      resources.handleApplicationEvent(
        SettingsChanged(Preferences()).toApplicationEvent(sequence: 2),
      );
      if (name != 'capture') expect(() => resources.capture, notCreated);
      if (name != 'audio') expect(() => resources.audio, notCreated);
      if (name != 'sessions') expect(() => resources.sessions, notCreated);
      expect(() => resources.keepAwake, notCreated, reason: name);
    }
  });

  test('画质查询失败交给调用方，关闭捕获模块不关闭借用的设备清单查询', () async {
    final queries = ScrcpyServerQueries(
      serverBytes: Uint8List(0),
      timeout: const Duration(seconds: 1),
    );
    addTearDown(queries.close);
    final connection = DeviceConnection(
      client: _UnusedClient(),
      device: const AdbDevice(
        id: 'connection',
        serial: 'phone',
        state: 'device',
      ),
    );
    final captures = await _resources(
      readServerQueries: () => queries,
      requireConnection: (_) => connection,
    );
    final unavailable = throwsA(
      isA<RequestFailure>().having((e) => e.code, 'code', 'encoder_probe'),
    );
    expect(await captures.capture.readVideoSessions(), isEmpty);
    await expectLater(
      captures.capture.readVideoQualityOptions('device'),
      unavailable,
    );
    await expectLater(
      captures.sessions.readVideoQualityOptions('device'),
      unavailable,
    );
    await captures.close();
    expect(() => captures.audio, throwsA(isA<RequestFailure>()));
    expect(() => captures.keepAwake, throwsA(isA<RequestFailure>()));
    await expectLater(
      () => queries.encoders(connection, AdbCancellation()),
      unavailable,
    );
    await queries.close();
    await expectLater(
      () => queries.encoders(connection, AdbCancellation()),
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'disposed')),
    );
  });
}

Future<CaptureResources> _resources({
  ScrcpyServerQueries Function()? readServerQueries,
  DeviceConnection Function(String)? requireConnection,
  AppLaunchJournal? launches,
}) async {
  final directory = await Directory.systemTemp.createTemp('capture-resources-');
  addTearDown(() => directory.delete(recursive: true));
  final records = await DeviceRecordStorage.open(directory: directory);
  final settings = AppSettings(
    preferences: await AppSettings.prepare(directory),
    metadata: DeviceMetadataTransfer(
      records: records,
      prepareImport: () async => throw StateError('捕获不应导入设备'),
      holdReconnect: () => throw StateError('捕获不应冻结设备连接'),
      onImported: () => throw StateError('捕获不应发布设备导入'),
      isDisposed: () => false,
    ),
    onChanged: (_) {},
  );
  return CaptureResources(
    scrcpy: ScrcpyClient(_UnusedScrcpy()),
    readServerQueries:
        readServerQueries ?? () => throw StateError('空读取和剪贴板不应取得设备清单查询器'),
    requireConnection: requireConnection ?? (_) => throw StateError('不应取得连接'),
    connectionForDevice: (_) => throw StateError('不应读取连接'),
    records: records,
    preferences: settings,
    launches: launches ?? await AppLaunchJournal.open(directory: directory),
    diagnostics: DiagnosticReporter(null),
    isDisposed: () => false,
    isStateUnverified: () => false,
    onChanged: (_) => throw StateError('空模块不应发布业务变化'),
    onCleanupFailure: (error) => fail('未确认清理：$error'),
  );
}

class _UnusedScrcpy implements NativeScrcpyApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('空投影或关闭不应调用 scrcpy：${invocation.memberName}');
}

class _UnusedClient implements AdbClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('清单查询缺少服务端字节时不应执行 SDK：${invocation.memberName}');
}
