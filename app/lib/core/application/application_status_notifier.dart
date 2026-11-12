import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/application_session_provider.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

import 'application_status.dart';

part 'application_status_notifier.g.dart';

@Riverpod(keepAlive: true)
class ApplicationStatusNotifier extends _$ApplicationStatusNotifier {
  @override
  ApplicationStatus build() {
    final session = ref.watch(applicationSessionProvider);
    final initial = session.dependencies.initialState;
    final subscription = session.stateEvents.listen((event) {
      if (!ref.mounted || session.disposed) return;
      final type = event['type'];
      final data = jsonObject(event['data']);
      state = state.copyWith(
        lastEvent: event,
        eventRevision: state.eventRevision + 1,
        reconciliationPending: type == 'state.resynced'
            ? false
            : type == 'state.resync' || type == 'state.resync.failed'
            ? true
            : state.reconciliationPending,
        reconciliationError: type == 'state.resync.failed'
            ? value(data, 'reason', '状态检查未完成，请重试。')
            : type == 'state.resync' || type == 'state.resynced'
            ? null
            : state.reconciliationError,
        reconciledSnapshot: type == 'state.resynced'
            ? data
            : state.reconciledSnapshot,
      );
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    return ApplicationStatus(
      lastEvent: initial.lastEvent,
      eventRevision: initial.eventRevision,
      audioError: initial.audioError,
      focusedDeviceId: initial.focusedDeviceId,
      reconciliationPending: initial.reconciliationPending,
      reconciliationError: initial.reconciliationError,
      reconciledSnapshot: initial.reconciledSnapshot,
    );
  }

  void updateAudioError(String? error) {
    if (ref.mounted && state.audioError != error) {
      state = state.copyWith(audioError: error);
    }
  }

  Future<void> focusDevice(String? id) async {
    if (ref.mounted && state.focusedDeviceId != id) {
      state = state.copyWith(focusedDeviceId: id);
    }
  }
}
