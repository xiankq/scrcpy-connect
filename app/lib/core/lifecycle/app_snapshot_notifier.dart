import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/current_device_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/files/share_inbox_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';
import 'package:scrcpy_connect/core/media/audio_error_notifier.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';

part 'app_snapshot_notifier.g.dart';

/// 跨能力原子只读投影；能力操作、状态写入和资源生命周期由各自所有者维护。
@Riverpod(keepAlive: true)
class AppSnapshotNotifier extends _$AppSnapshotNotifier {
  late StateSubscription _session;

  @override
  AppState build() {
    _session = ref.watch(stateSubscriptionProvider);
    // 同步组合只读投影，保证页面事件前已可读取状态；入口本身不随投影重建。
    void project() {
      if (ref.mounted && !_session.applyingState) state = _project();
    }

    ref.listen(deviceListProvider, (_, _) => project());
    ref.listen(preferencesProvider, (_, _) => project());
    ref.listen(shareInboxProvider, (_, _) => project());
    ref.listen(recoveryStateProvider, (_, _) => project());
    ref.listen(currentDeviceProvider, (_, _) => project());
    ref.listen(audioErrorProvider, (_, _) => project());
    final commits = _session.stateCommits.listen((_) => project());
    ref.onDispose(() => unawaited(commits.cancel()));
    return _project();
  }

  AppState _project() {
    final devices = ref.read(deviceListProvider);
    final preferences = ref.read(preferencesProvider);
    final shares = ref.read(shareInboxProvider);
    final status = ref.read(recoveryStateProvider);
    return AppState(
      devices: devices.devices,
      loading: devices.loading,
      deviceError: devices.error,
      settings: preferences.values,
      settingsError: preferences.error,
      pendingShares: shares.shares,
      lastEvent: status.lastEvent,
      eventRevision: status.eventRevision,
      audioError: ref.read(audioErrorProvider),
      focusedDeviceId: ref.read(currentDeviceProvider),
      reconciliationPending: status.reconciliationPending,
      reconciliationError: status.reconciliationError,
      reconciledSnapshot: status.reconciledSnapshot,
    );
  }
}
