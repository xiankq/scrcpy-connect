import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';
import 'package:scrcpy_connect/core/settings/models/preferences_state.dart';
import 'package:scrcpy_connect/core/settings/preference_codec.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

import 'settings_capabilities_provider.dart';
import 'settings_management.dart';

part 'preferences_notifier.g.dart';

/// 偏好投影与串行写入的唯一所有者；权威事件作废旧写入回执。
@Riverpod(keepAlive: true)
class PreferencesNotifier extends _$PreferencesNotifier {
  late _PreferenceOwner _owner;

  @override
  PreferencesState build() {
    final session = ref.watch(stateSubscriptionProvider);
    final owner = _owner = _PreferenceOwner(
      session,
      ref.watch(settingsManagementProvider),
    );
    final initial = session.session.initialState;
    final subscription = session.stateEvents.listen((event) {
      if (!_current(owner)) return;
      final type = event['type'];
      if (type == 'state.resync' || type == 'state.resync.failed') {
        owner.request++;
        owner.epoch++;
      } else if (type == 'state.resynced' || type == 'settings.changed') {
        owner.request++;
        owner.epoch++;
        final data = jsonObject(event['data']);
        state = state.copyWith(
          values: PreferenceCodec.decode(
            type == 'state.resynced' ? jsonObject(data['settings']) : data,
          ),
          error: null,
        );
      }
    });
    ref.onDispose(() {
      owner.disposed = true;
      unawaited(subscription.cancel());
    });
    if (session.session.initialize) {
      scheduleMicrotask(() {
        if (_current(owner)) unawaited(load());
      });
    }
    return PreferencesState(
      values: initial.settings,
      error: initial.settingsError,
    );
  }

  bool _current(_PreferenceOwner owner) =>
      ref.mounted &&
      !owner.disposed &&
      !owner.session.disposed &&
      identical(_owner, owner);
  Future<void> load() async {
    final owner = _owner;
    final requestId = ++owner.request;
    try {
      final result = await owner.settings.read();
      if (_current(owner) && requestId == owner.request) {
        owner.epoch++;
        state = state.copyWith(values: result, error: null);
      }
    } catch (error) {
      if (_current(owner) && requestId == owner.request) {
        state = state.copyWith(error: '$error');
      }
    }
  }

  Future<void> _update(PreferenceChanges? Function(Preferences) changes) {
    final owner = _owner;
    owner.request++;
    final operation = owner.writes.catchError((Object _) {}).then((_) async {
      if (!_current(owner)) return;
      final patch = changes(state.values);
      if (patch == null) return;
      final epoch = owner.epoch;
      final result = await owner.settings.update(patch);
      if (_current(owner) && epoch == owner.epoch) {
        state = state.copyWith(values: result, error: null);
      }
    });
    owner.writes = operation;
    return operation;
  }

  Future<void> update(PreferenceChanges patch) => _update((_) => patch);

  Future<void> updateDevice(String deviceId, DevicePreferences patch) =>
      _update(
        (current) => PreferenceChanges(
          deviceSettings: {
            ...current.deviceSettings,
            deviceId:
                (current.deviceSettings[deviceId] ?? const DevicePreferences())
                    .merge(patch),
          },
        ),
      );

  AppOpenMode? appOpenMode(String deviceId, String packageName) =>
      state.values.appOpenModes[deviceId]?[packageName];

  Future<void> rememberAppOpenMode(
    String deviceId,
    String packageName,
    AppOpenMode mode,
  ) => _update((current) {
    final previous = current.appOpenModes;
    final device = previous[deviceId] ?? const <String, AppOpenMode>{};
    if (device[packageName] == mode) return null;
    return PreferenceChanges(
      appOpenModes: {
        ...previous,
        deviceId: {...device, packageName: mode},
      },
    );
  });
}

// 依赖重建时 Notifier 可保持身份；每批排队写入仍属于创建它的能力代次。
final class _PreferenceOwner {
  _PreferenceOwner(this.session, this.settings);
  final StateSubscription session;
  final SettingsManagement settings;
  Future<void> writes = Future.value();
  int request = 0, epoch = 0;
  bool disposed = false;
}
