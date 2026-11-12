import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';

part 'recovery_state_notifier.g.dart';

@Riverpod(keepAlive: true)
class RecoveryStateNotifier extends _$RecoveryStateNotifier {
  @override
  RecoveryState build() {
    final session = ref.watch(stateSubscriptionProvider);
    final initial = session.session.initialState;
    final subscription = session.stateEvents.listen((event) {
      if (!ref.mounted || session.disposed) return;
      final payload = event['data'];
      state = state.copyWith(
        lastEvent: event,
        eventRevision: state.eventRevision + 1,
        reconciliationPending: switch (payload) {
          RecoveryCompleted() => false,
          RecoveryStarted() || RecoveryFailed() => true,
          _ => state.reconciliationPending,
        },
        reconciliationError: switch (payload) {
          RecoveryFailed(:final reason) => reason,
          RecoveryStarted() || RecoveryCompleted() => null,
          _ => state.reconciliationError,
        },
        reconciledSnapshot: payload is RecoveryCompleted
            ? payload.snapshot
            : state.reconciledSnapshot,
      );
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    return RecoveryState(
      lastEvent: initial.lastEvent,
      eventRevision: initial.eventRevision,
      reconciliationPending: initial.reconciliationPending,
      reconciliationError: initial.reconciliationError,
      reconciledSnapshot: initial.reconciledSnapshot,
    );
  }
}
