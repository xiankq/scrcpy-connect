import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

part 'recovery_state_notifier.g.dart';

@Riverpod(keepAlive: true)
class RecoveryStateNotifier extends _$RecoveryStateNotifier {
  @override
  RecoveryState build() {
    final session = ref.watch(stateSubscriptionProvider);
    final initial = session.session.initialState;
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
    return RecoveryState(
      lastEvent: initial.lastEvent,
      eventRevision: initial.eventRevision,
      reconciliationPending: initial.reconciliationPending,
      reconciliationError: initial.reconciliationError,
      reconciledSnapshot: initial.reconciledSnapshot,
    );
  }
}
