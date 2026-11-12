import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/bootstrap/app_bootstrap.dart';
import 'package:scrcpy_connect/core/activities/activity_management_provider.dart';
import 'package:scrcpy_connect/core/control/app_launch_journal.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_endpoint.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/devices/models/device_metadata.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/app_snapshot_notifier.dart';
import 'package:scrcpy_connect/core/platform/bundled_server_files.dart';
import 'package:scrcpy_connect/core/platform/native_host.dart';
import 'package:scrcpy_connect/core/platform/native_host_dependencies.dart';
import 'package:scrcpy_connect/core/recovery/recovery_actions_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/core/settings/metadata_management.dart';
import 'package:scrcpy_connect/router/route_resource_resolver_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('实际元数据导入由设备模块交付投影，全局偏好与重复导入保持同一账本', () async {
    final fixture = await _Assembly.open();
    final bootstrap = await AppBootstrap.initialize(
      dataDirectory: fixture.directory.path,
    );
    addTearDown(bootstrap.dispose);
    final container = ProviderContainer(overrides: bootstrap.overrides);
    addTearDown(container.dispose);
    container.read(appSnapshotProvider);
    final source = container.read(metadataManagementProvider);
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
      'settings': {'appearance': 'dark'},
    });
    final preview = await source.previewImport(document);
    final changed = container
        .read(runtimeEventsProvider)
        .firstWhere((event) => event['data'] is DeviceListChanged);
    final imported = await source.importMetadata(
      preview,
      importGlobalPreferences: true,
    );
    final receipt = imported.records.receipt.deviceIds.single;
    final projection = (await changed)['data'] as DeviceListChanged;
    expect(projection.devices.single.id, receipt);
    expect(
      projection.devices.single.status,
      DeviceConnectionStatus.unauthorized,
    );
    expect(container.read(appSnapshotProvider).devices.single.id, receipt);
    expect(
      container.read(appSnapshotProvider).settings.appearance,
      Appearance.dark,
    );
    final repeated = await source.importMetadata(
      await source.previewImport(document),
      importGlobalPreferences: true,
    );
    expect(repeated.records.alreadyImported, isTrue);
    expect(repeated.preferencesStatus, ImportPreferencesStatus.matchesCurrent);
    expect(
      (await container.read(deviceReaderProvider).readDevices()).single.id,
      receipt,
    );
    await bootstrap.dispose();
    expect(fixture.api.closed, ['files:files-1', 'admission:scope-1']);
  });

  test('实际启动未使用控制捕获时，仍恢复持久化待核对记录并能明确关闭', () async {
    final fixture = await _Assembly.open();
    const operation = '00000000-0000-0000-0000-000000000001';
    final journal = await AppLaunchJournal.open(directory: fixture.directory);
    await journal.begin(
      operationId: operation,
      sessionId: operation,
      deviceId: 'phone',
      packageName: 'com.example.app',
    );
    final bootstrap = await AppBootstrap.initialize(
      dataDirectory: fixture.directory.path,
    );
    addTearDown(bootstrap.dispose);
    final container = ProviderContainer(overrides: bootstrap.overrides);
    addTearDown(container.dispose);
    final activities = container.read(activityManagementProvider);
    final initial = await activities.readActivities();
    expect(initial.pendingApplications.single.sessionId, operation);
    expect(initial.pendingApplications.single.recordOnly, isTrue);
    expect(initial.pendingApplications.single.name, 'com.example.app');
    expect(
      (await activities.readActivities(deviceId: 'another-phone')).activities,
      isEmpty,
    );
    container.read(appSnapshotProvider);
    await container.read(reconcileStateProvider)();
    final recovered = container
        .read(appSnapshotProvider)
        .reconciledSnapshot!
        .sessions
        .single;
    expect(recovered.session.sessionId, operation);
    expect(recovered.session.recordOnly, isTrue);
    expect(recovered.live, isFalse);
    expect(recovered.output, isNull);
    expect(recovered.keepAwake!.keepActiveLeaseActive, isFalse);
    await activities.stopActivity(initial.activities.single.target);
    expect((await activities.readActivities()).pendingApplications, isEmpty);
    await container.read(reconcileStateProvider)();
    expect(
      container.read(appSnapshotProvider).reconciledSnapshot!.sessions,
      isEmpty,
    );
    await bootstrap.dispose();
    expect(fixture.api.closed, ['files:files-1', 'admission:scope-1']);
  });

  test('实际装配完成恢复与状态交付，空设备不调用捕获，模块关闭后才释放宿主', () async {
    final fixture = await _Assembly.open();
    final bootstrap = await AppBootstrap.initialize(
      dataDirectory: fixture.directory.path,
    );
    addTearDown(bootstrap.dispose);
    final container = ProviderContainer(overrides: bootstrap.overrides);
    addTearDown(container.dispose);
    expect(await container.read(deviceReaderProvider).readDevices(), isEmpty);
    await expectLater(
      container
          .read(routeResourceResolverProvider)
          .device('00000000-0000-0000-0000-000000000001'),
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'not_found')),
    );
    container.read(appSnapshotProvider);
    await container.read(reconcileStateProvider)();
    await container.pump();
    final state = container.read(appSnapshotProvider);
    expect(state.devices, isEmpty);
    expect(state.loading, isFalse);
    expect(state.reconciliationPending, isFalse);
    expect(state.reconciledSnapshot, isNotNull);
    expect(state.reconciledSnapshot!.sessions, isEmpty);
    expect(state.reconciledSnapshot!.sources, isEmpty);
    final activities = await container
        .read(activityManagementProvider)
        .readActivities();
    expect(activities.activities, isEmpty);
    final preferencesChanged = container
        .read(runtimeEventsProvider)
        .firstWhere((event) => event['type'] == 'settings.changed');
    final preferences = await container
        .read(settingsManagementProvider)
        .update(PreferenceChanges(appearance: .dark));
    expect((await preferencesChanged)['data'], same(preferences));
    expect(container.read(appSnapshotProvider).settings, same(preferences));
    final changed = container
        .read(runtimeEventsProvider)
        .firstWhere((event) => event['data'] is DeviceListChanged);
    final saved = await container
        .read(deviceManagementProvider)
        .addDevice(const DeviceEndpoint(address: '192.0.2.1', port: 5555));
    final event = await changed;
    expect((event['data'] as DeviceListChanged).devices.single.id, saved.id);
    // 实际发布链先提交状态，页面收到同一事件时无需重新查询。
    expect(container.read(appSnapshotProvider).devices.single, saved);
    await container.read(deviceManagementProvider).forgetDevice(saved.id);
    await container.pump();
    expect(container.read(appSnapshotProvider).devices, isEmpty);
    await bootstrap.dispose();
    expect(fixture.api.closed, ['files:files-1', 'admission:scope-1']);
    expect(fixture.api.scope, isNull);
    expect(fixture.api.attachments, 1);
  });

  test('实际装配中途失败等待原宿主清理，失败保留责任且后继启动先重试', () async {
    final fixture = await _Assembly.open();
    final invalid = File('${fixture.directory.path}/app-opens.json');
    await invalid.writeAsString('{invalid journal');
    fixture.api.allowFileClose = false;
    fixture.api.closeGate = Completer<void>();
    final originalScope = fixture.api.scope;
    var settled = false;
    final failed = expectLater(
      AppBootstrap.initialize(dataDirectory: fixture.directory.path),
      throwsA(
        isA<RequestFailure>().having(
          (e) => e.code,
          'code',
          'app_open_storage_invalid',
        ),
      ),
    ).then((_) => settled = true);
    await fixture.api.fileCloseStarted.future;
    expect(settled, isFalse);
    fixture.api.closeGate!.complete();
    await failed;
    expect(fixture.api.scope, same(originalScope));
    expect(fixture.api.closed, ['files:files-1']);
    await expectLater(
      AppBootstrap.initialize(dataDirectory: fixture.directory.path),
      throwsA(same(fixture.api.closeFailure)),
    );
    expect(fixture.api.attachments, 1);
    expect(fixture.api.closed, ['files:files-1', 'files:files-1']);
    fixture.api.allowFileClose = true;
    await fixture.host.close();
    expect(fixture.api.closed, [
      'files:files-1',
      'files:files-1',
      'files:files-1',
      'admission:scope-1',
    ]);
    await invalid.delete();
    // 复用宿主公开接管入口，只替换 SDK；后继仍走完整 bootstrap/装配/激活。
    final successor = _Execution();
    final host = await NativeHost.attach(
      dataDirectory: fixture.directory.path,
      dependencies: successor,
    );
    addTearDown(host.close);
    final bootstrap = await AppBootstrap.initialize(
      dataDirectory: fixture.directory.path,
    );
    addTearDown(bootstrap.dispose);
    await bootstrap.dispose();
    expect(successor.api.attachments, 1);
    expect(successor.api.closed, ['files:files-1', 'admission:scope-1']);
    expect(fixture.api.closed, hasLength(4));
  });

  test('实际关闭开始即撤销设置准入，释放失败仍保持关闭且重试原宿主', () async {
    final fixture = await _Assembly.open();
    final bootstrap = await AppBootstrap.initialize(
      dataDirectory: fixture.directory.path,
    );
    addTearDown(bootstrap.dispose);
    final container = ProviderContainer(overrides: bootstrap.overrides);
    addTearDown(container.dispose);
    final settings = container.read(settingsManagementProvider);
    final initial = await settings.read();
    fixture.api.allowFileClose = false;
    final gate = fixture.api.closeGate = Completer<void>();
    final originalScope = fixture.api.scope;
    final closing = expectLater(
      bootstrap.dispose(),
      throwsA(same(fixture.api.closeFailure)),
    );
    await fixture.api.fileCloseStarted.future;
    final disposed = throwsA(
      isA<RequestFailure>().having((e) => e.code, 'code', 'disposed'),
    );
    await expectLater(settings.read(), disposed);
    await expectLater(
      settings.update(PreferenceChanges(appearance: .dark)),
      disposed,
    );
    expect(fixture.host.preferences.current.values, same(initial));
    expect(fixture.api.scope, same(originalScope));
    gate.complete();
    await closing;
    await expectLater(settings.read(), disposed);
    expect(fixture.api.scope, same(originalScope));
    fixture.api.allowFileClose = true;
    await bootstrap.dispose();
    expect(fixture.api.closed, [
      'files:files-1',
      'files:files-1',
      'admission:scope-1',
    ]);
    expect(fixture.api.attachments, 1);
  });

  test('完整启动后的目录配置失败仍通过真实生命周期关闭所有者', () async {
    final fixture = await _Assembly.open();
    final original = StateError('outgoing directory unavailable');
    await expectLater(
      bootstrapApp(
        createSession: () =>
            AppBootstrap.initialize(dataDirectory: fixture.directory.path),
        prepareOutgoingDirectory: () async => throw original,
      ),
      throwsA(same(original)),
    );
    expect(fixture.api.closed, ['files:files-1', 'admission:scope-1']);
    expect(fixture.api.scope, isNull);
  });
}

final class _Assembly {
  _Assembly(this.directory, this.host, this.api);
  final Directory directory;
  final NativeHost host;
  final _NativeExecution api;

  static Future<_Assembly> open() async {
    final temporary = await Directory.systemTemp.createTemp('app-assembly-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    final execution = _Execution();
    final host = await NativeHost.attach(
      dataDirectory: directory.path,
      dependencies: execution,
    );
    addTearDown(() async {
      execution.api.allowFileClose = true;
      if (execution.api.closeGate case final gate? when !gate.isCompleted) {
        gate.complete();
      }
      await host.close();
      await temporary.delete(recursive: true);
    });
    return _Assembly(directory, host, execution.api);
  }
}

/// 只替换公开 SDK 执行能力；应用记录、模块、事件及关闭均使用真实实现。
final class _Execution extends NativeHostDependencies {
  final api = _NativeExecution();
  @override
  bool get desktop => false;
  @override
  Future<NativeAdbApi> bindings() async => api;
  @override
  Future<BundledServerFiles> assets(Directory directory) async =>
      BundledServerFiles({'scrcpy': Uint8List(0), 'companion': Uint8List(0)});
  @override
  Future<ScrcpyClient> createScrcpy(Uint8List bytes) async =>
      ScrcpyClient(_UnusedCapture());
}

final class _UnusedCapture implements NativeScrcpyApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('空装配不应启动捕获：${invocation.memberName}');
}

final class _NativeExecution
    implements
        NativeAdbApi,
        NativeAdbAdmissionApi,
        NativeAdbScopedFileScopeApi,
        NativeAdbFileApi,
        NativeAdbHandshakeApi,
        AdbIdentities {
  AdbAdmissionScopeInfo? scope;
  int attachments = 0;
  bool allowFileClose = true;
  Completer<void>? closeGate;
  final fileCloseStarted = Completer<void>();
  final closed = <String>[];
  final closeFailure = StateError('file scope release unconfirmed');

  @override
  Future<AdbAdmissionScopeInfo?> inspectAdmissionScope(String key) async =>
      scope;
  @override
  Future<AdbAdmissionScopeInfo> attachAdmissionScope(
    String key, {
    String? expectedScopeId,
    int timeoutMs = 7000,
  }) async {
    expect(expectedScopeId, isNull);
    return scope = AdbAdmissionScopeInfo(
      scopeKey: key,
      scopeId: 'scope-${++attachments}',
      accepting: true,
    );
  }

  @override
  Future<void> closeAdmissionScope(String id, {int timeoutMs = 7000}) async {
    expect(id, scope?.scopeId);
    closed.add('admission:$id');
    scope = null;
  }

  @override
  Future<String> fileScopeAttachScoped(String key, String scopeId) async {
    expect(scopeId, scope?.scopeId);
    return 'files-$attachments';
  }

  @override
  Future<void> fileScopeClose(String id) async {
    closed.add('files:$id');
    if (!fileCloseStarted.isCompleted) fileCloseStarted.complete();
    await closeGate?.future;
    if (!allowFileClose) throw closeFailure;
  }

  @override
  Future<void> initializeFileHelpers(List<AdbFileHelper> helpers) async {}
  @override
  Future<List<AdbDevice>> devices() async => [];
  @override
  Future<void> prepareIdentity(String path) async {
    if (!await File(path).exists()) {
      await File(path).writeAsString('SDK identity fixture');
    }
  }

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
      throw StateError('空装配不应执行 SDK 操作：${invocation.memberName}');
}
