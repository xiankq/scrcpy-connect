import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/identity/models/setup_identity.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/pages/device_setup/pairing/models/qr_pairing_state.dart';
import 'package:scrcpy_connect/pages/device_setup/pairing/qr_pairing_notifier.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/connection_form_page.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  late _Setup setup;
  late _Management management;
  late ProviderContainer container;
  final scope = Object();
  final provider = qrPairingProvider(deviceId: 'device', scope: scope);
  late QrPairingNotifier actions;
  late void Function() leave;
  final session = AppSession(initialize: false);
  final connections = _Connections();
  overrides() => [
    appSessionProvider.overrideWithValue(session),
    deviceSetupProvider.overrideWithValue(setup),
    deviceManagementProvider.overrideWithValue(management),
    deviceReaderProvider.overrideWithValue(management),
    deviceConnectionsProvider.overrideWithValue(connections),
  ];
  setUp(() {
    setup = _Setup();
    management = _Management();
    container = ProviderContainer(overrides: overrides());
    final subscription = container.listen(provider, (_, _) {});
    leave = subscription.close;
    actions = container.read(provider.notifier);
  });
  tearDown(() => container.dispose());

  test('取得二维码句柄前即可取消，迟到句柄及失败不复活页面', () async {
    final generate = actions.generate();
    await actions.generate();
    expect(setup.calls, hasLength(1));
    final cancel = actions.cancel();
    expect(management.cancellations.single.id, setup.calls.single.id);
    management.cancellations.single.result.complete();
    expect(await cancel, isTrue);
    setup.calls.single.deliver();
    await generate;
    setup.calls.single.result.completeError(StateError('late result'));
    await container.pump();
    expect(container.read(provider).phase, QrPairingPhase.cancelled);
    expect(container.read(provider).hasQr, isFalse);
    expect(container.read(provider).receipt, isNull);
  });

  test('重新生成必须确认原二维码已回收，失败重试同一标识', () async {
    final first = actions.generate();
    setup.calls.single.deliver();
    await first;
    expect(container.read(provider).hasQr, isTrue);
    final regenerate = actions.generate();
    expect(container.read(provider).hasQr, isFalse);
    management.cancellations.single.result.completeError(
      StateError('still owned'),
    );
    await regenerate;
    expect(container.read(provider).phase, QrPairingPhase.cleanupRequired);
    expect(setup.calls, hasLength(1));
    final retry = actions.generate();
    expect(management.cancellations.last.id, setup.calls.single.id);
    management.cancellations.last.result.complete();
    await container.pump();
    expect(setup.calls, hasLength(2));
    setup.calls.first.result.complete(_paired('device'));
    setup.calls.last.deliver();
    await retry;
    expect(container.read(provider).phase, QrPairingPhase.waiting);
    expect(container.read(provider).receipt, isNull);
    setup.calls.last.result.complete(_paired('device'));
    await container.pump();
    expect(container.read(provider).phase, QrPairingPhase.completed);
    expect(container.read(provider).receipt!.recorded, isTrue);
  });

  test('换源与离页停止原二维码，原结果不污染新所有者', () async {
    final first = actions.generate();
    setup.calls.single.deliver();
    await first;
    final oldSetup = setup;
    final oldManagement = management;
    setup = _Setup();
    management = _Management();
    container.updateOverrides(overrides());
    await container.pump();
    expect(oldManagement.cancellations.single.id, oldSetup.calls.single.id);
    oldManagement.cancellations.single.result.complete();
    oldSetup.calls.single.result.complete(_paired('device'));
    await container.pump();
    expect(container.read(provider).phase, QrPairingPhase.idle);
    final next = actions.generate();
    setup.calls.single.deliver();
    await next;
    leave();
    await container.pump();
    expect(management.cancellations.single.id, setup.calls.single.id);
    management.cancellations.single.result.complete();
    setup.calls.single.result.completeError(StateError('retired'));
    await container.pump();
  });

  test('完成与清理分别表达，保留配对事实但不绕过原回收失败', () async {
    final first = actions.generate();
    setup.calls.single.deliver();
    await first;
    setup.calls.single.result.completeError(
      DeviceSetupFailure(
        'setup_cleanup_unconfirmed',
        'release failed',
        receipt: _paired('device'),
      ),
    );
    await container.pump();
    expect(container.read(provider).phase, QrPairingPhase.cleanupRequired);
    expect(container.read(provider).receipt!.recorded, isTrue);
    final regenerate = actions.generate();
    management.cancellations.single.result.completeError(
      StateError('still owned'),
    );
    await regenerate;
    expect(setup.calls, hasLength(1));
    expect(container.read(provider).receipt!.recorded, isTrue);
    final cancel = actions.cancel();
    management.cancellations.last.result.complete();
    expect(await cancel, isTrue);
    expect(container.read(provider).receipt!.recorded, isTrue);
  });

  testWidgets('二维码到期立即隐藏，确认取消前不接纳迟到配对', (tester) async {
    final first = actions.generate();
    setup.calls.single.deliver(expiresIn: const Duration(milliseconds: 100));
    await first;
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(provider).phase, QrPairingPhase.cancelling);
    expect(container.read(provider).hasQr, isFalse);
    expect(management.cancellations.single.id, setup.calls.single.id);
    setup.calls.single.result.complete(_paired('device'));
    management.cancellations.single.result.complete();
    await tester.pump();
    expect(container.read(provider).phase, QrPairingPhase.expired);
    expect(container.read(provider).receipt, isNull);
    await tester.pump(const Duration(minutes: 1));
    expect(management.cancellations, hasLength(1));
  });

  test('配对回执核验原设备，拒绝将其他设备呈现为成功', () async {
    final first = actions.generate();
    setup.calls.single.deliver();
    await first;
    setup.calls.single.result.complete(_paired('wrong-device'));
    await container.pump();
    expect(container.read(provider).phase, QrPairingPhase.failed);
    expect(container.read(provider).receipt, isNull);
    expect(container.read(provider).message, contains('匹配到了另一台手机'));
  });

  testWidgets('添加页接纳配对后的设备身份，保留结果且不自动生成另一次二维码', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: const ConnectionFormPage(initialMode: AddDeviceMode.qr),
        ),
      ),
    );
    await tester.pump();
    expect(setup.calls, hasLength(1));
    setup.calls.single.deliver();
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.textContaining('扫描此二维码。')).dx, 640);
    expect(tester.getCenter(find.widgetWithText(FilledButton, '重新生成')).dx, 640);
    setup.calls.single.result.complete(_paired('device'));
    await tester.pumpAndSettle();
    expect(find.text('已配对，尚未连接'), findsOneWidget);
    expect(find.text('修改连接信息'), findsOneWidget);
    expect(setup.calls, hasLength(1));
    expect(management.cancellations, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

PairingReceipt _paired(String id) => PairingReceipt(
  guid: 'guid',
  address: 'phone.local',
  device: DeviceSnapshot(id: id, status: .paired),
  connectionPortRequired: true,
);

final class _Setup implements DeviceSetup {
  final calls = <_QrCall>[];
  @override
  Future<QrPairingSession> beginQrPairing({
    String? deviceId,
    String? attemptId,
    SetupIdentity? identity,
  }) {
    final call = _QrCall(attemptId!);
    calls.add(call);
    return call.session.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _QrCall {
  _QrCall(this.id);
  final String id;
  final session = Completer<QrPairingSession>();
  final result = Completer<PairingReceipt>();

  void deliver({Duration expiresIn = const Duration(minutes: 2)}) =>
      session.complete(
        QrPairingSession(
          attemptId: id,
          payload: 'WIFI:T:ADB;S:$id;P:test;;',
          expiresAt: DateTime.now().add(expiresIn),
          result: result.future,
        ),
      );
}

final class _Management implements DeviceManagement, DeviceReader {
  final cancellations = <({String id, Completer<void> result})>[];
  @override
  Future<void> cancelConnectionAttempt(String attemptId) {
    final result = Completer<void>();
    cancellations.add((id: attemptId, result: result));
    return result.future;
  }

  @override
  List<DeviceSnapshot> readDevices() => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Connections implements DeviceConnectionControl {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
