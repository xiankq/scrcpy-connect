import 'dart:async';

import 'package:adb/adb.dart' show AdbCancellation;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_discovery_provider.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';

void main() {
  group('设备查询独立装配', () {
    late _Inspection inspection;
    late StreamController<Map<String, dynamic>> events;
    late ProviderContainer container;
    setUp(() {
      inspection = _Inspection();
      events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
      container = ProviderContainer(
        overrides: [
          deviceInspectionProvider.overrideWithValue(inspection),
          runtimeEventsProvider.overrideWithValue(events.stream),
        ],
      );
    });
    tearDown(() async {
      container.dispose();
      await events.close();
    });

    test('消费者共享读取，最后一个离开后取消请求与事件订阅', () async {
      final provider = deviceDetailsProvider(
        'device',
        connectionId: 'connection',
      );
      final first = container.listen(provider, (_, _) {});
      final second = container.listen(provider, (_, _) {});
      expect(inspection.reads, hasLength(1));
      final read = inspection.reads.single;
      expect(read.deviceId, 'device');
      expect(read.connectionId, 'connection');
      first.close();
      await container.pump();
      expect(read.cancellation.isCancelled, isFalse);
      second.close();
      await container.pump();
      expect(read.cancellation.isCancelled, isTrue);
      expect(events.hasListener, isFalse);
    });

    test('连接事件立即取消旧读取，迟到结果不能覆盖下一次核验', () async {
      final provider = deviceDetailsProvider('device');
      container.listen(provider, (_, _) {});
      final previous = inspection.reads.single;
      events.add({'type': 'device.connected', 'deviceId': 'another-device'});
      events.add({'type': 'session.frame', 'deviceId': 'device'});
      await _flush(container);
      expect(inspection.reads, hasLength(1));
      expect(previous.cancellation.isCancelled, isFalse);
      events.add({'type': 'device.connected', 'deviceId': 'device'});
      expect(previous.cancellation.isCancelled, isTrue);
      await _flush(container);
      expect(inspection.reads, hasLength(2));
      previous.result.complete(_details('old-connection'));
      await _flush(container);
      expect(container.read(provider).isLoading, isTrue);
      inspection.reads.last.result.complete(_details('new-connection'));
      await _flush(container);
      expect(
        container.read(provider).requireValue.connectionId,
        'new-connection',
      );
    });

    test('替换能力和事件源后撤销原请求，保留新来源的结果', () async {
      final provider = deviceDetailsProvider('device');
      container.listen(provider, (_, _) {});
      final previous = inspection.reads.single;
      final replacement = _Inspection();
      final replacementEvents =
          StreamController<Map<String, dynamic>>.broadcast(sync: true);
      addTearDown(replacementEvents.close);
      container.updateOverrides([
        deviceInspectionProvider.overrideWithValue(replacement),
        runtimeEventsProvider.overrideWithValue(replacementEvents.stream),
      ]);
      await _flush(container);
      expect(previous.cancellation.isCancelled, isTrue);
      expect(events.hasListener, isFalse);
      replacement.reads.single.result.complete(_details('replacement'));
      await _flush(container);
      previous.result.complete(_details('retired'));
      events.add({'type': 'state.resync', 'data': const RecoveryStarted()});
      await _flush(container);
      expect(container.read(provider).requireValue.connectionId, 'replacement');
      expect(replacement.reads, hasLength(1));
    });
  });

  test('发现扫描只需替换设备设置能力，离页后取消在途扫描', () async {
    final setup = _Setup();
    final container = ProviderContainer(
      overrides: [deviceSetupProvider.overrideWithValue(setup)],
    );
    addTearDown(container.dispose);
    final listener = container.listen(deviceDiscoveryProvider, (_, _) {});
    expect(setup.cancellation.isCancelled, isFalse);
    listener.close();
    await container.pump();
    expect(setup.cancellation.isCancelled, isTrue);
    setup.result.complete(const []);
    await _flush(container);
  });
}

Future<void> _flush(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
}

DeviceReading<DeviceDetails> _details(String connectionId) => DeviceReading(
  deviceId: 'device',
  connectionId: connectionId,
  value: const DeviceDetails(),
);

typedef _Read = ({
  String deviceId,
  String? connectionId,
  AdbCancellation cancellation,
  Completer<DeviceReading<DeviceDetails>> result,
});

class _Inspection implements DeviceInspection {
  final reads = <_Read>[];
  @override
  Future<DeviceReading<DeviceDetails>> readDetails(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) {
    final result = Completer<DeviceReading<DeviceDetails>>();
    reads.add((
      deviceId: deviceId,
      connectionId: connectionId,
      cancellation: cancellation!,
      result: result,
    ));
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Setup implements DeviceSetup {
  late AdbCancellation cancellation;
  final result = Completer<List<DiscoveredDevice>>();
  @override
  Future<List<DiscoveredDevice>> discoverDevices({
    String? attemptId,
    AdbCancellation? cancellation,
  }) {
    this.cancellation = cancellation!;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
