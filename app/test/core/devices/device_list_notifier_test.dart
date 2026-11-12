import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

void main() {
  late StreamController<Map<String, dynamic>> events;
  late _Devices source;
  late _Session dependencies;
  late ProviderContainer container;
  setUp(() {
    events = StreamController.broadcast(sync: true);
    dependencies = _Session(events.stream);
    source = _Devices();
    container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(dependencies),
        deviceReaderProvider.overrideWithValue(source),
      ],
    );
    container.listen(deviceListProvider, (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await events.close();
  });

  test('设备能力换源清空旧投影，旧回执和订阅不再影响新列表', () async {
    final actions = container.read(deviceListProvider.notifier);
    expect(container.read(deviceListProvider).devices.single.id, 'initial');
    final retired = actions.refresh();
    final replacement = _Devices();
    container.updateOverrides([
      appSessionProvider.overrideWithValue(dependencies),
      deviceReaderProvider.overrideWithValue(replacement),
    ]);
    await container.pump();
    expect(container.read(deviceListProvider).devices, isEmpty);
    expect(container.read(deviceListProvider.notifier), same(actions));
    final refresh = actions.refresh();
    replacement.reads.single.complete([
      const DeviceSnapshot(id: 'new', name: 'New'),
    ]);
    await refresh;
    source.reads.single.completeError(StateError('old source failed'));
    await retired;
    expect(container.read(deviceListProvider).devices.single.id, 'new');
    expect(container.read(deviceListProvider).error, isNull);
    events.add({'type': 'device.changed'});
    expect(replacement.reads, hasLength(2));
    expect(source.reads, hasLength(1));
    replacement.reads.last.complete([
      const DeviceSnapshot(id: 'latest', name: 'Latest'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(deviceListProvider).devices.single.id, 'latest');
  });

  test('权威恢复快照作废在途读取，scope 关闭后不再提交或订阅', () async {
    final actions = container.read(deviceListProvider.notifier);
    final loading = actions.refresh();
    events.add({'type': 'state.resync'});
    events.add({
      'type': 'state.resynced',
      'data': RuntimeSnapshot(
        sequence: 1,
        settings: Preferences(),
        devices: [
          const DeviceSnapshot(
            id: 'verified',
            name: 'Verified',
            status: .connected,
          ),
        ],
      ),
    });
    source.reads.single.complete([
      const DeviceSnapshot(id: 'old', name: 'Old'),
    ]);
    await loading;
    expect(container.read(deviceListProvider).devices.single.id, 'verified');
    expect(container.read(deviceListProvider).loading, isFalse);
    final retired = actions.refresh();
    container.dispose();
    source.reads.last.completeError(StateError('late failure'));
    await retired;
    expect(events.hasListener, isFalse);
  });
}

class _Devices implements DeviceReader {
  final reads = <Completer<List<DeviceSnapshot>>>[];
  @override
  Future<List<DeviceSnapshot>> readDevices() {
    final result = Completer<List<DeviceSnapshot>>();
    reads.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements AppSession {
  _Session(this.events);
  @override
  final initialState = AppState(
    devices: [const DeviceSnapshot(id: 'initial', name: 'Initial')],
    loading: false,
  );
  @override
  final Stream<Map<String, dynamic>> events;
  @override
  bool get initialize => false;
  @override
  Future<void> Function()? get close => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
