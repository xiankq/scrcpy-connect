import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';

void main() {
  late _Settings settings;
  late _Session dependencies;
  late StreamController<Map<String, dynamic>> events;
  late ProviderContainer container;
  setUp(() {
    settings = _Settings();
    events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    dependencies = _Session(events.stream);
    container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(dependencies),
        settingsManagementProvider.overrideWithValue(settings),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await events.close();
  });

  test('排队写入使用前一次提交后的设备偏好，不覆盖其他字段', () async {
    final notifier = container.read(preferencesProvider.notifier);
    final first = notifier.updateDevice(
      'device',
      const DevicePreferences(showNavigationBar: false),
    );
    final second = notifier.updateDevice(
      'device',
      const DevicePreferences(stayAwake: true),
    );
    await _flush(container);
    expect(settings.writes, hasLength(1));
    settings.writes[0].result.complete(
      Preferences(deviceSettings: settings.writes[0].patch.deviceSettings!),
    );
    await first;
    await _flush(container);
    final merged = settings.writes[1].patch.deviceSettings!['device']!;
    expect(merged.showNavigationBar, isFalse);
    expect(merged.stayAwake, isTrue);
    settings.writes[1].result.complete(
      Preferences(deviceSettings: {'device': merged}),
    );
    await second;
    expect(
      container.read(preferencesProvider).values.deviceSettings['device'],
      merged,
    );
  });

  test('权威设置事件作废在途写入，下一次写入合并新状态', () async {
    final notifier = container.read(preferencesProvider.notifier);
    final first = notifier.updateDevice(
      'device',
      const DevicePreferences(stayAwake: true),
    );
    final second = notifier.updateDevice(
      'device',
      const DevicePreferences(lockOnClose: true),
    );
    await _flush(container);
    events.add({
      'type': 'settings.changed',
      'data': {
        'appearance': 'dark',
        'deviceSettings': {
          'device': {'showNavigationBar': false},
        },
      },
    });
    settings.writes[0].result.complete(
      Preferences(appearance: Appearance.light),
    );
    await first;
    await _flush(container);
    expect(
      container.read(preferencesProvider).values.appearance,
      Appearance.dark,
    );
    final patch = settings.writes[1].patch.deviceSettings!['device']!;
    expect(patch.showNavigationBar, isFalse);
    expect(patch.lockOnClose, isTrue);
    expect(patch.stayAwake, isNull);
    settings.writes[1].result.complete(
      Preferences(
        appearance: Appearance.dark,
        deviceSettings: {'device': patch},
      ),
    );
    await second;
  });

  test('能力换源后不执行旧队列，旧回执也不能写入新代次', () async {
    final notifier = container.read(preferencesProvider.notifier);
    final first = notifier.update(
      PreferenceChanges(appearance: Appearance.dark),
    );
    final queued = notifier.update(PreferenceChanges(notificationAlerts: true));
    final loading = notifier.load();
    await _flush(container);
    final replacement = _Settings();
    container.updateOverrides([
      appSessionProvider.overrideWithValue(dependencies),
      settingsManagementProvider.overrideWithValue(replacement),
    ]);
    await _flush(container);
    final current = container.read(preferencesProvider.notifier);
    expect(current, same(notifier));
    final update = current.update(
      PreferenceChanges(appearance: Appearance.light),
    );
    await _flush(container);
    replacement.writes.single.result.complete(
      Preferences(appearance: Appearance.light),
    );
    await update;
    settings.writes.single.result.complete(
      Preferences(appearance: Appearance.dark),
    );
    settings.reads.single.complete(Preferences(appearance: Appearance.dark));
    await Future.wait([first, queued, loading]);
    expect(settings.writes, hasLength(1));
    expect(
      container.read(preferencesProvider).values.appearance,
      Appearance.light,
    );
  });

  test('显式写入作废更早的读取，离开 scope 后旧回执不再提交', () async {
    final notifier = container.read(preferencesProvider.notifier);
    final loading = notifier.load();
    final writing = notifier.update(
      PreferenceChanges(appearance: Appearance.dark),
    );
    await _flush(container);
    settings.writes.single.result.complete(
      Preferences(appearance: Appearance.dark),
    );
    await writing;
    settings.reads.single.complete(Preferences(appearance: Appearance.light));
    await loading;
    expect(
      container.read(preferencesProvider).values.appearance,
      Appearance.dark,
    );
    final retired = notifier.update(
      PreferenceChanges(appearance: Appearance.light),
    );
    await _flush(container);
    container.dispose();
    settings.writes.last.result.complete(
      Preferences(appearance: Appearance.light),
    );
    await retired;
  });
}

class _Settings implements SettingsManagement {
  final reads = <Completer<Preferences>>[];
  final writes = <({PreferenceChanges patch, Completer<Preferences> result})>[];
  @override
  Future<Preferences> read() {
    final result = Completer<Preferences>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<Preferences> update(
    PreferenceChanges changes, {
    int? expectedRevision,
  }) {
    final result = Completer<Preferences>();
    writes.add((patch: changes, result: result));
    return result.future;
  }
}

class _Session implements AppSession {
  _Session(this.events);
  @override
  final Stream<Map<String, dynamic>> events;
  @override
  AppState get initialState => AppState();
  @override
  bool get initialize => false;
  @override
  Future<void> Function()? get close => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
}
