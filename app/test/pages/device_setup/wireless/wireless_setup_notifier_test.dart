import 'dart:async';

import 'package:adb/adb.dart' show AdbCancellation;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/models/device_endpoint.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/pages/device_setup/wireless/models/wireless_setup_state.dart';
import 'package:scrcpy_connect/pages/device_setup/wireless/wireless_setup_notifier.dart';

void main() {
  test('确认前只核验来源，提交绑定原连接且重复确认不重发', () async {
    final fixture = await _Fixture.open();
    final plan = await fixture.prepare();
    expect(fixture.state.phase, WirelessSetupPhase.confirming);
    expect(fixture.setup.calls, isEmpty);
    expect(fixture.inspection.calls.last.connectionId, 'original');
    await fixture.actions.submit(plan.copyWith(port: 7777));
    expect(fixture.setup.calls, isEmpty);
    final submitting = fixture.actions.submit(plan);
    await fixture.actions.submit(plan);
    await _tick();
    final call = fixture.setup.calls.single;
    expect(call.deviceId, 'device');
    expect(call.connectionId, 'original');
    expect(call.attemptId, plan.attemptId);
    expect(call.address, plan.address);
    expect(call.port, plan.port);
    call.result.complete(_connected(plan));
    await submitting;
    expect(fixture.state.phase, WirelessSetupPhase.completed);
    expect(fixture.state.result!.connected, isTrue);
  });

  test('撤回确认不创建核心尝试，旧确认不能提交后一次意图', () async {
    final fixture = await _Fixture.open();
    final first = await fixture.prepare();
    fixture.actions.dismiss(first);
    expect(fixture.state.phase, WirelessSetupPhase.idle);
    expect(fixture.management.cancellations, isEmpty);
    final next = await fixture.prepare();
    expect(next.attemptId, isNot(first.attemptId));
    await fixture.actions.submit(first);
    expect(fixture.state.confirmation, same(next));
    expect(fixture.setup.calls, isEmpty);
  });

  test('确认期间原连接变化，旧目标不能提交到新连接', () async {
    final fixture = await _Fixture.open();
    final plan = await fixture.prepare();
    fixture.reader.current = _device.copyWith(connectionId: 'successor');
    await fixture.actions.submit(plan);
    expect(fixture.setup.calls, isEmpty);
    expect(fixture.state.phase, WirelessSetupPhase.failed);
    expect(fixture.state.error, contains('连接已变化'));
    expect(fixture.state.notice, isNull);
  });

  test('核验期间目标地址变化，保留新地址并要求重新选择', () async {
    final fixture = await _Fixture.open();
    final preparing = fixture.actions.prepare(address: '192.0.2.1', port: 5555);
    await _tick();
    fixture.inspection.calls.last.result.complete(_network('192.0.2.2'));
    expect(await preparing, isNull);
    expect(fixture.state.phase, WirelessSetupPhase.idle);
    expect(fixture.state.addresses.single.address, '192.0.2.2');
    expect(fixture.state.notice, contains('重新选择'));
    expect(fixture.setup.calls, isEmpty);
  });

  for (final invalid in [
    _network().copyWith(deviceId: 'other'),
    _network().copyWith(connectionId: 'old'),
    _network().copyWith(stale: true),
  ]) {
    test('未核验的网络来源不能生成确认：$invalid', () async {
      final fixture = await _Fixture.open();
      final preparing = fixture.actions.prepare(
        address: '192.0.2.1',
        port: 5555,
      );
      await _tick();
      fixture.inspection.calls.last.result.complete(invalid);
      expect(await preparing, isNull);
      expect(fixture.state.phase, WirelessSetupPhase.failed);
      expect(fixture.state.addresses, isEmpty);
      expect(fixture.setup.calls, isEmpty);
    });
  }

  test('换次读取取消原查询，迟到旧地址不能覆盖新结果', () async {
    final fixture = await _Fixture.open();
    final first = fixture.actions.refresh();
    await _tick();
    final old = fixture.inspection.calls.last;
    final second = fixture.actions.refresh();
    await _tick();
    expect(old.cancellation.isCancelled, isTrue);
    fixture.inspection.calls.last.result.complete(_network('192.0.2.2'));
    await second;
    old.result.complete(_network('192.0.2.99'));
    await first;
    expect(fixture.state.addresses.single.address, '192.0.2.2');
    expect(fixture.state.error, isNull);
  });

  test('取消同步撤销成功准入，原回收未确认前不能重新提交', () async {
    final fixture = await _Fixture.open();
    final plan = await fixture.prepare();
    final submitting = fixture.actions.submit(plan);
    await _tick();
    final cancelling = fixture.actions.cancel();
    final sameCancel = fixture.actions.cancel();
    expect(fixture.state.phase, WirelessSetupPhase.cancelling);
    await _tick();
    expect(fixture.management.cancellations, hasLength(1));
    fixture.setup.calls.single.result.complete(_connected(plan));
    await submitting;
    expect(fixture.state.phase, WirelessSetupPhase.cancelling);
    expect(fixture.state.result, isNull);
    expect(
      await fixture.actions.prepare(address: plan.address, port: plan.port),
      isNull,
    );
    fixture.management.cancellations.single.result.complete();
    await Future.wait([cancelling, sameCancel]);
    expect(fixture.state.phase, WirelessSetupPhase.cancelled);
    expect(fixture.management.cancellations.single.id, plan.attemptId);
  });

  test('取消失败保留原尝试，重试同一清理责任且不接纳迟到失败', () async {
    final fixture = await _Fixture.open();
    final plan = await fixture.prepare();
    final submitting = fixture.actions.submit(plan);
    await _tick();
    final cancelling = fixture.actions.cancel();
    await _tick();
    fixture.management.cancellations.single.result.completeError(
      StateError('still owned'),
    );
    await cancelling;
    expect(fixture.state.phase, WirelessSetupPhase.cleanupRequired);
    fixture.setup.calls.single.result.completeError(
      const RequestFailure('cancelled', 'late'),
    );
    await submitting;
    expect(fixture.state.error, contains('重试取消'));
    expect(
      await fixture.actions.prepare(address: plan.address, port: plan.port),
      isNull,
    );
    final retry = fixture.actions.cancel();
    await _tick();
    expect(fixture.management.cancellations.last.id, plan.attemptId);
    fixture.management.cancellations.last.result.complete();
    await retry;
    expect(fixture.state.phase, WirelessSetupPhase.cancelled);
  });

  test('核心清理失败保留已经连接的事实，页面只能重试原回收', () async {
    final fixture = await _Fixture.open();
    final plan = await fixture.prepare();
    final submitting = fixture.actions.submit(plan);
    await _tick();
    fixture.setup.calls.single.result.completeError(
      DeviceSetupFailure(
        'setup_cleanup_unconfirmed',
        'release failed',
        receipt: _connected(plan),
      ),
    );
    await submitting;
    expect(fixture.state.phase, WirelessSetupPhase.cleanupRequired);
    expect(fixture.state.result!.connected, isTrue);
    final cancelling = fixture.actions.cancel();
    await _tick();
    fixture.management.cancellations.single.result.complete();
    await cancelling;
    expect(fixture.state.result!.connected, isTrue);
  });

  test('依赖换源取消原所有者，旧结果不进入重新初始化的页面', () async {
    final fixture = await _Fixture.open();
    final plan = await fixture.prepare();
    final submitting = fixture.actions.submit(plan);
    await _tick();
    final oldSetup = fixture.setup;
    final oldManagement = fixture.management;
    fixture.setup = _Setup();
    fixture.management = _Management();
    fixture.inspection = _Inspection();
    fixture.reader = _Reader();
    fixture.container.updateOverrides(fixture.overrides());
    await fixture.container.pump();
    await _tick();
    expect(oldManagement.cancellations.single.id, plan.attemptId);
    oldSetup.calls.single.result.complete(_connected(plan));
    oldManagement.cancellations.single.result.complete();
    await submitting;
    expect(fixture.state.phase, WirelessSetupPhase.reading);
    fixture.inspection.calls.single.result.complete(_network());
    await _tick();
    expect(fixture.state.phase, WirelessSetupPhase.idle);
    expect(fixture.state.result, isNull);
    expect(fixture.setup.calls, isEmpty);
  });

  test('离页撤销原网络读取，迟到地址不创建切换或取消其他尝试', () async {
    final fixture = await _Fixture.open();
    final reading = fixture.actions.refresh();
    await _tick();
    final original = fixture.inspection.calls.last;
    fixture.leave();
    await fixture.container.pump();
    expect(original.cancellation.isCancelled, isTrue);
    original.result.complete(_network());
    await reading;
    expect(fixture.setup.calls, isEmpty);
    expect(fixture.management.cancellations, isEmpty);
  });
}

const _device = DeviceSnapshot(
  id: 'device',
  status: .connected,
  connectionId: 'original',
);

DeviceReading<DeviceNetworkInfo> _network([String address = '192.0.2.1']) =>
    DeviceReading(
      deviceId: 'device',
      connectionId: 'original',
      value: DeviceNetworkInfo(
        addresses: [DeviceNetworkAddress(interface: 'wlan0', address: address)],
      ),
    );

WirelessReceipt _connected(WirelessSwitchRequest request) => WirelessReceipt(
  deviceId: request.deviceId,
  address: request.address,
  port: request.port,
  connection: DeviceConnectionReceipt(
    device: _device.copyWith(connectionId: 'tcp'),
  ),
);

Future<void> _tick() => Future<void>.delayed(Duration.zero);

final class _Fixture {
  final scope = Object();
  late final provider = wirelessSetupProvider(deviceId: 'device', scope: scope);
  final session = AppSession(initialize: false);
  _Inspection inspection = _Inspection();
  _Setup setup = _Setup();
  _Management management = _Management();
  _Reader reader = _Reader();
  late ProviderContainer container;
  late void Function() leave;
  WirelessSetupNotifier get actions => container.read(provider.notifier);
  WirelessSetupState get state => container.read(provider);

  List<Override> overrides() => [
    appSessionProvider.overrideWithValue(session),
    deviceInspectionProvider.overrideWithValue(inspection),
    deviceSetupProvider.overrideWithValue(setup),
    deviceManagementProvider.overrideWithValue(management),
    deviceReaderProvider.overrideWithValue(reader),
  ];

  static Future<_Fixture> open() async {
    final fixture = _Fixture();
    fixture.container = ProviderContainer(overrides: fixture.overrides());
    fixture.leave = fixture.container.listen(fixture.provider, (_, _) {}).close;
    addTearDown(() async {
      fixture.container.dispose();
      for (final call in fixture.inspection.calls) {
        if (!call.result.isCompleted) {
          call.result.completeError(StateError('disposed'));
        }
      }
      for (final call in fixture.setup.calls) {
        if (!call.result.isCompleted) {
          call.result.completeError(StateError('disposed'));
        }
      }
      for (final call in fixture.management.cancellations) {
        if (!call.result.isCompleted) call.result.complete();
      }
      await _tick();
    });
    await _tick();
    fixture.inspection.calls.single.result.complete(_network());
    await _tick();
    expect(fixture.state.phase, WirelessSetupPhase.idle);
    return fixture;
  }

  Future<WirelessSwitchRequest> prepare() async {
    final future = actions.prepare(address: '192.0.2.1', port: 5555);
    await _tick();
    inspection.calls.last.result.complete(_network());
    return (await future)!;
  }
}

final class _Inspection implements DeviceInspection {
  final calls =
      <
        ({
          String? connectionId,
          AdbCancellation cancellation,
          Completer<DeviceReading<DeviceNetworkInfo>> result,
        })
      >[];
  @override
  Future<DeviceReading<DeviceNetworkInfo>> readNetwork(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) {
    final result = Completer<DeviceReading<DeviceNetworkInfo>>();
    calls.add((
      connectionId: connectionId,
      cancellation: cancellation!,
      result: result,
    ));
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected inspection ${invocation.memberName}');
}

final class _Setup implements DeviceSetup {
  final calls =
      <
        ({
          String deviceId,
          String address,
          int port,
          String? connectionId,
          String attemptId,
          Completer<WirelessReceipt> result,
        })
      >[];
  @override
  Future<WirelessReceipt> enableWireless(
    String deviceId,
    String address, {
    int port = 5555,
    required String connectionId,
    String? attemptId,
  }) {
    final result = Completer<WirelessReceipt>();
    calls.add((
      deviceId: deviceId,
      address: address,
      port: port,
      connectionId: connectionId,
      attemptId: attemptId!,
      result: result,
    ));
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected setup ${invocation.memberName}');
}

final class _Management implements DeviceManagement {
  final cancellations = <({String id, Completer<void> result})>[];
  @override
  Future<void> cancelConnectionAttempt(String attemptId) {
    final result = Completer<void>();
    cancellations.add((id: attemptId, result: result));
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected management ${invocation.memberName}');
}

final class _Reader implements DeviceReader {
  DeviceSnapshot current = _device;
  @override
  DeviceSnapshot readDevice(String id) => current;
  @override
  List<DeviceSnapshot> readDevices() => [current];
}
