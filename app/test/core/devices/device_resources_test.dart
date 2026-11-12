import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/display_recovery.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_connection_service.dart';
import 'package:scrcpy_connect/core/devices/device_discovery.dart';
import 'package:scrcpy_connect/core/devices/device_resources.dart';
import 'package:scrcpy_connect/core/devices/models/connection_change.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/files/file_document_platform.dart';
import 'package:scrcpy_connect/core/files/file_resources.dart';
import 'package:scrcpy_connect/core/lifecycle/app_lifecycle.dart';
import 'package:scrcpy_connect/core/lifecycle/app_lifetime.dart';
import 'package:scrcpy_connect/core/media/media_playback.dart';
import 'package:scrcpy_connect/core/platform/background_policy.dart';
import 'package:scrcpy_connect/core/devices/models/device_metadata.dart';
import 'package:scrcpy_connect/core/recovery/state_recovery.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/app_settings.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

void main() {
  test('元数据导入不创建配对、发现、重连或原生查询执行者', () async {
    final changes = <DeviceListChanged>[];
    final resources = await _resources(onDevicesChanged: changes.add);
    final metadata = resources.metadata;
    final document = DeviceMetadata.parse({
      'format': 'scrcpy-connect-metadata',
      'version': 1,
      'devices': [
        {
          'name': 'Imported phone',
          'address': '192.0.2.1',
          'port': 5555,
          'transport': 'tcp',
        },
      ],
    });
    final receipt = await metadata.import(
      document,
      importGlobalPreferences: false,
      apply: (commit) => commit(),
    );
    expect(changes.single.devices.single.id, receipt.receipt.deviceIds.single);
    await resources.close();
    _expectUnused(resources, devicesUsed: true);
    expect(resources.metadata, same(metadata));
  });

  test('空记录、无关事件和退出不创建未使用的设备执行所有者', () async {
    final resources = await _resources();
    expect(resources.records.current.devices, isEmpty);
    expect(
      (await resources.identities.selectForDevice()).fingerprint,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    resources.handleEvent({'type': 'settings.changed'});
    resources.handleRecovery(const RecoveryStarted());
    resources.handleRecovery(const RecoveryFailed('unverified'));
    resources.handleRecovery(
      RecoveryCompleted(RuntimeSnapshot(sequence: 0, settings: Preferences())),
    );
    resources.handleEvent({
      'type': 'devices.changed',
      'data': DeviceListChanged([]),
    });
    await resources.prepareChange(
      const ConnectionChange(.cancel, attemptId: 'unused'),
    );
    await resources.forgetObservation('unused');
    await resources.stopConnections();
    await resources.stopAdmission();
    await resources.close();
    await resources.close();
    resources.handleEvent({
      'type': 'devices.changed',
      'data': DeviceListChanged([]),
    });
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
      'data': DeviceListChanged([]),
    });
    resources.handleRecovery(const RecoveryStarted());
    resources.handleRecovery(
      RecoveryCompleted(
        RuntimeSnapshot(
          sequence: 2,
          devices: [],
          settings: Preferences(backgroundKeepAlive: false),
        ),
      ),
    );
    await resources.close();
    expect(sequenceReads, 1);
    expect(settingsReads, 1);
    _expectUnused(resources, devicesUsed: true, reconnectUsed: true);
  });

  test('离线应用查询不创建清单部署或伴生所有者', () async {
    final resources = await _resources();
    final apps = resources.apps;
    await expectLater(
      apps.readInstalledApps('00000000-0000-0000-0000-000000000001'),
      throwsA(
        isA<RequestFailure>().having((e) => e.code, 'code', 'disconnected'),
      ),
    );
    await resources.close();
    expect(resources.apps, same(apps));
    expect(() => resources.serverQueries, throwsA(isA<RequestFailure>()));
    expect(() => resources.companion, throwsA(isA<RequestFailure>()));
    expect(() => resources.observations, throwsA(isA<RequestFailure>()));
    expect(() => resources.setup, throwsA(isA<RequestFailure>()));
  });

  test('能力评估和空唤醒不创建配对、清单部署或伴生观察', () async {
    final resources = await _resources();
    final operations = resources.operations;
    const id = '00000000-0000-0000-0000-000000000001';
    await expectLater(
      operations.readCapabilities(id),
      throwsA(
        isA<RequestFailure>().having((e) => e.code, 'code', 'device_not_found'),
      ),
    );
    await expectLater(
      operations.wakeDevice(id),
      throwsA(
        isA<RequestFailure>().having((e) => e.code, 'code', 'disconnected'),
      ),
    );
    await resources.close();
    expect(resources.operations, same(operations));
    _expectUnused(resources, devicesUsed: true, operationsUsed: true);
  });

  test('延迟创建的配对流程直接遵守当前恢复屏障，不依赖创建前收到事件', () async {
    final resources = await _resources();
    final discovery = DeviceDiscovery();
    await discovery.close();
    var unverified = true;
    final waiting = Completer<void>();
    final resume = Completer<void>();
    final setup = DeviceConnectionService(
      devices: resources.devices,
      discovery: discovery,
      clientForIdentity: (_) => _UnusedClient(),
      releaseIdentityClient: (_) async {},
      policy: const ConnectionPolicy(),
      emit: (_) {},
      isStateUnverified: () => unverified,
      delay: (_) {
        if (!waiting.isCompleted) waiting.complete();
        return resume.future;
      },
    );
    addTearDown(setup.dispose);
    final handle = await setup.beginQrPairing(attemptId: 'late-setup');
    await waiting.future;
    var settled = false;
    final blocked = expectLater(
      handle.result,
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'disposed')),
    ).then((_) => settled = true);
    expect(settled, isFalse);
    unverified = false;
    resume.complete();
    await blocked;
  });

  test('设备模块持有失败的清单部署，关闭重试原上传与清理责任', () async {
    final resources = await _resources(
      scrcpyServerBytes: Uint8List.fromList([1]),
    );
    final api = _QueryUpload();
    final client = _QueryClient(api);
    addTearDown(() async {
      api.allowClose = true;
      await resources.close();
      await client.services.close();
    });
    final queries = resources.serverQueries;
    final connection = DeviceConnection(
      client: client,
      device: const AdbDevice(
        id: 'query-connection',
        serial: 'phone',
        state: 'device',
      ),
    );
    final failed = throwsA(
      isA<RequestFailure>().having(
        (e) => e.code,
        'code',
        'apps_cleanup_unconfirmed',
      ),
    );
    await expectLater(
      queries.installedApps(connection, AdbCancellation()),
      failed,
    );
    await expectLater(resources.close(), failed);
    expect(resources.serverQueries, same(queries));
    expect(client.removed, isEmpty);
    expect(api.uploads, 1);
    api.allowClose = true;
    await resources.close();
    expect(client.removed, hasLength(1));
    expect(api.closed.every((id) => id == 'original-upload'), isTrue);
    expect(api.uploads, 1);
    final closed = api.closed.length;
    await resources.close();
    expect(api.closed, hasLength(closed));
    expect(() => resources.companion, throwsA(isA<RequestFailure>()));
  });

  test('停止连接等待原 USB 租约释放，停止后仍允许新的手动流程', () async {
    final ids = ['first', 'second'];
    final authorizing = {for (final id in ids) id: Completer<void>()};
    final authorized = {
      for (final id in ids) id: Completer<Map<String, dynamic>>(),
    };
    final releasing = {for (final id in ids) id: Completer<void>()};
    final released = {for (final id in ids) id: Completer<void>()};
    final cancellations = <String>[];
    final leases = <String>[];
    final resources = await _resources(
      authorizeUsb: (params) {
        final id = params['attemptId'] as String;
        authorizing[id]!.complete();
        return authorized[id]!.future;
      },
      cancelUsb: (params) async =>
          cancellations.add(params['attemptId'] as String),
      releaseUsb: (params) async {
        final id = params['usbLeaseId'] as String;
        leases.add(id);
        releasing[id]!.complete();
        await released[id]!.future;
      },
      onDevicesChanged: (_) {},
    );
    addTearDown(() {
      for (final id in ids) {
        if (!authorized[id]!.isCompleted) authorized[id]!.complete({});
        if (!released[id]!.isCompleted) released[id]!.complete();
      }
    });
    final setup = resources.setup;
    for (final id in ids) {
      final request = expectLater(
        setup.connectUsb(attemptId: id),
        throwsA(
          isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await authorizing[id]!.future;
      var finished = false;
      final stopping = resources.stopConnections().then((_) => finished = true);
      expect(cancellations, contains(id));
      authorized[id]!.complete({'usbLeaseId': id, 'fd': 7});
      await releasing[id]!.future;
      expect(finished, isFalse);
      released[id]!.complete();
      await request;
      await stopping;
      expect(resources.setup, same(setup));
    }
    expect(leases, ids);
    await resources.close();
    expect(() => resources.companion, throwsA(isA<RequestFailure>()));
    expect(() => resources.observations, throwsA(isA<RequestFailure>()));
    expect(() => resources.serverQueries, throwsA(isA<RequestFailure>()));
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
    metadata: resources.metadata,
    onChanged: (_) {},
  );
  final events = RuntimeEvents(
    acceptState: ({required sequence, required telemetry}) => true,
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
    lifetime: AppLifetime(),
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
      onEvent: (_) {},
      isDisposed: () => false,
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
  bool operationsUsed = false,
}) {
  final disposed = throwsA(
    isA<RequestFailure>().having((error) => error.code, 'code', 'disposed'),
  );
  if (!devicesUsed) expect(() => resources.devices, disposed);
  expect(() => resources.setup, disposed);
  if (!reconnectUsed) expect(() => resources.reconnections, disposed);
  expect(() => resources.companion, disposed);
  expect(() => resources.serverQueries, disposed);
  expect(() => resources.observations, disposed);
  expect(() => resources.apps, disposed);
  if (!operationsUsed) expect(() => resources.operations, disposed);
  expect(() => resources.identity, disposed);
}

Future<DeviceResources> _resources({
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? authorizeUsb,
  Future<void> Function(Map<String, dynamic>)? cancelUsb,
  Future<void> Function(Map<String, dynamic>)? releaseUsb,
  Future<void> Function(String, DeviceConnection, bool)? stopWork,
  int Function()? readEventSequence,
  bool Function()? readBackgroundKeepAlive,
  Uint8List? scrcpyServerBytes,
  void Function(DeviceListChanged)? onDevicesChanged,
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
    scrcpyServerBytes: scrcpyServerBytes ?? Uint8List(0),
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
    authorizeUsb: authorizeUsb,
    cancelUsb: cancelUsb,
    releaseUsb: releaseUsb,
    emit: (_) => throw StateError('此流程不应发布事件'),
    publish: (_, _, _) => throw StateError('此流程不应发布事件'),
    onDevicesChanged:
        onDevicesChanged ?? (_) => throw StateError('此流程不应修改设备投影'),
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

final class _QueryUpload implements NativeAdbApi {
  bool allowClose = false;
  var uploads = 0;
  final closed = <String>[];
  @override
  Future<String> sync(String id, AdbSyncRequest request, int timeoutMs) async {
    expect(id, 'query-connection');
    uploads++;
    return 'original-upload';
  }

  @override
  Future<NativeAdbEvent?> next(String operationId) async => NativeAdbEvent(
    kind: 'done',
    bytes: Uint8List(0),
    done: true,
    transferred: 1,
  );
  @override
  Future<void> write(String id, AdbServiceInput input) async {}
  @override
  Future<void> cancel(String operationId) async {
    closed.add(operationId);
    if (!allowClose) throw StateError('upload close unconfirmed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('清单查询不应调用其他 SDK 能力：${invocation.memberName}');
}

final class _QueryClient implements AdbClient {
  _QueryClient(_QueryUpload api) {
    services = AdbServices(() => api, (device) async => device, () {});
  }
  @override
  late final AdbServices services;
  final removed = <String>[];
  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) async* {
    expect(device.id, 'query-connection');
    expect(command, startsWith('rm -f -- '));
    removed.add(command);
    final marker = RegExp(r'__INTEROP_QUERY_REMOVE_[0-9a-f-]+__:')
        .firstMatch(command)![0]!;
    yield AdbShellEvent(
      .stdout,
      Uint8List.fromList(utf8.encode('\n${marker}0\n')),
    );
    yield AdbShellEvent(.exit, Uint8List(0), exitCode: 0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('清单查询不应创建其他客户端能力：${invocation.memberName}');
}
