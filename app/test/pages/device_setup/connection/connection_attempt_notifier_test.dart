import 'dart:async';

import 'package:adb/adb.dart' show AdbCancellation;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/identity/models/setup_identity.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/recovery/recovery_actions_provider.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/connection_attempt_notifier.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/models/connection_attempt_request.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/models/connection_attempt_state.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/connection_form_page.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/widgets/connection_address_fields.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/widgets/connection_attempt_status.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/widgets/connection_mode_selector.dart';
import 'package:scrcpy_connect/styles/theme.dart';

const _endpoint = DeviceEndpoint(address: 'phone.local', port: 5555);
const _connect = ConnectionAttemptRequest.connect(endpoint: _endpoint);
const _pair = ConnectionAttemptRequest.pair(
  address: 'phone.local',
  port: 45678,
  code: '123456',
  deviceId: 'device',
);

void main() {
  late _Setup setup;
  late _Management management;
  late _Connections connections;
  late _Reconcile probe;
  late Future<void> Function() reconcile;
  late ProviderContainer container;
  final scope = Object();
  final provider = connectionAttemptProvider(scope: scope);
  late ConnectionAttemptNotifier actions;
  late void Function() leave;
  final session = AppSession(initialize: false);
  overrides() => [
    appSessionProvider.overrideWithValue(session),
    deviceSetupProvider.overrideWithValue(setup),
    deviceManagementProvider.overrideWithValue(management),
    deviceReaderProvider.overrideWithValue(management),
    deviceConnectionsProvider.overrideWithValue(connections),
    reconcileStateProvider.overrideWithValue(reconcile),
  ];
  setUp(() {
    setup = _Setup();
    management = _Management();
    connections = _Connections();
    probe = _Reconcile();
    reconcile = probe.run;
    container = ProviderContainer(overrides: overrides());
    final subscription = container.listen(provider, (_, _) {});
    leave = subscription.close;
    actions = container.read(provider.notifier);
  });
  tearDown(() => container.dispose());

  test('保存记录期间取消，迟到记录不接续连接；回收失败只重试原尝试', () async {
    final submission = actions.submit(_connect);
    await actions.submit(_connect);
    expect(management.saves, hasLength(1));
    final cancel = actions.cancel();
    expect(management.saves.single.stop!.isCancelled, isTrue);
    management.cancellations.single.result.completeError(
      StateError('still owned'),
    );
    expect(await cancel, isFalse);
    expect(
      container.read(provider).phase,
      ConnectionAttemptPhase.cleanupRequired,
    );
    management.saves.single.result.complete(const DeviceSnapshot(id: 'saved'));
    await submission;
    expect(connections.calls, isEmpty);
    await actions.submit(_connect);
    expect(management.saves, hasLength(1));
    final retry = actions.cancel();
    expect(management.cancellations.last.id, management.cancellations.first.id);
    management.cancellations.last.result.complete();
    expect(await retry, isTrue);
    expect(container.read(provider).canSubmit, isTrue);
  });

  test('连接失败保留已保存记录，明确重试沿用同一记录及原传输方式', () async {
    final submission = actions.submit(_connect);
    management.saves.single.result.complete(const DeviceSnapshot(id: 'saved'));
    await container.pump();
    expect(connections.calls.single.id, 'saved');
    connections.calls.single.result.completeError(
      const RequestFailure('timeout', 'connection timeout'),
    );
    await submission;
    expect(container.read(provider).deviceId, 'saved');
    expect(container.read(provider).failure!.code, 'timeout');
    expect(container.read(provider).canSubmit, isTrue);
    final retry = actions.submit(
      const ConnectionAttemptRequest.connect(
        endpoint: DeviceEndpoint(
          address: 'phone.local',
          port: 45679,
          transport: .tls,
        ),
        deviceId: 'saved',
      ),
    );
    expect(management.saves.last.id, 'saved');
    expect(management.saves.last.endpoint.transport, DeviceTransport.tls);
    management.saves.last.result.complete(const DeviceSnapshot(id: 'saved'));
    await container.pump();
    management.devices = [
      const DeviceSnapshot(id: 'saved', status: .connected),
    ];
    connections.calls.last.result.complete(_connected('saved'));
    await retry;
    expect(container.read(provider).connectedDeviceId, 'saved');
  });

  test('换源与离页撤销原执行，迟到连接回执不进入新页面', () async {
    final submission = actions.submit(_connect);
    management.saves.single.result.complete(const DeviceSnapshot(id: 'saved'));
    await container.pump();
    final previousManagement = management;
    final previousConnections = connections;
    setup = _Setup();
    management = _Management();
    connections = _Connections();
    container.updateOverrides(overrides());
    await container.pump();
    expect(previousConnections.calls.single.stop!.isCancelled, isTrue);
    expect(
      previousManagement.cancellations.single.id,
      previousConnections.calls.single.attempt,
    );
    previousManagement.cancellations.single.result.complete();
    previousConnections.calls.single.result.complete(_connected('saved'));
    await submission;
    expect(container.read(provider).phase, ConnectionAttemptPhase.idle);
    expect(container.read(provider).connectedDeviceId, isNull);
    final next = actions.submit(_pair);
    leave();
    await container.pump();
    expect(management.cancellations.single.id, setup.calls.single.id);
    management.cancellations.single.result.complete();
    setup.calls.single.result.complete(_paired());
    await next;
  });

  test('配对事实与连接未知分别保存，核对不重放请求且保留异常反馈', () async {
    final submission = actions.submit(_pair);
    setup.calls.single.result.complete(
      _paired(
        issue: const SetupIssue('result_unknown', 'awaiting confirmation'),
      ),
    );
    await submission;
    expect(container.read(provider).pairing!.recorded, isTrue);
    expect(container.read(provider).canSubmit, isFalse);
    final check = actions.recheck();
    await actions.recheck();
    expect(probe.calls, hasLength(1));
    expect(container.read(provider).checking, isTrue);
    expect(container.read(provider).failure!.message, 'awaiting confirmation');
    await actions.submit(_pair);
    expect(setup.calls, hasLength(1));
    management.devices = [
      const DeviceSnapshot(id: 'device', status: .connected),
    ];
    probe.calls.single.complete();
    await check;
    expect(container.read(provider).connectedDeviceId, 'device');
    expect(
      container.read(provider).phase,
      ConnectionAttemptPhase.cleanupRequired,
    );
    final cancel = actions.cancel();
    management.cancellations.single.result.complete();
    expect(await cancel, isTrue);
    expect(container.read(provider).pairing!.recorded, isTrue);
    expect(container.read(provider).notice, contains('配对授权已保留'));
  });

  test('核对换源或取消后忽略旧结果，核对状态能够结束', () async {
    final submission = actions.submit(_pair);
    setup.calls.single.result.complete(
      _paired(
        issue: const SetupIssue('result_unknown', 'awaiting confirmation'),
      ),
    );
    await submission;
    final check = actions.recheck();
    final oldProbe = probe;
    probe = _Reconcile();
    reconcile = probe.run;
    container.updateOverrides(overrides());
    await container.pump();
    management.devices = [
      const DeviceSnapshot(id: 'device', status: .connected),
    ];
    oldProbe.calls.single.complete();
    await check;
    expect(container.read(provider).checking, isFalse);
    expect(container.read(provider).connectedDeviceId, isNull);
    final nextCheck = actions.recheck();
    final cancel = actions.cancel();
    probe.calls.single.complete();
    management.cancellations.single.result.complete();
    await nextCheck;
    expect(await cancel, isTrue);
    expect(container.read(provider).connectedDeviceId, isNull);
  });

  test('配置回执不属于原设备时，保留原目标及清理责任，禁止重复提交', () async {
    const request = ConnectionAttemptRequest.connect(
      endpoint: _endpoint,
      deviceId: 'device',
      configure: true,
    );
    final submission = actions.submit(request);
    expect(connections.calls.single.configuring, isTrue);
    connections.calls.single.result.complete(_connected('wrong-device'));
    await submission;
    expect(container.read(provider).deviceId, 'device');
    expect(container.read(provider).failure!.code, 'configuration_unverified');
    expect(container.read(provider).connectedDeviceId, isNull);
    await actions.submit(request);
    expect(connections.calls, hasLength(1));
    final reset = actions.reset();
    management.cancellations.single.result.completeError(
      StateError('cleanup failed'),
    );
    expect(await reset, isFalse);
    expect(
      container.read(provider).phase,
      ConnectionAttemptPhase.cleanupRequired,
    );
  });

  test('清理异常不抹去真实配对回执，也不接纳其他设备的回执', () async {
    final submission = actions.submit(_pair);
    setup.calls.single.result.completeError(
      DeviceSetupFailure(
        'setup_cleanup_unconfirmed',
        'release failed',
        receipt: _paired(),
      ),
    );
    await submission;
    expect(container.read(provider).pairing!.recorded, isTrue);
    expect(
      container.read(provider).phase,
      ConnectionAttemptPhase.cleanupRequired,
    );
    final reset = actions.reset();
    management.cancellations.single.result.complete();
    expect(await reset, isTrue);
    final next = actions.submit(_pair);
    setup.calls.last.result.completeError(
      const DeviceSetupFailure(
        'setup_cleanup_unconfirmed',
        'release failed',
        receipt: PairingReceipt(
          guid: 'other',
          address: 'other',
          device: DeviceSnapshot(id: 'other'),
        ),
      ),
    );
    await next;
    expect(container.read(provider).deviceId, 'device');
    expect(container.read(provider).pairing, isNull);
    expect(container.read(provider).canSubmit, isFalse);
  });

  testWidgets('窄屏大字仍可读到连接检查说明并使用操作按钮', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 520)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: ConnectionAttemptStatus(
          busy: false,
          checking: false,
          cancelling: false,
          paired: false,
          pairing: true,
          legacyTcp: false,
          address: '',
          failure: const SetupIssue('result_unknown', 'transport owner 32'),
          onCancel: () {},
          onEdit: () {},
          onRetry: () => fail('结果待确认时不能直接重新连接'),
          onRecheck: () => checks++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final explanation = find.text('暂时无法确认手机是否已连接。');
    expect(explanation, findsOneWidget);
    expect(find.textContaining('transport owner'), findsNothing);
    final button = find.text('重新检查');
    expect(
      tester.getRect(explanation).bottom,
      lessThan(tester.getTopLeft(button).dy),
    );
    await tester.tap(button);
    expect(checks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('添加设备的 USB 状态卡、表单和主操作在宽窗内共用中轴', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          darkTheme: ConnectTokens.theme(Brightness.dark),
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: MediaQuery.sizeOf(context).width < 400 ? 2 : 1,
            child: child!,
          ),
          home: const ConnectionFormPage(initialMode: AddDeviceMode.usb),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tabs = find.byType(ConnectionModeSelector);
    final status = find.text('连接手机');
    final statusIcon = find.byIcon(LucideIcons.circle);
    final check = find.widgetWithText(FilledButton, '检查连接');
    expect(tester.getCenter(tabs).dx, 640);
    expect(tester.getCenter(status).dx, 640);
    expect(tester.getCenter(statusIcon).dx, 640);
    expect(tester.getCenter(check).dx, 640);
    expect(
      tester.getRect(status).top,
      greaterThan(tester.getRect(tabs).bottom),
    );

    for (final (label, action) in [('配对码', '配对并连接'), ('IP 连接', '连接设备')]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byType(ConnectionAddressFields)).dx, 640);
      expect(
        tester.getCenter(find.widgetWithText(FilledButton, action)).dx,
        640,
      );
    }

    await tester.tap(find.text('USB'));
    tester.view.physicalSize = const Size(320, 520);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(tester.getCenter(status).dx, 160);
    expect(tester.getCenter(statusIcon).dx, 160);
    expect(tester.getCenter(check).dx, 160);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -380));
    await tester.pumpAndSettle();
    final help = find.widgetWithText(TextButton, 'USB 连接帮助');
    expect(tester.getRect(help).bottom, lessThan(tester.getRect(check).top));
    expect(help.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('连接失败返回配对码表单，主动切到 IP 才修改连接信息', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: const ConnectionFormPage(
            pairing: true,
            address: 'phone.local',
            port: '45678',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fields = tester.widget<ConnectionAddressFields>(
      find.byType(ConnectionAddressFields),
    );
    final inputs = find.byType(TextFormField);
    expect(
      tester.getTopLeft(inputs.at(0)).dy,
      tester.getTopLeft(inputs.at(1)).dy,
    );
    await tester.showKeyboard(inputs.at(2));
    final codeFocus = tester
        .widget<EditableText>(
          find.descendant(
            of: inputs.at(2),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode;
    expect(codeFocus.hasFocus, isTrue);
    fields.pairingCode.text = '123456';
    await tester.ensureVisible(find.text('配对并连接'));
    await tester.tap(find.text('配对并连接'));
    await tester.pump();
    expect(setup.calls, hasLength(1));
    expect(codeFocus.hasFocus, isFalse);
    expect(fields.pairingCode.text, isEmpty);
    setup.calls.single.result.complete(_paired());
    await tester.pumpAndSettle();
    expect(find.text('连接失败'), findsOneWidget);
    expect(find.text('补充连接端口'), findsNothing);
    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(find.text('配对并连接'), findsOneWidget);
    expect(fields.address.text, 'phone.local');
    expect(fields.port.text, '45678');
    expect(fields.pairingCode.text, isEmpty);
    await tester.tap(find.text('IP 连接'));
    await tester.pumpAndSettle();
    final completed = tester.widget<ConnectionAddressFields>(
      find.byType(ConnectionAddressFields),
    );
    expect(completed.pairing, isFalse);
    expect(completed.legacyTcp, isFalse);
    expect(completed.address.text, 'phone.local');
    expect(completed.port.text, isEmpty);
    completed.port.text = '45679';
    await tester.ensureVisible(find.text('连接设备'));
    await tester.tap(find.text('连接设备'));
    await tester.pump();
    expect(management.saves.single.id, 'device');
    expect(management.saves.single.endpoint.transport, DeviceTransport.tls);
    management.saves.single.result.complete(const DeviceSnapshot(id: 'device'));
    await tester.pump();
    connections.calls.single.result.completeError(
      const RequestFailure('timeout', 'connection timeout'),
    );
    await tester.pumpAndSettle();
    expect(find.text('connection timeout'), findsNothing);
    expect(find.textContaining('手机没有及时响应'), findsOneWidget);
    expect(find.text('重试连接'), findsOneWidget);
    expect(setup.calls, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump();
  });
}

DeviceConnectionReceipt _connected(String id) => DeviceConnectionReceipt(
  device: DeviceSnapshot(id: id, status: .connected),
);
PairingReceipt _paired({SetupIssue? issue}) => PairingReceipt(
  guid: 'guid',
  address: 'phone.local',
  device: const DeviceSnapshot(id: 'device'),
  connectionPortRequired: issue == null,
  connectionFailure: issue,
);

final class _Setup implements DeviceSetup {
  final calls = <({String id, Completer<PairingReceipt> result})>[];
  @override
  Future<PairingReceipt> pairDevice(
    String address,
    int port,
    String code, {
    String? deviceId,
    String? attemptId,
    SetupIdentity? identity,
  }) {
    final result = Completer<PairingReceipt>();
    calls.add((id: attemptId!, result: result));
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Management implements DeviceManagement, DeviceReader {
  List<DeviceSnapshot> devices = [];
  final saves =
      <
        ({
          String? id,
          DeviceEndpoint endpoint,
          AdbCancellation? stop,
          Completer<DeviceSnapshot> result,
        })
      >[];
  final cancellations = <({String id, Completer<void> result})>[];
  Future<DeviceSnapshot> _save(
    String? id,
    DeviceEndpoint endpoint,
    AdbCancellation? stop,
  ) {
    final result = Completer<DeviceSnapshot>();
    saves.add((id: id, endpoint: endpoint, stop: stop, result: result));
    return result.future;
  }

  @override
  Future<DeviceSnapshot> addDevice(
    DeviceEndpoint endpoint, {
    String name = 'Android 设备',
    SetupIdentity? identity,
    AdbCancellation? cancellation,
  }) => _save(null, endpoint, cancellation);
  @override
  Future<DeviceSnapshot> updateDeviceEndpoint(
    String deviceId,
    DeviceEndpoint endpoint, {
    AdbCancellation? cancellation,
  }) => _save(deviceId, endpoint, cancellation);
  @override
  Future<void> cancelConnectionAttempt(String attemptId) {
    final result = Completer<void>();
    cancellations.add((id: attemptId, result: result));
    return result.future;
  }

  @override
  List<DeviceSnapshot> readDevices() => devices;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Connections implements DeviceConnectionControl {
  final calls =
      <
        ({
          String id,
          String attempt,
          bool configuring,
          AdbCancellation? stop,
          Completer<DeviceConnectionReceipt> result,
        })
      >[];
  Future<DeviceConnectionReceipt> _start(
    String id,
    String attempt,
    bool configuring,
    AdbCancellation? stop,
  ) {
    final result = Completer<DeviceConnectionReceipt>();
    calls.add((
      id: id,
      attempt: attempt,
      configuring: configuring,
      stop: stop,
      result: result,
    ));
    return result.future;
  }

  @override
  Future<DeviceConnectionReceipt> connectDevice(
    String deviceId, {
    String? attemptId,
    ConnectionCandidateSource candidateSource = .saved,
    AdbCancellation? cancellation,
  }) => _start(deviceId, attemptId!, false, cancellation);
  @override
  Future<DeviceConnectionReceipt> configureDevice(
    String deviceId,
    DeviceEndpoint endpoint, {
    String? attemptId,
    ConnectionCandidateSource candidateSource = .saved,
    AdbCancellation? cancellation,
  }) => _start(deviceId, attemptId!, true, cancellation);
}

final class _Reconcile {
  final calls = <Completer<void>>[];
  Future<void> run() {
    final result = Completer<void>();
    calls.add(result);
    return result.future;
  }
}
