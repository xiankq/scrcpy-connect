import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/display_recovery.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_resources.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/files/file_document_platform.dart';
import 'package:scrcpy_connect/core/files/file_resources.dart';
import 'package:scrcpy_connect/core/lifecycle/app_lifecycle.dart';
import 'package:scrcpy_connect/core/media/media_playback.dart';
import 'package:scrcpy_connect/core/platform/background_policy.dart';
import 'package:scrcpy_connect/core/devices/models/device_reconnect_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/state_recovery.dart';
import 'package:scrcpy_connect/core/settings/app_settings.dart';

void main() {
  test('空记录、无关事件和退出不创建未使用的设备执行所有者', () async {
    final resources = await _resources();
    expect(resources.records.current.devices, isEmpty);
    expect(
      (await resources.identities.selectForDevice()).fingerprint,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    resources.handleEvent({'type': 'settings.changed'});
    resources.handleEvent({'type': 'devices.changed'});
    await resources.stopAdmission();
    await resources.close();
    await resources.close();
    resources.handleEvent({'type': 'devices.changed'});
    _expectUnused(resources);
  });

  test('空连接取消和退休不创建伴生、观察或捕获执行器', () async {
    var stopped = 0;
    final resources = await _resources(
      stopWork: (id, connection, accepted) async {
        expect(id, 'retired-record');
        expect(accepted, isFalse);
        stopped++;
      },
    );
    final devices = resources.devices;
    expect(devices.readDevices(), isEmpty);
    await devices.cancelConnectionAttempt('unused-attempt');
    await resources.stopConnectionActivities(
      'retired-record',
      DeviceConnection(
        client: _UnusedClient(),
        device: const AdbDevice(
          id: 'old-connection',
          serial: 'serial',
          state: 'device',
        ),
      ),
    );
    expect(stopped, 1);
    await resources.close();
    expect(resources.devices, same(devices));
    expect(
      devices.readDevices,
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'disposed')),
    );
    _expectUnused(resources, devicesUsed: true);
  });

  test('重连刷新与恢复事件只读取设备投影，不装配其他能力', () async {
    var sequenceReads = 0, settingsReads = 0;
    final resources = await _resources(
      readEventSequence: () {
        sequenceReads++;
        return 0;
      },
      readBackgroundKeepAlive: () {
        settingsReads++;
        return false;
      },
    );
    expect(resources.currentObservations(), isEmpty);
    await resources.reconnections.start();
    resources.handleEvent({
      'type': 'devices.changed',
      'sequence': 1,
      'data': {'devices': <Map<String, dynamic>>[]},
    });
    resources.invalidateState();
    resources.restoreState(
      DeviceReconnectSnapshot(
        sequence: 2,
        devices: [],
        backgroundKeepAlive: false,
      ),
    );
    await resources.close();
    expect(sequenceReads, 1);
    expect(settingsReads, 1);
    _expectUnused(resources, devicesUsed: true, reconnectUsed: true);
  });

  test('应用退出等待迟到 USB 租约，重试原资源后最后释放宿主', () async {
    final authorizing = Completer<void>();
    final authorized = Completer<Map<String, dynamic>>();
    final releasing = Completer<void>();
    final released = Completer<void>();
    final cancellations = <String>[];
    final leases = <String>[];
    var releaseAllowed = false;
    final resources = await _resources(
      authorizeUsb: (params) {
        expect(params['attemptId'], 'usb-original');
        authorizing.complete();
        return authorized.future;
      },
      cancelUsb: (params) async {
        cancellations.add(params['attemptId'] as String);
      },
      releaseUsb: (params) async {
        leases.add(params['usbLeaseId'] as String);
        if (!releaseAllowed) throw StateError('USB release unconfirmed');
        releasing.complete();
        await released.future;
      },
    );
    final observations = resources.observations;
    final companion = resources.companion;
    var companionClosed = false;
    final subscription = companion.updates.listen(
      (_) {},
      onDone: () => companionClosed = true,
    );
    addTearDown(subscription.cancel);
    addTearDown(() {
      releaseAllowed = true;
      if (!released.isCompleted) released.complete();
    });
    var hostCloses = 0;
    final lifecycle = await _lifecycle(resources, () async {
      expect(companionClosed, isTrue);
      hostCloses++;
      if (hostCloses == 1) throw StateError('host release unconfirmed');
    });
    final setup = resources.setup;
    final request = setup.connectUsb(attemptId: 'usb-original');
    final requestChecked = expectLater(request, throwsA(isA<RequestFailure>()));
    await authorizing.future;
    var closeFinished = false;
    final closing = lifecycle.dispose();
    final closeChecked = expectLater(
      closing,
      throwsA(isA<StateError>()),
    ).then((_) => closeFinished = true);
    await Future<void>.delayed(Duration.zero);
    expect(closeFinished, isFalse);
    expect(cancellations, ['usb-original']);
    authorized.complete({'usbLeaseId': 'original-lease', 'fd': 7});
    await requestChecked;
    await closeChecked;
    expect(lifecycle.isDisposed, isTrue);
    expect(hostCloses, 0);
    expect(leases, isNotEmpty);
    expect(leases.every((lease) => lease == 'original-lease'), isTrue);
    expect(companionClosed, isFalse);
    expect(resources.setup, same(setup));
    expect(resources.observations, same(observations));
    expect(resources.companion, same(companion));
    expect(() => resources.apps, throwsA(isA<RequestFailure>()));

    releaseAllowed = true;
    var retryFinished = false;
    final retry = expectLater(
      lifecycle.dispose(),
      throwsA(isA<StateError>()),
    ).then((_) => retryFinished = true);
    await releasing.future;
    expect(retryFinished, isFalse);
    expect(companionClosed, isFalse);
    released.complete();
    await retry;
    await Future<void>.delayed(Duration.zero);
    expect(companionClosed, isTrue);
    expect(hostCloses, 1);
    expect(cancellations.every((id) => id == 'usb-original'), isTrue);
    expect(leases.every((lease) => lease == 'original-lease'), isTrue);
    final releases = leases.length;
    await lifecycle.dispose();
    expect(hostCloses, 2);
    await lifecycle.dispose();
    expect(hostCloses, 2);
    expect(leases, hasLength(releases));
  });
}

Future<AppLifecycle> _lifecycle(
  DeviceResources resources,
  Future<void> Function() closeHost,
) async {
  final directory = resources.identities.directory;
  final settings = AppSettings(
    preferences: await AppSettings.prepare(directory),
    records: resources.records,
    onDevicesImported: (_) {},
    onChanged: (_) {},
  );
  final events = RuntimeEvents(
    acceptState: (_) => true,
    onState: (_) {},
    beforePublish: (_) {},
    afterState: (_) {},
    handlePlatform: (_) async {},
    isDisposed: () => false,
  );
  final localFiles = AdbServices(
    () => throw StateError('没有文件执行操作'),
    (_) async => throw StateError('没有文件连接需要解析'),
    () {},
  );
  addTearDown(localFiles.close);
  final files = await FileResources.open(
    fileScopeId: 'test-file-scope',
    fileScopeKey: 'test-file-owner',
    documentPlatform: FileDocumentPlatform(
      files: () async => LocalFiles(_RecoveryFiles()),
      request: (_, _) async => throw StateError('没有平台文档请求'),
      isDisposed: () => false,
    ),
    localFiles: localFiles,
    dataDirectory: directory.path,
    records: resources.records,
    requireConnection: (_) => throw StateError('没有文件连接'),
    request: () => throw StateError('没有缩略图任务'),
    isDisposed: () => false,
    isStateUnverified: () => false,
    diagnostics: DiagnosticReporter(null),
    emit: (_) {},
    attachCatalogEvents: events.attachFileEvents,
    onSharingOpened: (_) {},
  );
  addTearDown(files.close);
  final media = MediaPlayback(
    captures: () => throw StateError('退出不应创建捕获能力'),
    readCapturedAudio: () async => throw StateError('退出不应读取捕获音源'),
    readSnapshot: () async => throw StateError('退出不应恢复业务状态'),
    readSettings: settings.read,
    platform: (_, _) async => throw StateError('退出不应创建平台播放器'),
    emit: (_) {},
    isDisposed: () => false,
    requireVerifiedState: () {},
    dataDirectory: directory.path,
    capture: () => throw StateError('退出不应创建捕获适配器'),
  );
  return AppLifecycle(
    closeHost: closeHost,
    connections: resources,
    readCaptures: () => null,
    files: files,
    events: events,
    stateRecovery: StateRecovery(
      read: (_) async => throw StateError('退出不应发起恢复'),
      emit: (_) {},
      isDisposed: () => false,
    ),
    preferences: settings,
    platformEvents: null,
    readVisible: null,
    background: BackgroundPolicy(
      platform: null,
      audioPolicy: (_) async {},
      onChanged: (_) {},
      onFailure: (_) {},
    ),
    media: media,
    diagnostics: DiagnosticReporter(null),
  );
}

class _RecoveryFiles implements NativeLocalFilesApi {
  @override
  Future<String> openScope(
    String key,
    List<Uint8List> roots,
    int timeoutMs,
  ) async => 'recovered-documents';
  @override
  Future<void> closeScope(String id, int timeoutMs) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('空恢复不应复制文件：${invocation.memberName}');
}

void _expectUnused(
  DeviceResources resources, {
  bool devicesUsed = false,
  bool reconnectUsed = false,
}) {
  final disposed = throwsA(
    isA<RequestFailure>().having((error) => error.code, 'code', 'disposed'),
  );
  if (!devicesUsed) expect(() => resources.devices, disposed);
  expect(() => resources.setup, disposed);
  if (!reconnectUsed) expect(() => resources.reconnections, disposed);
  expect(() => resources.companion, disposed);
  expect(() => resources.observations, disposed);
  expect(() => resources.apps, disposed);
  expect(() => resources.operations, disposed);
  expect(() => resources.identity, disposed);
}

Future<DeviceResources> _resources({
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? authorizeUsb,
  Future<void> Function(Map<String, dynamic>)? cancelUsb,
  Future<void> Function(Map<String, dynamic>)? releaseUsb,
  Future<void> Function(String, DeviceConnection, bool)? stopWork,
  int Function()? readEventSequence,
  bool Function()? readBackgroundKeepAlive,
}) async {
  final temporary = await Directory.systemTemp.createTemp('device-resources-');
  final directory = Directory(await temporary.resolveSymbolicLinks());
  addTearDown(() => directory.delete(recursive: true));
  final resources = await DeviceResources.open(
    directory: directory,
    identities: _Identities(),
    recoverConnections: () async {},
    drainConnections: () async {},
    clientForIdentity: (_) => throw StateError('此流程不应创建 SDK 客户端'),
    releaseIdentityClient: (_) async => throw StateError('没有候选客户端需要释放'),
    displays: DisplayRecovery(timeout: const Duration(seconds: 1)),
    companionBytes: Uint8List(0),
    burstMode: () => false,
    policy: const ConnectionPolicy(),
    diagnostics: null,
    isDisposed: () => false,
    isStateUnverified: () => false,
    readEventSequence:
        readEventSequence ?? () => throw StateError('不应通过空操作读取事件水位'),
    readBackgroundKeepAlive:
        readBackgroundKeepAlive ?? () => throw StateError('不应通过空操作读取重连偏好'),
    readSessions: () => throw StateError('重连不应读取捕获会话'),
    readAudio: () => throw StateError('重连不应读取设备音源'),
    serverQueries: () => throw StateError('不应创建捕获查询器'),
    authorizeUsb: authorizeUsb,
    cancelUsb: cancelUsb,
    releaseUsb: releaseUsb,
    emit: (_) => throw StateError('此流程不应发布事件'),
    publish: (_, _, _) => throw StateError('此流程不应发布事件'),
    stopWork: stopWork ?? (_, _, _) async => throw StateError('没有设备活动需要停止'),
  );
  addTearDown(resources.close);
  return resources;
}

class _Identities implements AdbIdentities {
  @override
  Future<void> prepareIdentity(String path) async {}
  @override
  Future<AdbIdentityInfo?> inspectIdentity(String path) async =>
      const AdbIdentityInfo(
        fingerprint:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        fingerprintAlgorithm: 'sha256',
        fingerprintInput: 'adb-public-key',
        bits: 2048,
        exponent: 65537,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('没有身份修改：${invocation.memberName}');
}

class _UnusedClient implements AdbClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('未使用的连接不应查询或执行原生命令：${invocation.memberName}');
}
