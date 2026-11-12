import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/current_device_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/app_snapshot_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/media/audio_error_notifier.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';

void main() {
  test('事件发布前一次提交完整投影，恢复不覆盖当前设备和音频错误', () async {
    final events = StreamController<Json>.broadcast(sync: true);
    final dependencies = _Session(events.stream, 'initial');
    final container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(dependencies),
        deviceManagementProvider.overrideWithValue(dependencies.devices),
        settingsManagementProvider.overrideWithValue(dependencies.settings),
        incomingSharesProvider.overrideWithValue(dependencies.incomingShares),
      ],
    );
    container.read(appSnapshotProvider);
    await container.read(currentDeviceProvider.notifier).focus('selected');
    container.read(audioErrorProvider.notifier).update('local audio failure');
    final projections = <AppState>[];
    container.listen(appSnapshotProvider, (_, next) => projections.add(next));
    final observed = <AppState>[];
    final subscription = container.read(runtimeEventsProvider).listen((_) {
      observed.add(container.read(appSnapshotProvider));
    });
    events.add({
      'type': 'state.resynced',
      'data': RuntimeSnapshot(
        sequence: 1,
        devices: [
          const DeviceSnapshot(
            id: 'device',
            name: 'updated',
            status: .connected,
          ),
        ],
        settings: Preferences(appearance: .dark),
        shares: [const IncomingShare(shareId: 'share', status: .ready)],
      ),
    });
    expect(projections, hasLength(1));
    final snapshot = observed.single;
    expect(snapshot.devices.single.name, 'updated');
    expect(snapshot.settings.appearance, Appearance.dark);
    expect(snapshot.pendingShares.single.shareId, 'share');
    expect(snapshot.reconciliationPending, isFalse);
    expect(snapshot.loading, isFalse);
    expect(snapshot.focusedDeviceId, 'selected');
    expect(snapshot.audioError, 'local audio failure');
    // 相同水位在没有恢复请求时是重复回执，不重复交付状态或事件。
    events.add({
      'type': 'state.resynced',
      'data': RuntimeSnapshot(sequence: 1, settings: Preferences()),
    });
    expect(observed, hasLength(1));
    expect(projections, hasLength(1));
    await subscription.cancel();
    container.dispose();
    await events.close();
    expect(dependencies.closes, 1);
  });

  test('替换应用作用域后取消旧事件订阅，只关闭各自所有者一次', () async {
    final oldEvents = StreamController<Json>.broadcast(sync: true);
    final newEvents = StreamController<Json>.broadcast(sync: true);
    final previous = _Session(oldEvents.stream, 'previous');
    final replacement = _Session(newEvents.stream, 'replacement');
    final container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(previous),
        deviceManagementProvider.overrideWithValue(previous.devices),
        settingsManagementProvider.overrideWithValue(previous.settings),
        incomingSharesProvider.overrideWithValue(previous.incomingShares),
      ],
    );
    container.listen(appSnapshotProvider, (_, _) {});
    container.updateOverrides([
      appSessionProvider.overrideWithValue(replacement),
      deviceManagementProvider.overrideWithValue(replacement.devices),
      settingsManagementProvider.overrideWithValue(replacement.settings),
      incomingSharesProvider.overrideWithValue(replacement.incomingShares),
    ]);
    await container.pump();
    var snapshot = container.read(appSnapshotProvider);
    expect(snapshot.focusedDeviceId, 'replacement');
    expect(snapshot.audioError, 'replacement audio');
    expect(oldEvents.hasListener, isFalse);
    expect(previous.closes, 1);
    oldEvents.add({'type': 'state.resync'});
    newEvents.add({'type': 'state.resync'});
    snapshot = container.read(appSnapshotProvider);
    expect(snapshot.reconciliationPending, isTrue);
    expect(snapshot.focusedDeviceId, 'replacement');
    container.dispose();
    await oldEvents.close();
    await newEvents.close();
    expect(previous.closes, 1);
    expect(replacement.closes, 1);
  });
}

class _Session implements AppSession {
  _Session(this.events, String label)
    : initialState = AppState(
        focusedDeviceId: label,
        audioError: '$label audio',
      );

  int closes = 0;
  final SettingsManagement settings = _Settings();
  final IncomingShares incomingShares = _Shares();
  final DeviceManagement devices = _Devices();
  @override
  final Stream<Json> events;
  @override
  final AppState initialState;
  @override
  bool get initialize => false;
  @override
  DiagnosticLog? get diagnostics => null;
  @override
  Future<void> Function() get close => () async {
    closes++;
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings implements SettingsManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Shares implements IncomingShares {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Devices implements DeviceManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
