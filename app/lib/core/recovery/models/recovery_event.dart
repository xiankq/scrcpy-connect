import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';

sealed class RecoveryEvent extends AppEvent {
  const RecoveryEvent();

  @override
  String get type => switch (this) {
    RecoveryStarted() => 'state.resync',
    RecoveryCompleted() => 'state.resynced',
    RecoveryFailed() => 'state.resync.failed',
  };
}

final class RecoveryStarted extends RecoveryEvent {
  const RecoveryStarted();
}

final class RecoveryCompleted extends RecoveryEvent {
  const RecoveryCompleted(this.snapshot);
  final RuntimeSnapshot snapshot;
}

final class RecoveryFailed extends RecoveryEvent {
  const RecoveryFailed(this.reason);
  final String reason;
}
