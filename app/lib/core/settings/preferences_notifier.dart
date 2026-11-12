import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/application_session_provider.dart';

import 'preferences.dart';
import 'preference_codec.dart';

import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/core/application/application_session.dart';

import 'preferences_state.dart';

part 'preferences_notifier.g.dart';

/// 偏好投影与串行写入的唯一所有者；权威事件作废旧写入回执。
@Riverpod(keepAlive: true)
class PreferencesNotifier extends _$PreferencesNotifier {
  late ApplicationSession _session;
  Future<void> _writes = Future.value();
  int _request = 0, _epoch = 0;

  @override
  PreferencesState build() {
    final session = _session = ref.watch(applicationSessionProvider);
    _writes = Future.value();
    final initial = session.dependencies.initialState;
    final subscription = session.stateEvents.listen((event) {
      if (!_current(session)) return;
      final type = event['type'];
      if (type == 'state.resync' || type == 'state.resync.failed') {
        _request++;
        _epoch++;
      } else if (type == 'state.resynced' || type == 'settings.changed') {
        _request++;
        _epoch++;
        final data = jsonObject(event['data']);
        state = state.copyWith(
          values: PreferenceCodec.decode(
            type == 'state.resynced' ? jsonObject(data['settings']) : data,
          ),
          error: null,
        );
      }
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    if (session.dependencies.initialize) {
      scheduleMicrotask(() {
        if (_current(session)) unawaited(load());
      });
    }
    return PreferencesState(
      values: initial.settings,
      error: initial.settingsError,
    );
  }

  bool _current(ApplicationSession session) =>
      ref.mounted && !session.disposed && identical(_session, session);
  Future<void> load() async {
    final session = _session;
    final requestId = ++_request;
    try {
      final result = await session.dependencies.settings.read();
      if (_current(session) && requestId == _request) {
        _epoch++;
        state = state.copyWith(values: result, error: null);
      }
    } catch (error) {
      if (_current(session) && requestId == _request) {
        state = state.copyWith(error: '$error');
      }
    }
  }

  Future<void> _update(PreferenceChanges? Function(Preferences) changes) {
    final session = _session;
    _request++;
    final operation = _writes.catchError((Object _) {}).then((_) async {
      if (!_current(session)) return;
      final patch = changes(state.values);
      if (patch == null) return;
      final epoch = _epoch;
      final result = await session.dependencies.settings.update(patch);
      if (_current(session) && epoch == _epoch) {
        state = state.copyWith(values: result, error: null);
      }
    });
    _writes = operation;
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
