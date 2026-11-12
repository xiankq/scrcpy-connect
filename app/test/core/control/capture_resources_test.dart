import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/control/app_launch_journal.dart';
import 'package:scrcpy_connect/core/control/capture_resources.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/settings/app_settings.dart';

void main() {
  test('捕获模块可独立装配，空投影和退出不调用原生执行能力', () async {
    final captures = await _resources();
    expect(captures.currentSessions(), isEmpty);
    expect(await captures.readSessions(), isEmpty);
    expect(await captures.readRecoverySessions(), isEmpty);
    expect(await captures.readActivitySessions(), isEmpty);
    expect(captures.audioSnapshots(), isEmpty);
    captures.settingsChanged();
    await captures.close();
    await captures.close();
    expect(() => captures.capture, throwsA(isA<RequestFailure>()));
    expect(() => captures.sessions, throwsA(isA<RequestFailure>()));
    expect(() => captures.keepAwake, throwsA(isA<RequestFailure>()));
  });

  test('只创建剪贴板会话后关闭，不创建新的捕获或唤醒能力', () async {
    final captures = await _resources();
    final clipboard = captures.sessions;
    await captures.close();
    expect(identical(captures.sessions, clipboard), isTrue);
    expect(() => captures.audio, throwsA(isA<RequestFailure>()));
    expect(() => captures.keepAwake, throwsA(isA<RequestFailure>()));
    expect(await captures.readSessions(), isEmpty);
    expect(await captures.readRecoverySessions(), isEmpty);
  });

  test('捕获模块关闭不接管借用的设备清单查询', () async {
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
    await expectLater(
      captures.sessions.readVideoQualityOptions('device'),
      unavailable,
    );
    await captures.close();
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
}) async {
  final directory = await Directory.systemTemp.createTemp('capture-resources-');
  addTearDown(() => directory.delete(recursive: true));
  final records = await DeviceRecordStorage.open(directory: directory);
  final settings = AppSettings(
    preferences: await AppSettings.prepare(directory),
    records: records,
    onDevicesImported: (_) {},
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
    launches: await AppLaunchJournal.open(directory: directory),
    diagnostics: DiagnosticReporter(null),
    isDisposed: () => false,
    isStateUnverified: () => false,
    publish: (_) => throw StateError('空模块不应发布业务变化'),
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
